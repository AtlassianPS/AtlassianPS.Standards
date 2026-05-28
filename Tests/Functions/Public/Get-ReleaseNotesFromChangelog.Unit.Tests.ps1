#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Get-ReleaseNotesFromChangelog' {
    It 'returns release notes for v-prefixed changelog headings' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## v1.2.3

- Added release flow.
- Fixed package metadata.

## v1.2.2

- Previous release.
'@

        $notes = InModuleScope AtlassianPS.Standards -Parameters @{ ChangelogPath = $changelogPath } {
            param($ChangelogPath)

            Get-ReleaseNotesFromChangelog -ChangelogPath $ChangelogPath -ReleaseVersion 'v1.2.3'
        }

        @($notes).Count | Should -Be 1
        ($notes -replace "`r`n", "`n") | Should -Be "- Added release flow.`n- Fixed package metadata."
    }

    It 'returns release notes for dated non-prefixed changelog headings' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG-dated.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## 3.0.0 - 2026-05-10

This is the release summary.

## 2.9.0 - 2026-04-01

Older release.
'@

        $notes = InModuleScope AtlassianPS.Standards -Parameters @{ ChangelogPath = $changelogPath } {
            param($ChangelogPath)

            Get-ReleaseNotesFromChangelog -ChangelogPath $ChangelogPath -ReleaseVersion '3.0.0'
        }

        $notes | Should -Be 'This is the release summary.'
    }

    It 'throws when the changelog section is missing or empty' {
        $changelogPath = Join-Path -Path $TestDrive -ChildPath 'CHANGELOG-empty.md'
        Set-Content -LiteralPath $changelogPath -Value @'
# Changelog

## v1.2.3

## v1.2.2

- Older release.
'@

        InModuleScope AtlassianPS.Standards -Parameters @{ ChangelogPath = $changelogPath } {
            param($ChangelogPath)

            { Get-ReleaseNotesFromChangelog -ChangelogPath $ChangelogPath -ReleaseVersion '1.2.3' } |
                Should -Throw -ExpectedMessage "Changelog section '## v1.2.3'*is empty."
            { Get-ReleaseNotesFromChangelog -ChangelogPath $ChangelogPath -ReleaseVersion '1.2.4' } |
                Should -Throw -ExpectedMessage "Could not find changelog section '## v1.2.4'*"
        }
    }
}
