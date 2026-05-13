@{
    RootModule           = 'AtlassianPS.Standards.psm1'
    ModuleVersion        = '0.1.1'
    GUID                 = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    Author               = 'AtlassianPS'
    CompanyName          = 'AtlassianPS'
    Copyright            = '(c) 2026 AtlassianPS. All rights reserved.'
    Description          = 'Shared analyzer settings and standards utilities for AtlassianPS modules.'
    PowerShellVersion    = '5.1'
    RequiredModules      = @(
        @{ ModuleName = 'Metadata'; RequiredVersion = '1.5.7' }
        @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = '1.25.0' }
    )

    FunctionsToExport    = @(
        'Copy-ModuleArtifacts'
        'Get-BuildEnvironmentInfo'
        'Get-ScriptAnalyzerSettingsPath'
        'Initialize-BuildEnvironment'
        'Invoke-Lint'
        'Invoke-ModuleTests'
        'Join-ModuleSource'
        'New-ModulePackage'
        'Publish-ModuleRelease'
        'Set-ModuleManifestVersion'
        'Sync-ScriptAnalyzerSettings'
        'Update-ModuleManifestExports'
        'Write-BuildInfo'
    )
    DefaultCommandPrefix = 'AtlassianPS'
    FileList             = @(
        'PSScriptAnalyzerSettings.psd1'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @(
                'AtlassianPS'
                'PSScriptAnalyzer'
                'Standards'
            )
            Prerelease   = ''
            LicenseUri   = 'https://github.com/AtlassianPS/AtlassianPS.Standards/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/AtlassianPS/AtlassianPS.Standards'
            ReleaseNotes = 'Initial shared standards module release.'
        }
    }
}
