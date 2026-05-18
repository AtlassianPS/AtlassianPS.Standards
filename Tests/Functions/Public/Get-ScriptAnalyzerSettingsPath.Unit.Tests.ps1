#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"

    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Get-ScriptAnalyzerSettingsPath (internal)' {
    It 'is available inside module scope' {
        InModuleScope AtlassianPS.Standards {
            Get-Command -Name Get-ScriptAnalyzerSettingsPath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It 'returns the full path to the shipped settings file' {
        $path = InModuleScope AtlassianPS.Standards { Get-ScriptAnalyzerSettingsPath }

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
