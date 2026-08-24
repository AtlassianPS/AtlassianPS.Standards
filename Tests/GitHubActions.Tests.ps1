#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

Describe 'GitHub Actions' -Tag 'Lint', 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/Helpers/TestTools.ps1"
        $script:projectRoot = Resolve-ProjectRoot
        $script:validateReleaseIntentScriptPath = Join-Path -Path $script:projectRoot -ChildPath '.github/actions/validate-release-intent/validate-release-intent.ps1'
        $script:planMergedReleaseScriptPath = Join-Path -Path $script:projectRoot -ChildPath '.github/actions/plan-merged-release/plan-merged-release.ps1'
    }

    It 'pins every external workflow dependency to a full commit SHA' {
        $workflowRoot = Join-Path -Path $script:projectRoot -ChildPath '.github/workflows'
        foreach ($workflow in Get-ChildItem -LiteralPath $workflowRoot -Filter '*.yml') {
            $content = Get-Content -LiteralPath $workflow.FullName -Raw
            $references = [Regex]::Matches($content, '(?m)^\s*(?:-\s+)?uses:\s+(?<reference>[^\s#]+)')
            foreach ($match in $references) {
                $reference = $match.Groups['reference'].Value
                if ($reference.StartsWith('./')) {
                    continue
                }
                $reference | Should -Match '@[0-9a-f]{40}$' -Because $workflow.Name
            }
        }
    }

    It 'plan-merged-release computes the next tag and generated fragment for a merged PR' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/*/pulls') {
                '{"number":42,"title":"Fix release notes","user":{"login":"tester"},"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"abc123"}'
                return
            }

            if ($route -like 'repos/*/issues/*/labels') {
                'release:minor'
                'changelog:fixed'
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }

            if ($arguments[0] -eq 'rev-list') {
                'abc123'
                return
            }

            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--list') {
                'v1.2.3'
                'v1.3.0-beta'
                return
            }

            if ($arguments[0] -eq 'show-ref') {
                Set-Variable -Name LASTEXITCODE -Value 1 -Scope 1
                return
            }

            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'manual-github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousOutput = $env:GITHUB_OUTPUT
        $pushedLocation = $false
        try {
            Push-Location -Path $TestDrive
            $pushedLocation = $true
            Remove-Item -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog') -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'abc123'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:GITHUB_OUTPUT = $previousOutput
            if ($pushedLocation) {
                Pop-Location
            }
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=true'
        $output | Should -Match 'release_tag=v1.3.0'
        $fragmentPath = Join-Path -Path $TestDrive -ChildPath '.changelog/42.minor.fixed.md'
        (Get-Content -LiteralPath $fragmentPath -Raw) | Should -Match ([Regex]::Escape('* Fix release notes (#42, @tester)'))
        $output | Should -Not -Match 'fragment_path='
        $output | Should -Not -Match 'fragment_content='
    }

    It 'plan-merged-release skips release:none merged PRs' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/*/pulls') {
                '{"number":43,"title":"Update docs","user":{"login":"tester"},"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"def456"}'
                return
            }

            if ($route -like 'repos/*/issues/*/labels') {
                'release:none'
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'def456'
                return
            }
            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousOutput = $env:GITHUB_OUTPUT
        $pushedLocation = $false
        try {
            Push-Location -Path $TestDrive
            $pushedLocation = $true
            Remove-Item -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog') -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'def456'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:GITHUB_OUTPUT = $previousOutput
            if ($pushedLocation) {
                Pop-Location
            }
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=false'
    }

    It 'plan-merged-release batches merged pull requests and selects highest impact' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/first/pulls') {
                '{"number":43,"title":"First","user":{"login":"tester"},"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"abc123"}'
                return
            }
            if ($route -like 'repos/*/commits/second/pulls') {
                '{"number":44,"title":"Second","user":{"login":"tester"},"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"abc123"}'
                return
            }

            if ($route -like 'repos/*/issues/43/labels') {
                'release:patch'
                'changelog:fixed'
                return
            }
            if ($route -like 'repos/*/issues/44/labels') {
                'release:minor'
                'changelog:added'
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'first'
                'second'
                return
            }
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--list') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'show-ref') {
                Set-Variable -Name LASTEXITCODE -Value 1 -Scope 1
                return
            }
            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'batched-github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousOutput = $env:GITHUB_OUTPUT
        $pushedLocation = $false
        try {
            Push-Location -Path $TestDrive
            $pushedLocation = $true
            Remove-Item -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog') -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'head123'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:GITHUB_OUTPUT = $previousOutput
            if ($pushedLocation) {
                Pop-Location
            }
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=true'
        $output | Should -Match 'release_tag=v1.3.0'
        Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog/43.patch.fixed.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog/44.minor.added.md') | Should -BeTrue
        $output | Should -Not -Match 'fragment_path='
    }

    It 'plan-merged-release fails closed when merged pull requests cannot be read' {
        function gh {
            Set-Variable -Name LASTEXITCODE -Value 1 -Scope 1
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'unreadable-commit'
                return
            }
            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'head123'
            $env:GITHUB_OUTPUT = Join-Path -Path $TestDrive -ChildPath 'failed-api-output.txt'

            { & $script:planMergedReleaseScriptPath } |
                Should -Throw -ExpectedMessage "*Unable to read pull requests for commit 'unreadable-commit'*"
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:GITHUB_OUTPUT = $previousOutput
        }
    }

    It 'plan-merged-release computes a manual release without generating a PR fragment' {
        function gh {
            throw "Unexpected gh invocation: $($args -join ' ')"
        }

        $repositoryPath = Join-Path -Path $TestDrive -ChildPath 'manual-release-repo'
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousReleaseImpact = $env:RELEASE_IMPACT
        $previousOutput = $env:GITHUB_OUTPUT
        $pushedLocation = $false
        try {
            $null = New-Item -Path $repositoryPath -ItemType Directory
            Push-Location -Path $repositoryPath
            $pushedLocation = $true
            git init | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $repositoryPath -ChildPath 'README.md') -Value 'test'
            git add README.md
            git -c user.name='Test User' -c user.email='test@example.invalid' -c commit.gpgsign=false commit -m 'Initial commit' | Out-Null
            git -c tag.gpgsign=false tag -a v2.3.4 -m v2.3.4
            Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue

            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:RELEASE_IMPACT = 'patch'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:RELEASE_IMPACT = $previousReleaseImpact
            $env:GITHUB_OUTPUT = $previousOutput
            if ($pushedLocation) {
                Pop-Location
            }
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=true'
        $output | Should -Match 'release_tag=v2.3.5'
        $output | Should -Not -Match 'fragment_path='
        $output | Should -Not -Match 'fragment_content='
        $LASTEXITCODE | Should -Be 0
    }

    It 'plan-merged-release rejects breaking changes without a major release label' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/*/pulls') {
                '{"number":44,"title":"Change defaults","user":{"login":"tester"},"merged_at":"2026-01-01T00:00:00Z","merge_commit_sha":"ghi789"}'
                return
            }

            if ($route -like 'repos/*/issues/*/labels') {
                'release:minor'
                'changelog:breaking'
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'ghi789'
                return
            }
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--list') {
                'v1.2.3'
                return
            }

            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousOutput = $env:GITHUB_OUTPUT
        $pushedLocation = $false
        try {
            Push-Location -Path $TestDrive
            $pushedLocation = $true
            Remove-Item -LiteralPath (Join-Path -Path $TestDrive -ChildPath '.changelog') -Recurse -Force -ErrorAction SilentlyContinue
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'ghi789'
            $env:GITHUB_OUTPUT = $outputPath

            { & $script:planMergedReleaseScriptPath } | Should -Throw -ExpectedMessage '*breaking changelog fragments require release:major*'
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:GITHUB_OUTPUT = $previousOutput
            if ($pushedLocation) {
                Pop-Location
            }
        }
    }

    It 'builds one secretless candidate and promotes it without executing repository code' {
        $callerPath = Join-Path -Path $projectRoot -ChildPath '.github/workflows/continuous_release.yml'
        $workflowPath = Join-Path -Path $projectRoot -ChildPath '.github/workflows/module_release.yml'
        $caller = Get-Content -LiteralPath $callerPath -Raw
        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $publishWorkflow = $workflow.Substring($workflow.IndexOf('  publish:'))
        $ciWorkflow = Get-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath '.github/workflows/ci.yml') -Raw

        # Module repositories own only their trigger and module identity. Standards owns the
        # complete prepare/publish process and evaluates the caller's event context.
        $caller | Should -Match 'uses: \./\.github/workflows/module_release\.yml'
        $caller | Should -Match 'module-name: AtlassianPS\.Standards'
        $caller | Should -Match 'notify-homepage: false'
        $caller | Should -Match 'secrets: inherit'
        $caller | Should -Match '(?ms)permissions:\s+actions: read\s+contents: read\s+issues: read\s+pull-requests: read'
        $caller | Should -Not -Match 'Prepare release metadata|Publish-Module|create-github-app-token'
        $workflow | Should -Match '(?m)^\s+workflow_call:'
        $workflow | Should -Match 'repository: \$\{\{ job\.workflow_repository \}\}'
        $workflow | Should -Match 'ref: \$\{\{ job\.workflow_sha \}\}'
        $workflow | Should -Match 'uses: \./\.release-workflow/\.github/actions/plan-merged-release'

        # Only a metadata commit on master can start normal publication. Repository rulesets and
        # protected environments remain the enforcement boundary for writer provenance.
        $workflow | Should -Match "startsWith\(github\.event\.workflow_run\.head_commit\.message, 'Prepare v'\)"
        $workflow | Should -Match "github\.event\.workflow_run\.head_commit\.author\.name == 'github-actions\[bot\]'"
        $workflow | Should -Match "github\.ref == 'refs/heads/master'"
        $workflow | Should -Match 'environment: release'
        $workflow | Should -Match 'actions/create-github-app-token@[0-9a-f]{40}'
        $workflow | Should -Match 'ATLASSIANPS_RELEASE_APP_CLIENT_ID'
        $workflow | Should -Match 'ATLASSIANPS_RELEASE_APP_PRIVATE_KEY'
        $workflow | Should -Match 'uses: \./\.release-workflow/\.github/actions/commit-release-metadata'
        $workflow | Should -Match 'persist-credentials: false'
        $workflow | Should -Match "workflow_run\.event == 'push'"
        $workflow | Should -Match 'PREPARED_COMMIT_MESSAGE'

        # The build job stamps the artifact before platform tests consume it. Publishing starts
        # only after the complete CI workflow succeeds.
        $ciWorkflow | Should -Match 'name: Release'
        $ciWorkflow | Should -Match 'Invoke-Build -Task SetVersion'
        $ciWorkflow | Should -Not -Match 'Invoke-Build -Task SetVersion .*VerifyPublishedRelease'
        $ciWorkflow | Should -Match 'Invoke-Build -Task VerifyReleaseArtifact'
        $ciWorkflow | Should -Not -Match 'Invoke-Build -Task PackageGallery'
        $ciWorkflow | Should -Match 'if-no-files-found: error'
        $ciWorkflow | Should -Match 'path: \./Release/'
        $ciWorkflow | Should -Not -Match 'nupkg|gallery_package_path'
        $ciWorkflow | Should -Not -Match 'release-manifest\.json|packageSha256|galleryPackageSha256|releaseNotesSha256'
        $ciWorkflow | Should -Not -Match 'PSGALLERY_API_KEY|HOMEPAGE_PAT|ATLASSIANPS_RELEASE_APP_PRIVATE_KEY'
        $ciWorkflow | Should -Match 'failure\|cancelled\|skipped'

        # Promotion downloads the immutable artifact from the exact triggering run and executes
        # no checked-out repository actions or build commands while credentials are available.
        $publishWorkflow | Should -Match 'name: Release'
        $publishWorkflow | Should -Match 'actions/download-artifact@[0-9a-f]{40}'
        $publishWorkflow | Should -Match 'github-token: \$\{\{ github\.token \}\}'
        $publishWorkflow | Should -Match 'run-id: \$\{\{ github\.event\.workflow_run\.id \}\}'
        $publishWorkflow | Should -Match 'digest-mismatch: error'
        $publishWorkflow | Should -Not -Match 'dawidd6/action-download-artifact|release-manifest\.json|Get-FileHash|ZipFile'
        $publishWorkflow | Should -Match 'Publish-Module -Path \$modulePath'
        $publishWorkflow | Should -Match 'Find-Module -Name \$env:MODULE_NAME -RequiredVersion \$expectedGalleryVersion -Repository PSGallery'
        $publishWorkflow | Should -Match '\$installParameters\.RequiredVersion = \$dependency\.RequiredVersion'
        $publishWorkflow | Should -Match '\$installParameters\.MinimumVersion = \$dependency\.ModuleVersion'
        $publishWorkflow | Should -Match '\$installParameters\.MaximumVersion = \$dependency\.MaximumVersion'
        $publishWorkflow | Should -Match '(?ms)if \(\$dependency\.ModuleVersion\) \{.*?MinimumVersion.*?\}\s+if \(\$dependency\.MaximumVersion\) \{.*?MaximumVersion'
        $publishWorkflow | Should -Not -Match '(?m)Publish-Module[^\r\n]*-Force'
        $publishWorkflow | Should -Not -Match 'Publish-PSResource|Find-PSResource|nupkg|gallery_package_path'
        $workflow | Should -Match '(?ms)prepare:.*?permissions:\s+contents: read\s+issues: read\s+pull-requests: read'
        $publishWorkflow | Should -Match '(?ms)permissions:\s+actions: read\s+contents: read'
        $workflow | Should -Not -Match 'contents: write'
        $publishWorkflow | Should -Match '\$PSNativeCommandUseErrorActionPreference = \$true'
        $publishWorkflow | Should -Match 'token: \$\{\{ steps\.release_app\.outputs\.token \}\}'
        $publishWorkflow | Should -Not -Match 'GITHUB_TOKEN: \$\{\{ secrets\.GITHUB_TOKEN \}\}'
        $publishWorkflow | Should -Match '(?ms)if: inputs\.notify-homepage\s+uses: peter-evans/repository-dispatch@'
        $publishWorkflow | Should -Not -Match 'actions/checkout|setup-powershell|Invoke-Build|Compress-Archive|uses: \./\.release-workflow/'
        $workflow | Should -Not -Match 'recovery_tag|RECOVERY_TAG|No successful CI run was found for recovery commit'

        # Tag creation precedes the immutable PSGallery publication.
        $tagIndex = $publishWorkflow.IndexOf('Create annotated release tag')
        $publishIndex = $publishWorkflow.IndexOf('Publish-Module')
        $tagIndex | Should -BeGreaterThan -1
        $publishIndex | Should -BeGreaterThan $tagIndex

        $codeOwners = Get-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'CODEOWNERS')
        $codeOwners[0] | Should -Match '^\*\s+@atlassianps/maintainers$'
        $codeOwners[-1] | Should -Match '^docs/ReleaseBlueprint\.md\s+@atlassianps/ci-managers$'
    }

    It 'plan-merged-release publishes only batch-safe outputs' {
        $actionPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/plan-merged-release/action.yml'
        $action = Get-Content -LiteralPath $actionPath -Raw

        $action | Should -Match 'should_release:'
        $action | Should -Match 'release_tag:'
        $action | Should -Not -Match 'steps\.plan\.outputs\.(skip_reason|release_impact|release_version)'
        $action | Should -Not -Match 'fragment_path:'
        $action | Should -Not -Match 'fragment_content:'
        $action | Should -Not -Match 'pr_number:'
        $action | Should -Not -Match 'prerelease'
    }

    It 'keeps publishing secrets and publish tasks out of the build script' {
        $buildScriptPath = Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards.build.ps1'
        $buildScript = Get-Content -LiteralPath $buildScriptPath -Raw

        $buildScript | Should -Not -Match '(?m)^Task Publish\b'
        $buildScript | Should -Not -Match 'PSGalleryAPIKey'
        $buildScript | Should -Match '(?m)^Task Package\b'
        $buildScript | Should -Not -Match 'PackageGallery|Compress-PSResource|GalleryPackage'
        $buildScript | Should -Match '(?m)^Task VerifyReleaseArtifact Package,'
        $buildScript | Should -Match '(?m)^Task SetSourceVersion\b'
        $buildScript | Should -Match '(?m)^Task SetVersion\b'
        $buildScript | Should -Match '(?m)^Task TestPublish\b'
        $buildScript | Should -Not -Match 'VerifyPublishedRelease|EnforceGreaterThanPublished'
    }

    It 'does not keep a non-idempotent tag release workflow beside continuous release' {
        $workflowPath = Join-Path -Path $projectRoot -ChildPath '.github/workflows/release.yml'

        Test-Path -LiteralPath $workflowPath | Should -BeFalse
    }

    It 'validate-release-intent accepts deleted historical fragments during release preparation' {
        $scriptPath = $script:validateReleaseIntentScriptPath
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)
            $jqIndex = [Array]::IndexOf($arguments, '--jq')
            $query = if ($jqIndex -ge 0) { $arguments[$jqIndex + 1] } else { '' }

            if ($route -like 'repos/*/issues/*/labels') {
                'release:patch'
                'changelog:fixed'
                return
            }

            if ($route -like 'repos/*/pulls/*/files') {
                $files = @(
                    @{ filename = 'CHANGELOG.md'; status = 'modified' }
                    @{ filename = '.changelog/41.patch.fixed.md'; status = 'removed' }
                )

                if ($query -eq '.[].filename') {
                    $files | ForEach-Object { $_.filename }
                }
                elseif ($query -like '*status == "removed"*') {
                    $files | Where-Object { $_.status -eq 'removed' } | ForEach-Object { $_.filename }
                }
                return
            }

            if ($route -like 'repos/*/issues/*/comments') {
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'def456'
                return
            }
            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousPrNumber = $env:PR_NUMBER
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:PR_NUMBER = '42'
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:GITHUB_OUTPUT = $outputPath

            & $scriptPath
        }
        finally {
            $env:PR_NUMBER = $previousPrNumber
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'is_valid=true'
        $output | Should -Match 'release_impact=patch'
        $output | Should -Match 'changelog_type=fixed'
    }

    It 'validate-release-intent rejects <CaseName>' -TestCases @(
        @{
            CaseName        = 'missing release label'
            Labels          = @('changelog:fixed')
            Files           = @(@{ filename = 'Public/Get-Thing.ps1'; status = 'modified' })
            ExpectedPattern = 'Add exactly one release label'
        }
        @{
            CaseName        = 'invalid changelog fragment name'
            Labels          = @('release:patch')
            Files           = @(@{ filename = '.changelog/41.patch.fixed.md'; status = 'added' })
            ExpectedPattern = "Changelog fragment '.changelog/41.patch.fixed.md' must be named"
        }
        @{
            CaseName        = 'changelog label and fragment together'
            Labels          = @('release:patch', 'changelog:fixed')
            Files           = @(@{ filename = '.changelog/42.patch.fixed.md'; status = 'added' })
            ExpectedPattern = 'Use either one changelog label'
        }
        @{
            CaseName        = 'breaking changelog without major release'
            Labels          = @('release:minor', 'changelog:breaking')
            Files           = @(@{ filename = 'Public/Get-Thing.ps1'; status = 'modified' })
            ExpectedPattern = 'changelog:breaking and breaking changelog fragments require'
        }
    ) {
        param($Labels, $Files, $ExpectedPattern)

        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)
            $jqIndex = [Array]::IndexOf($arguments, '--jq')
            $query = if ($jqIndex -ge 0) { $arguments[$jqIndex + 1] } else { '' }

            if ($route -like 'repos/*/issues/*/labels') {
                $Labels
                return
            }

            if ($route -like 'repos/*/pulls/*/files') {
                if ($query -eq '.[].filename') {
                    $Files | ForEach-Object { $_.filename }
                }
                elseif ($query -like '*status == "removed"*') {
                    $Files | Where-Object { $_.status -eq 'removed' } | ForEach-Object { $_.filename }
                }
                return
            }

            if ($route -like 'repos/*/issues/*/comments') {
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        function git {
            $arguments = [String[]]$args
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--merged') {
                'v1.2.3'
                return
            }
            if ($arguments[0] -eq 'rev-list') {
                'def456'
                return
            }
            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousPrNumber = $env:PR_NUMBER
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:PR_NUMBER = '42'
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:GITHUB_OUTPUT = $outputPath

            $scriptOutput = & $script:validateReleaseIntentScriptPath 2>&1
        }
        finally {
            $env:PR_NUMBER = $previousPrNumber
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'is_valid=false'
        ($scriptOutput | Out-String) | Should -Match ([Regex]::Escape($ExpectedPattern))
    }

    It 'prepare-release-changelog folds fragments and writes notes outside the working tree by default' {
        $scriptPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/prepare-release-changelog/prepare-release-changelog.ps1'
        $repoPath = Join-Path -Path $TestDrive -ChildPath 'repo'
        $fragmentDirectory = Join-Path -Path $repoPath -ChildPath '.changelog'
        $runnerTemp = Join-Path -Path $TestDrive -ChildPath 'runner-temp'
        New-Item -Path $fragmentDirectory -ItemType Directory | Out-Null
        New-Item -Path $runnerTemp -ItemType Directory | Out-Null

        $changelogPath = Join-Path -Path $repoPath -ChildPath 'CHANGELOG.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

### Fixed

- Preserved an existing fixed entry.

### Fixed

- Preserved a second existing fixed entry.

## v1.2.2 - 2026-05-01

- Previous release.
'@
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') -Value '* Fixed generated release comments. (#42, @tester)'

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousChangelogPath = $env:CHANGELOG_PATH
        $previousReleaseVersion = $env:RELEASE_VERSION
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousReleaseNotesPath = $env:RELEASE_NOTES_PATH
        $previousRunnerTemp = $env:RUNNER_TEMP
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:CHANGELOG_PATH = $changelogPath
            $env:RELEASE_VERSION = 'v1.2.3'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:RELEASE_NOTES_PATH = ''
            $env:RUNNER_TEMP = $runnerTemp
            $env:GITHUB_OUTPUT = $outputPath

            & $scriptPath
        }
        finally {
            $env:CHANGELOG_PATH = $previousChangelogPath
            $env:RELEASE_VERSION = $previousReleaseVersion
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:RELEASE_NOTES_PATH = $previousReleaseNotesPath
            $env:RUNNER_TEMP = $previousRunnerTemp
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $content = (Get-Content -LiteralPath $changelogPath -Raw) -replace "`r`n", "`n"
        $content | Should -Match '## Unreleased\n\n## v1\.2\.3 - \d{4}-\d{2}-\d{2}'
        ([Regex]::Matches($content, '(?m)^### Fixed$')).Count | Should -Be 1
        $content | Should -Match '- Preserved an existing fixed entry\.'
        $content | Should -Match '- Preserved a second existing fixed entry\.'
        $content | Should -Match '\* Fixed generated release comments\. \(#42, @tester\)'
        $content | Should -Match '(?s)### Fixed\n\n- Preserved an existing fixed entry\.\n- Preserved a second existing fixed entry\.\n\* Fixed generated release comments\.'
        Test-Path -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $repoPath -ChildPath 'Release/release-notes.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $runnerTemp -ChildPath 'release-notes.md') | Should -BeTrue

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'release_version=v1.2.3'
        $output | Should -Match ([Regex]::Escape((Join-Path -Path $runnerTemp -ChildPath 'release-notes.md')))
    }

    It 'groups fragments under changelog headings in standard order' {
        $scriptPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/prepare-release-changelog/prepare-release-changelog.ps1'
        $repoPath = Join-Path -Path $TestDrive -ChildPath 'categorized-repo'
        $fragmentDirectory = Join-Path -Path $repoPath -ChildPath '.changelog'
        New-Item -Path $fragmentDirectory -ItemType Directory -Force | Out-Null

        $changelogPath = Join-Path -Path $repoPath -ChildPath 'CHANGELOG.md'
        Set-Content -LiteralPath $changelogPath -Value "# Changelog`n`n## Unreleased`n`n## v1.2.2 - 2026-05-01`n`n- Previous release."
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '44.patch.fixed.md') -Value '* Fixed the later defect.'
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '43.patch.changed.md') -Value '* Changed the test behavior.'

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'categorized-output.txt'
        $releaseNotesPath = Join-Path -Path $TestDrive -ChildPath 'categorized-notes.md'
        $previousChangelogPath = $env:CHANGELOG_PATH
        $previousReleaseVersion = $env:RELEASE_VERSION
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousReleaseNotesPath = $env:RELEASE_NOTES_PATH
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:CHANGELOG_PATH = $changelogPath
            $env:RELEASE_VERSION = 'v1.2.3'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:RELEASE_NOTES_PATH = $releaseNotesPath
            $env:GITHUB_OUTPUT = $outputPath

            & $scriptPath
        }
        finally {
            $env:CHANGELOG_PATH = $previousChangelogPath
            $env:RELEASE_VERSION = $previousReleaseVersion
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:RELEASE_NOTES_PATH = $previousReleaseNotesPath
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $content = (Get-Content -LiteralPath $changelogPath -Raw) -replace "`r`n", "`n"
        $content | Should -Match '(?s)### Changed\n\n\* Changed the test behavior\.\n\n### Fixed\n\n\* Fixed the later defect\.'
        (Get-Content -LiteralPath $releaseNotesPath -Raw) | Should -Match '### Changed'
    }

    It 'preserves heading-like text inside fenced code blocks' {
        $scriptPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/prepare-release-changelog/prepare-release-changelog.ps1'
        $repoPath = Join-Path -Path $TestDrive -ChildPath 'fenced-repo'
        $fragmentDirectory = Join-Path -Path $repoPath -ChildPath '.changelog'
        New-Item -Path $fragmentDirectory -ItemType Directory -Force | Out-Null

        $changelogPath = Join-Path -Path $repoPath -ChildPath 'CHANGELOG.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

### Changed

- Documented this example:

```markdown
### Fixed

- This is example text, not a changelog section.
```

## v1.2.2 - 2026-05-01

- Previous release.
'@
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') -Value '* Fixed the actual defect.'

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'fenced-output.txt'
        $previousChangelogPath = $env:CHANGELOG_PATH
        $previousReleaseVersion = $env:RELEASE_VERSION
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousReleaseNotesPath = $env:RELEASE_NOTES_PATH
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:CHANGELOG_PATH = $changelogPath
            $env:RELEASE_VERSION = 'v1.2.3'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:RELEASE_NOTES_PATH = Join-Path -Path $TestDrive -ChildPath 'fenced-notes.md'
            $env:GITHUB_OUTPUT = $outputPath

            & $scriptPath
        }
        finally {
            $env:CHANGELOG_PATH = $previousChangelogPath
            $env:RELEASE_VERSION = $previousReleaseVersion
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:RELEASE_NOTES_PATH = $previousReleaseNotesPath
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $content = (Get-Content -LiteralPath $changelogPath -Raw) -replace "`r`n", "`n"
        $content | Should -Match '(?s)```markdown\n### Fixed\n\n- This is example text, not a changelog section\.\n```'
        ([Regex]::Matches($content, '(?m)^### Fixed$')).Count | Should -Be 2
        $content | Should -Match '(?s)```\n\n### Fixed\n\n\* Fixed the actual defect\.'
    }
}
