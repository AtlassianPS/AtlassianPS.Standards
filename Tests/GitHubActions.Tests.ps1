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
}
