#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"

    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Get-ScriptAnalyzerSettingsPath' {
    BeforeEach {
        $script:settingsCommand = Get-Command -Module 'AtlassianPS.Standards' |
            Where-Object { $_.CommandType -eq 'Function' -and $_.Verb -eq 'Get' -and $_.Name -like '*ScriptAnalyzerSettingsPath' } |
            Select-Object -First 1
    }

    It 'is exported by the module' {
        $script:settingsCommand | Should -Not -BeNullOrEmpty
    }

    It 'returns the full path to the shipped settings file' {
        $path = & $script:settingsCommand.Name

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
