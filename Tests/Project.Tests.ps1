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
        $projectRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
        $manifestPath = Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1'
        $manifestData = Import-PowerShellDataFile -Path $manifestPath
        $privateFunctionNames = @(
            Get-ChildItem -Path (Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/Private/*.ps1') -ErrorAction SilentlyContinue
        ).BaseName
        $moduleCommands = @(
            Get-Command -Module AtlassianPS.Standards -CommandType Function | Select-Object -ExpandProperty Name
        )
        $normalizedModuleCommands = @(
            foreach ($moduleCommand in $moduleCommands) {
                $parts = $moduleCommand -split '-', 2
                if (
                    $parts.Count -eq 2 -and
                    $manifestData.DefaultCommandPrefix -and
                    $parts[1].StartsWith([string]$manifestData.DefaultCommandPrefix)
                ) {
                    '{0}-{1}' -f $parts[0], $parts[1].Substring(([string]$manifestData.DefaultCommandPrefix).Length)
                }
                else {
                    $moduleCommand
                }
            }
        )
        $privateExports = @(
            $normalizedModuleCommands | Where-Object { $_ -in $privateFunctionNames }
        )

        if ($privateExports.Count -gt 0) {
            throw "Private functions must not be exported. Found: $($privateExports -join ', ')"
        }
    }

    It 'loads analyzer settings as a hashtable' {
        $settingsPath = InModuleScope AtlassianPS.Standards { Get-ScriptAnalyzerSettingsPath }
        $settings = Import-PowerShellDataFile -Path $settingsPath

        $settings | Should -BeOfType [hashtable]
        $settings.IncludeRules | Should -Not -BeNullOrEmpty
        $settings.Rules | Should -Not -BeNullOrEmpty
    }
}
