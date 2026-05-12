function Get-AtlassianPSScriptAnalyzerSettingsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $settingsPath = Join-Path -Path $script:ModuleRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'

    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "Unable to locate PSScriptAnalyzer settings file at '$settingsPath'. Ensure AtlassianPS.Standards is installed correctly."
    }

    return (Resolve-Path -LiteralPath $settingsPath).ProviderPath
}
