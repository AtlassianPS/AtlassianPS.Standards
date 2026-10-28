function Test-ModulePackage {
    <#
    .SYNOPSIS
        Validates release module packaging artifacts without publishing.

    .DESCRIPTION
        Checks that the built module directory, manifest, and package archive exist,
        validates the manifest metadata resolves to the expected module name and a
        concrete version, then expands the package to verify that the archive contains
        the expected built module files and metadata.

    .PARAMETER BuildOutputPath
        Path to the build output directory, usually Release.

    .PARAMETER ModuleName
        Name of the module directory and manifest to validate.

    .PARAMETER PackagePath
        Optional explicit package archive path. Defaults to <BuildOutputPath>/<ModuleName>.zip.

    .PARAMETER ExpectedVersion
        Optional expected full version, including the exact prerelease label.

    .PARAMETER RequireReleaseNotes
        Require non-empty PrivateData.PSData.ReleaseNotes in both release manifest and package.

    .OUTPUTS
        PSCustomObject with ModulePath, ManifestPath, PackagePath, Name, and Version.

    .EXAMPLE
        Test-AtlassianPSModulePackage -BuildOutputPath './Release' -ModuleName 'JiraPS'

        Validates that Release/JiraPS and Release/JiraPS.zip contain matching manifests.
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
        [String]$PackagePath,

        [Parameter()]
        [String]$ExpectedVersion,

        [Parameter()]
        [Switch]$RequireReleaseNotes
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
    $manifestData = Import-PowerShellDataFile -LiteralPath $releaseManifestPath
    $fullVersion = $manifest.Version.ToString()
    if ($manifestData.PrivateData.PSData.Prerelease) {
        $fullVersion += '-' + $manifestData.PrivateData.PSData.Prerelease
    }
    if ($ExpectedVersion -and $fullVersion -cne $ExpectedVersion.TrimStart('v')) {
        throw "Release manifest version '$fullVersion' does not match expected '$ExpectedVersion'."
    }
    if ($RequireReleaseNotes -and [String]::IsNullOrWhiteSpace($manifestData.PrivateData.PSData.ReleaseNotes)) {
        throw 'Release manifest release notes are empty.'
    }
    $packageValidationRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "AtlassianPS-PackageValidation-$([Guid]::NewGuid().ToString('N'))"
    try {
        $null = New-Item -Path $packageValidationRoot -ItemType Directory -Force
        Expand-Archive -LiteralPath $PackagePath -DestinationPath $packageValidationRoot -Force
        $packagedManifestPath = Join-Path -Path (Join-Path -Path $packageValidationRoot -ChildPath $ModuleName) -ChildPath "$ModuleName.psd1"
        if (-not (Test-Path -LiteralPath $packagedManifestPath -PathType Leaf)) {
            throw "Release package '$PackagePath' does not contain expected manifest '$ModuleName/$ModuleName.psd1'."
        }

        $packagedManifest = Test-ModuleManifest -Path $packagedManifestPath -ErrorAction Stop
        if ($packagedManifest.Name -ne $ModuleName) {
            throw "Packaged manifest name '$($packagedManifest.Name)' does not match '$ModuleName'."
        }
        if ($packagedManifest.Version -ne $manifest.Version) {
            throw "Packaged manifest version '$($packagedManifest.Version)' does not match release manifest version '$($manifest.Version)'."
        }
        $packagedManifestData = Import-PowerShellDataFile -LiteralPath $packagedManifestPath
        if ([String]$packagedManifestData.PrivateData.PSData.Prerelease -cne [String]$manifestData.PrivateData.PSData.Prerelease) {
            throw 'Packaged manifest prerelease label does not match the release manifest.'
        }
        if ([String]$packagedManifestData.PrivateData.PSData.ReleaseNotes -cne [String]$manifestData.PrivateData.PSData.ReleaseNotes) {
            throw 'Packaged manifest release notes do not match the release manifest.'
        }
        $packagedModulePath = Split-Path $packagedManifestPath -Parent
        $builtFiles = @(Get-ChildItem -LiteralPath $releaseModulePath -Recurse -File -Force)
        $packagedFiles = @(Get-ChildItem -LiteralPath $packagedModulePath -Recurse -File -Force)
        if ($builtFiles.Count -ne $packagedFiles.Count) {
            throw 'Packaged file count differs from the built module.'
        }
        $resolvedModulePath = (Resolve-Path -LiteralPath $releaseModulePath).ProviderPath
        foreach ($file in $builtFiles) {
            $relativePath = $file.FullName.Substring($resolvedModulePath.Length + 1)
            $packagedFilePath = Join-Path $packagedModulePath $relativePath
            if (-not (Test-Path -LiteralPath $packagedFilePath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -cne
                (Get-FileHash -LiteralPath $packagedFilePath -Algorithm SHA256).Hash) {
                throw "Packaged file '$relativePath' differs from the built module."
            }
        }
    }
    catch {
        throw "Release package validation failed for '$PackagePath': $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $packageValidationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    [PSCustomObject]@{
        ModulePath   = $releaseModulePath
        ManifestPath = $releaseManifestPath
        PackagePath  = $PackagePath
        Name         = $manifest.Name
        Version      = $manifest.Version
        FullVersion  = $fullVersion
    }
}
