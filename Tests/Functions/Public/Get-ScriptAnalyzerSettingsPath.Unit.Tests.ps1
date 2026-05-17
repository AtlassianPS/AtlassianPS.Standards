#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"

    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Get-ScriptAnalyzerSettingsPath' {
    It 'is exported by the module' {
        $command = Get-Command -Name 'Get-AtlassianPSScriptAnalyzerSettingsPath' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'returns the full path to the shipped settings file' {
        $path = Get-AtlassianPSScriptAnalyzerSettingsPath

        $path | Should -Not -BeNullOrEmpty
        $path | Should -Match 'PSScriptAnalyzerSettings\.psd1$'
        (Test-Path -LiteralPath $path -PathType Leaf) | Should -BeTrue
    }

    It 'throws a clear error if the settings file is missing' {
        InModuleScope AtlassianPS.Standards {
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $PathType -eq 'Leaf'
            }

            {
                Get-ScriptAnalyzerSettingsPath
            } | Should -Throw -ExpectedMessage "Unable to locate PSScriptAnalyzer settings file*"
        }
    }
}
