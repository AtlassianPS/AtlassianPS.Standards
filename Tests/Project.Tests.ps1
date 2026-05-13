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
    It 'loads analyzer settings as a hashtable' {
        $settingsCommand = Get-Command -Module 'AtlassianPS.Standards' |
            Where-Object { $_.CommandType -eq 'Function' -and $_.Verb -eq 'Get' -and $_.Name -like '*ScriptAnalyzerSettingsPath' } |
            Select-Object -First 1
        $settingsCommand | Should -Not -BeNullOrEmpty
        $settingsPath = & $settingsCommand.Name
        $settings = Import-PowerShellDataFile -Path $settingsPath

        $settings | Should -BeOfType [hashtable]
        $settings.IncludeRules | Should -Not -BeNullOrEmpty
        $settings.Rules | Should -Not -BeNullOrEmpty
    }
}
