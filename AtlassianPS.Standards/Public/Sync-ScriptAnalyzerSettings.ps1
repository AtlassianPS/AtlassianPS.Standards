function Sync-ScriptAnalyzerSettings {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([String])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DestinationPath
    )

    $sourceSettingsPath = Get-ScriptAnalyzerSettingsPath
    if (-not (Test-Path -LiteralPath $sourceSettingsPath -PathType Leaf)) {
        throw "Shared PSScriptAnalyzer settings file was not found at '$sourceSettingsPath'."
    }

    $destinationDirectory = Split-Path -Path $DestinationPath -Parent
    if ($destinationDirectory -and -not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        $null = New-Item -Path $destinationDirectory -ItemType Directory -Force
    }

    if ($PSCmdlet.ShouldProcess($DestinationPath, "Copy analyzer settings from '$sourceSettingsPath'")) {
        Copy-Item -LiteralPath $sourceSettingsPath -Destination $DestinationPath -Force -ErrorAction Stop
    }

    return (Resolve-Path -LiteralPath $DestinationPath).ProviderPath
}
