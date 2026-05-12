BeforeAll {
    $moduleManifestPath = if ($env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST) {
        $env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST
    }
    else {
        Join-Path -Path $PSScriptRoot -ChildPath '../../../AtlassianPS.Standards/AtlassianPS.Standards.psd1'
    }

    Import-Module $moduleManifestPath -Force
}

AfterAll {
    Remove-Module AtlassianPS.Standards -ErrorAction SilentlyContinue
}

Describe 'Get-AtlassianPSScriptAnalyzerSettingsPath' {
    It 'is exported by the module' {
        $command = Get-Command -Name 'Get-AtlassianPSScriptAnalyzerSettingsPath' -Module 'AtlassianPS.Standards'
        $command | Should -Not -BeNullOrEmpty
    }

    It 'returns the full path to the shipped settings file' {
        $path = Get-AtlassianPSScriptAnalyzerSettingsPath

        $path | Should -Not -BeNullOrEmpty
        $path | Should -Match 'PSScriptAnalyzerSettings\.psd1$'
        (Test-Path -LiteralPath $path -PathType Leaf) | Should -BeTrue
    }

    It 'throws a clear error if the settings file is missing' {
        Mock -CommandName Test-Path -ModuleName AtlassianPS.Standards -MockWith { $false } -ParameterFilter {
            $PathType -eq 'Leaf'
        }

        {
            Get-AtlassianPSScriptAnalyzerSettingsPath
        } | Should -Throw -ExpectedMessage "Unable to locate PSScriptAnalyzer settings file*"
    }
}
