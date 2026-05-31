#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

Describe 'GitHub Actions' -Tag 'Lint', 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/Helpers/TestTools.ps1"
        $script:projectRoot = Resolve-ProjectRoot
        $script:validateReleaseIntentScriptPath = Join-Path -Path $script:projectRoot -ChildPath '.github/actions/validate-release-intent/validate-release-intent.ps1'
        $script:planMergedReleaseScriptPath = Join-Path -Path $script:projectRoot -ChildPath '.github/actions/plan-merged-release/plan-merged-release.ps1'
    }

    It 'action script parses for <ActionName>' -TestCases @(
        @{ ActionName = 'validate-release-intent' }
        @{ ActionName = 'prepare-release-changelog' }
        @{ ActionName = 'plan-merged-release' }
    ) {
        param($ActionName)

        $scriptPath = Join-Path -Path $projectRoot -ChildPath ".github/actions/$ActionName/$ActionName.ps1"
        $scriptText = [System.IO.File]::ReadAllText($scriptPath)
        $errors = $null

        $null = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'plan-merged-release computes the next tag and generated fragment for a merged PR' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/*/pulls') {
                '{"number":42,"title":"Fix release notes","user":"tester"}'
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
            if ($arguments[0] -eq 'tag' -and $arguments[1] -eq '--list') {
                'v1.2.3'
                'v1.3.0-beta'
                return
            }

            if ($arguments[0] -eq 'show-ref') {
                return
            }

            throw "Unexpected git invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'abc123'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=true'
        $output | Should -Match 'release_impact=minor'
        $output | Should -Match 'changelog_type=fixed'
        $output | Should -Match 'release_version=1.3.0'
        $output | Should -Match 'release_tag=v1.3.0'
        $output | Should -Match 'fragment_path=.changelog/42.minor.fixed.md'
        $output | Should -Match ([Regex]::Escape('fragment_content=* Fix release notes (#42, @tester)'))
    }

    It 'plan-merged-release skips release:none merged PRs' {
        function gh {
            $arguments = [String[]]$args
            $route = @($arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1)

            if ($route -like 'repos/*/commits/*/pulls') {
                '{"number":43,"title":"Update docs","user":"tester"}'
                return
            }

            if ($route -like 'repos/*/issues/*/labels') {
                'release:none'
                return
            }

            throw "Unexpected gh invocation: $($arguments -join ' ')"
        }

        $outputPath = Join-Path -Path $TestDrive -ChildPath 'github-output.txt'
        $previousRepository = $env:GITHUB_REPOSITORY
        $previousCommitSha = $env:COMMIT_SHA
        $previousChangelogDirectory = $env:CHANGELOG_DIRECTORY
        $previousOutput = $env:GITHUB_OUTPUT
        try {
            $env:GITHUB_REPOSITORY = 'AtlassianPS/AtlassianPS.Standards'
            $env:COMMIT_SHA = 'def456'
            $env:CHANGELOG_DIRECTORY = '.changelog'
            $env:GITHUB_OUTPUT = $outputPath

            & $script:planMergedReleaseScriptPath
        }
        finally {
            $env:GITHUB_REPOSITORY = $previousRepository
            $env:COMMIT_SHA = $previousCommitSha
            $env:CHANGELOG_DIRECTORY = $previousChangelogDirectory
            $env:GITHUB_OUTPUT = $previousOutput
        }

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'should_release=false'
        $output | Should -Match 'skip_reason=release:none'
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

- Added release intent validation.

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
        $content | Should -Match '- Added release intent validation\.'
        $content | Should -Match '\* Fixed generated release comments\. \(#42, @tester\)'
        Test-Path -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $repoPath -ChildPath 'Release/release-notes.md') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $runnerTemp -ChildPath 'release-notes.md') | Should -BeTrue

        $output = Get-Content -LiteralPath $outputPath -Raw
        $output | Should -Match 'release_version=v1.2.3'
        $output | Should -Match ([Regex]::Escape((Join-Path -Path $runnerTemp -ChildPath 'release-notes.md')))
    }
}
