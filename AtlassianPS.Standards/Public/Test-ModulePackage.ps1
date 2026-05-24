function Test-ModulePackage {
    <#
    .SYNOPSIS
        Validates release module packaging artifacts without publishing.

    .DESCRIPTION
        Checks that the built module directory, manifest, and package archive exist,
        then validates the manifest metadata resolves to the expected module name and
        a concrete version.

    .PARAMETER BuildOutputPath
        Path to the build output directory, usually Release.

    .PARAMETER ModuleName
        Name of the module directory and manifest to validate.

    .PARAMETER PackagePath
        Optional explicit package archive path. Defaults to <BuildOutputPath>/<ModuleName>.zip.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$PackagePath
    )

    $releaseModulePath = Join-Path -Path $BuildOutputPath -ChildPath $ModuleName
    $releaseManifestPath = Join-Path -Path $releaseModulePath -ChildPath "$ModuleName.psd1"
    if (-not $PackagePath) {
        $PackagePath = Join-Path -Path $BuildOutputPath -ChildPath "$ModuleName.zip"
    }

    if (-not (Test-Path -LiteralPath $releaseModulePath -PathType Container)) {
        throw "Release module directory was not created: $releaseModulePath"
    }
    if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
        throw "Release manifest was not created: $releaseManifestPath"
    }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw "Release package was not created: $PackagePath"
    }

    $manifest = Test-ModuleManifest -Path $releaseManifestPath -ErrorAction Stop
    if ($manifest.Name -ne $ModuleName) {
        throw "Release manifest name '$($manifest.Name)' does not match '$ModuleName'."
    }
    if ($null -eq $manifest.Version) {
        throw 'Release manifest version could not be resolved.'
    }

    [PSCustomObject]@{
        ModulePath   = $releaseModulePath
        ManifestPath = $releaseManifestPath
        PackagePath  = $PackagePath
        Name         = $manifest.Name
        Version      = $manifest.Version
    }
}
