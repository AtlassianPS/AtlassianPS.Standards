BeforeAll {
    $moduleManifestPath = if ($env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST) {
        $env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST
    }
    else {
        Join-Path -Path $PSScriptRoot -ChildPath '../AtlassianPS.Standards/AtlassianPS.Standards.psd1'
    }

    Import-Module $moduleManifestPath -Force
}

AfterAll {
    Remove-Module AtlassianPS.Standards -ErrorAction SilentlyContinue
}

Describe 'Project validation' {
    It 'loads analyzer settings as a hashtable' {
        $settingsPath = Get-AtlassianPSScriptAnalyzerSettingsPath
        $settings = Import-PowerShellDataFile -Path $settingsPath

        $settings | Should -BeOfType [hashtable]
        $settings.IncludeRules | Should -Not -BeNullOrEmpty
        $settings.Rules | Should -Not -BeNullOrEmpty
    }
}
