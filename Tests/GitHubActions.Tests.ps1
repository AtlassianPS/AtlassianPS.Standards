#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

Describe 'GitHub Actions' -Tag 'Lint', 'Unit' {
    BeforeAll {
        . "$PSScriptRoot/Helpers/TestTools.ps1"
        $script:projectRoot = Resolve-ProjectRoot
    }

    It 'validate-release-intent embedded PowerShell parses' {
        $actionPath = Join-Path -Path $projectRoot -ChildPath '.github/actions/validate-release-intent/action.yml'
        $lines = [System.IO.File]::ReadAllLines($actionPath)
        $runLineIndex = [Array]::FindIndex($lines, [Predicate[String]] { param($line) $line -eq '      run: |' })

        $runLineIndex | Should -BeGreaterOrEqual 0

        $scriptLines = @(
            for ($i = $runLineIndex + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '^        (.*)$') {
                    $Matches[1]
                }
            }
        )
        $scriptText = $scriptLines -join [Environment]::NewLine
        $errors = $null

        $null = [System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$null, [ref]$errors)

        $errors | Should -BeNullOrEmpty
    }
}
