function Update-ModuleManifestExports {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$SourceModulePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuiltManifestPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName
    )

    if (-not (Get-Command -Name 'Metadata\Update-Metadata' -ErrorAction SilentlyContinue)) {
        throw "Metadata\Update-Metadata is not available. Ensure the required metadata tooling is installed."
    }

    if (-not (Test-Path -LiteralPath $BuiltManifestPath -PathType Leaf)) {
        throw "Built module manifest '$BuiltManifestPath' was not found."
    }

    $sourceManifestPath = Join-Path -Path $SourceModulePath -ChildPath "$ModuleName.psd1"
    if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
        throw "Source module manifest '$sourceManifestPath' was not found."
    }

    $moduleFunctions = @(
        Get-ChildItem -Path (Join-Path -Path $SourceModulePath -ChildPath 'Public/*.ps1') -ErrorAction SilentlyContinue
    ).BaseName
    $sourceModuleInfo = Test-ModuleManifest -Path $sourceManifestPath -ErrorAction Stop
    $moduleAlias = @($sourceModuleInfo.ExportedAliases.Keys)

    if ($PSCmdlet.ShouldProcess($BuiltManifestPath, 'Update exported functions and aliases')) {
        Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'FunctionsToExport' -Value @($moduleFunctions)
        Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'AliasesToExport' -Value ''

        if ($moduleAlias.Count -gt 0) {
            Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'AliasesToExport' -Value @($moduleAlias)
        }
    }

    return [PSCustomObject]@{
        FunctionsToExport = @($moduleFunctions)
        AliasesToExport   = @($moduleAlias)
    }
}
