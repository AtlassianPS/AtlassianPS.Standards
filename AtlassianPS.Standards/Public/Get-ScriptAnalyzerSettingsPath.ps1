function Get-ScriptAnalyzerSettingsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
    if (-not $moduleBase) {
        throw 'Unable to resolve AtlassianPS.Standards module base path.'
    }

    $settingsPath = Join-Path -Path $moduleBase -ChildPath 'PSScriptAnalyzerSettings.psd1'

    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "Unable to locate PSScriptAnalyzer settings file at '$settingsPath'. Ensure AtlassianPS.Standards is installed correctly."
    }

    return (Resolve-Path -LiteralPath $settingsPath).ProviderPath
}
