#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

Describe 'GitHub Actions' -Tag 'Lint', 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/Helpers/TestTools.ps1"
        $script:projectRoot = Resolve-ProjectRoot
    }

    It 'action script parses for <ActionName>' -TestCases @(
        @{ ActionName = 'validate-release-intent' }
        @{ ActionName = 'prepare-release-changelog' }
    ) {
        param($ActionName)

        $scriptPath = Join-Path -Path $projectRoot -ChildPath ".github/actions/$ActionName/$ActionName.ps1"
        $scriptText = [System.IO.File]::ReadAllText($scriptPath)
        $errors = $null

        $null = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }

    It 'validate-release-intent accepts deleted historical fragments during release preparation' {
        $scriptPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/validate-release-intent/validate-release-intent.ps1'
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
