BeforeAll {
    $moduleManifestPath = if ($env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST) {
        $env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST
    }
    else {
        Join-Path -Path $PSScriptRoot -ChildPath '../AtlassianPS.Standards/AtlassianPS.Standards.psd1'
    }

    Import-Module $moduleManifestPath -Force
}

Describe 'Project validation' {
    It 'does not export internal helper commands' {
        $moduleCommands = Get-Command -Module AtlassianPS.Standards | Select-Object -ExpandProperty Name

        $moduleCommands | Should -Not -Contain 'Get-AtlassianPSBuildEnvironmentInfo'
        $moduleCommands | Should -Not -Contain 'Get-AtlassianPSScriptAnalyzerSettingsPath'
    }

    It 'loads analyzer settings as a hashtable' {
        $settingsPath = InModuleScope AtlassianPS.Standards { Get-ScriptAnalyzerSettingsPath }
        $settings = Import-PowerShellDataFile -Path $settingsPath

        $settings | Should -BeOfType [hashtable]
        $settings.IncludeRules | Should -Not -BeNullOrEmpty
        $settings.Rules | Should -Not -BeNullOrEmpty
    }
}
