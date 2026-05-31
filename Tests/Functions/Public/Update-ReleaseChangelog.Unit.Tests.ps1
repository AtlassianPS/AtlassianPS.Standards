#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Update-ReleaseChangelog' {
    It 'creates a release section from unreleased entries and deletes consumed fragments' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG.md'
        $fragmentDirectory = Join-Path -Path $TestDrive -ChildPath '.changelog'
        New-Item -Path $fragmentDirectory -ItemType Directory | Out-Null
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

- Added release intent validation.

## v1.2.2 - 2026-05-01

- Previous release.
'@
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') -Value '* Fixed generated release comments. (#42, @tester)'

        $result = InModuleScope AtlassianPS.Standards -Parameters @{
            ChangelogPath      = $changelogPath
            ChangelogDirectory = $fragmentDirectory
        } {
            param($ChangelogPath, $ChangelogDirectory)

            Update-ReleaseChangelog `
                -ChangelogPath $ChangelogPath `
                -ReleaseVersion 'v1.2.3' `
                -ChangelogDirectory $ChangelogDirectory `
                -ReleaseDate ([DateTime]'2026-05-31')
        }

        $content = Get-Content -LiteralPath $changelogPath -Raw
        $expectedContent = @'
# Changelog

## Unreleased

## v1.2.3 - 2026-05-31

- Added release intent validation.
* Fixed generated release comments. (#42, @tester)

## v1.2.2 - 2026-05-01

- Previous release.
'@
        ($content -replace "`r`n", "`n") | Should -Be (($expectedContent -replace "`r`n", "`n") + "`n")
        Test-Path -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '42.patch.fixed.md') | Should -BeFalse
        $result.ReleaseVersion | Should -Be 'v1.2.3'
        @($result.ChangelogFragmentPath).Count | Should -Be 1
        ($result.ReleaseNotes -replace "`r`n", "`n") | Should -Be "- Added release intent validation.`n* Fixed generated release comments. (#42, @tester)"
    }

    It 'creates a release section from fragments when Unreleased is empty' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG-fragment-only.md'
        $fragmentDirectory = Join-Path -Path $TestDrive -ChildPath 'fragment-only'
        New-Item -Path $fragmentDirectory -ItemType Directory | Out-Null
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

## v1.2.2

- Previous release.
'@
        Set-Content -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '43.minor.added.md') -Value '* Added fragment-only release notes. (#43, @tester)'

        $result = InModuleScope AtlassianPS.Standards -Parameters @{
            ChangelogPath      = $changelogPath
            ChangelogDirectory = $fragmentDirectory
        } {
            param($ChangelogPath, $ChangelogDirectory)

            Update-ReleaseChangelog `
                -ChangelogPath $ChangelogPath `
                -ReleaseVersion '1.2.3' `
                -ChangelogDirectory $ChangelogDirectory `
                -ReleaseDate ([DateTime]'2026-05-31')
        }

        $result.ReleaseNotes | Should -Be '* Added fragment-only release notes. (#43, @tester)'
        Test-Path -LiteralPath (Join-Path -Path $fragmentDirectory -ChildPath '43.minor.added.md') | Should -BeFalse
    }

    It 'throws when the release section already exists' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG-existing.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

- Pending change.

## v1.2.3 - 2026-05-31

- Existing release.
'@

        InModuleScope AtlassianPS.Standards -Parameters @{ ChangelogPath = $changelogPath } {
            param($ChangelogPath)

            { Update-ReleaseChangelog -ChangelogPath $ChangelogPath -ReleaseVersion 'v1.2.3' } |
                Should -Throw -ExpectedMessage "Changelog section '## v1.2.3' already exists*"
        }
    }

    It 'throws for invalid fragment names and leaves files unchanged' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG-invalid.md'
        $fragmentDirectory = Join-Path -Path $TestDrive -ChildPath 'invalid-fragments'
        New-Item -Path $fragmentDirectory -ItemType Directory | Out-Null
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## Unreleased

- Pending change.
'@
        $fragmentPath = Join-Path -Path $fragmentDirectory -ChildPath 'not-a-fragment.md'
        Set-Content -LiteralPath $fragmentPath -Value '* Invalid.'

        InModuleScope AtlassianPS.Standards -Parameters @{
            ChangelogPath      = $changelogPath
            ChangelogDirectory = $fragmentDirectory
        } {
            param($ChangelogPath, $ChangelogDirectory)

            { Update-ReleaseChangelog -ChangelogPath $ChangelogPath -ReleaseVersion 'v1.2.3' -ChangelogDirectory $ChangelogDirectory } |
                Should -Throw -ExpectedMessage "Changelog fragment '*' must be named*"
        }
        Test-Path -LiteralPath $fragmentPath | Should -BeTrue
    }
}
