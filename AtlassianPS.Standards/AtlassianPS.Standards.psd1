@{
    RootModule           = 'AtlassianPS.Standards.psm1'
    ModuleVersion        = '0.2.0'
    GUID                 = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    Author               = 'AtlassianPS'
    CompanyName          = 'AtlassianPS'
    Copyright            = '(c) 2026 AtlassianPS contributors.'
    Description          = 'Shared analyzer settings and standards utilities for AtlassianPS modules.'
    PowerShellVersion    = '5.1'
    RequiredModules      = @(
        @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = '1.25.0' }
    )

    FunctionsToExport    = '*'
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
            ReleaseNotes = ''
        }
    }
}
