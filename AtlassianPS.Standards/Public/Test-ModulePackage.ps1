function Test-ModulePackage {
    <#
    .SYNOPSIS
        Validates release module packaging artifacts without publishing.

    .DESCRIPTION
        Checks that the built module directory, manifest, and package archives exist,
        validates the manifest metadata resolves to the expected module name and a
        concrete version, then expands the packages to verify that the archives contain
        the expected built module files and metadata.

    .PARAMETER BuildOutputPath
        Path to the build output directory, usually Release.

    .PARAMETER ModuleName
        Name of the module directory and manifest to validate.

    .PARAMETER PackagePath
        Optional explicit package archive path. Defaults to <BuildOutputPath>/<ModuleName>.zip.

    .PARAMETER GalleryPackagePath
        Optional PSGallery .nupkg path. When provided, every built module file must exist
        at the package root with identical contents.

    .PARAMETER ExpectedVersion
        Optional expected numeric module version.

    .PARAMETER RequireReleaseNotes
        Require non-empty PrivateData.PSData.ReleaseNotes in both release manifest and package.

    .PARAMETER ExpectedPrerelease
        Optional prerelease label expected in PrivateData.PSData.Prerelease.

    .OUTPUTS
        PSCustomObject with ModulePath, ManifestPath, PackagePath, GalleryPackagePath,
        Name, and Version.

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
        [String]$GalleryPackagePath,

        [Parameter()]
        [String]$ExpectedVersion,

        [Parameter()]
        [Switch]$RequireReleaseNotes,

        [Parameter()]
        [AllowEmptyString()]
        [String]$ExpectedPrerelease
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
    if ($GalleryPackagePath -and -not (Test-Path -LiteralPath $GalleryPackagePath -PathType Leaf)) {
        throw "PSGallery package was not created: $GalleryPackagePath"
    }

    $manifest = Test-ModuleManifest -Path $releaseManifestPath -ErrorAction Stop
    if ($manifest.Name -ne $ModuleName) {
        throw "Release manifest name '$($manifest.Name)' does not match '$ModuleName'."
    }
    if ($null -eq $manifest.Version) {
        throw 'Release manifest version could not be resolved.'
    }
    if ($ExpectedVersion -and $manifest.Version.ToString() -ne $ExpectedVersion) {
        throw "Release manifest version '$($manifest.Version)' does not match expected '$ExpectedVersion'."
    }
    $manifestData = Import-PowerShellDataFile -LiteralPath $releaseManifestPath
    if ($RequireReleaseNotes -and [String]::IsNullOrWhiteSpace($manifestData.PrivateData.PSData.ReleaseNotes)) {
        throw 'Release manifest release notes are empty.'
    }
    if ($PSBoundParameters.ContainsKey('ExpectedPrerelease') -and $manifestData.PrivateData.PSData.Prerelease -ne $ExpectedPrerelease) {
        throw "Release manifest prerelease '$($manifestData.PrivateData.PSData.Prerelease)' does not match expected '$ExpectedPrerelease'."
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
        if ($RequireReleaseNotes -and [String]::IsNullOrWhiteSpace($packagedManifestData.PrivateData.PSData.ReleaseNotes)) {
            throw 'Packaged manifest release notes are empty.'
        }
        if ($PSBoundParameters.ContainsKey('ExpectedPrerelease') -and $packagedManifestData.PrivateData.PSData.Prerelease -ne $ExpectedPrerelease) {
            throw "Packaged manifest prerelease '$($packagedManifestData.PrivateData.PSData.Prerelease)' does not match expected '$ExpectedPrerelease'."
        }
    }
    catch {
        throw "Release package validation failed for '$PackagePath': $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $packageValidationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($GalleryPackagePath) {
        $galleryValidationRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "AtlassianPS-GalleryValidation-$([Guid]::NewGuid().ToString('N'))"
        try {
            $null = New-Item -Path $galleryValidationRoot -ItemType Directory -Force
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory(
                (Resolve-Path -LiteralPath $GalleryPackagePath).ProviderPath,
                $galleryValidationRoot
            )

            $resolvedModulePath = (Resolve-Path -LiteralPath $releaseModulePath).ProviderPath.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            )
            foreach ($builtFile in Get-ChildItem -LiteralPath $resolvedModulePath -File -Recurse) {
                $relativePath = $builtFile.FullName.Substring($resolvedModulePath.Length).TrimStart(
                    [System.IO.Path]::DirectorySeparatorChar,
                    [System.IO.Path]::AltDirectorySeparatorChar
                )
                $galleryFilePath = Join-Path -Path $galleryValidationRoot -ChildPath $relativePath
                if (-not (Test-Path -LiteralPath $galleryFilePath -PathType Leaf)) {
                    throw "PSGallery package '$GalleryPackagePath' does not contain built module file '$relativePath'."
                }

                $builtHash = (Get-FileHash -LiteralPath $builtFile.FullName -Algorithm SHA256).Hash
                $galleryHash = (Get-FileHash -LiteralPath $galleryFilePath -Algorithm SHA256).Hash
                if ($galleryHash -ne $builtHash) {
                    throw "PSGallery package file '$relativePath' does not match the built module."
                }
            }

            $galleryManifestPath = Join-Path -Path $galleryValidationRoot -ChildPath "$ModuleName.psd1"
            $galleryManifest = Test-ModuleManifest -Path $galleryManifestPath -ErrorAction Stop
            if ($galleryManifest.Name -ne $ModuleName) {
                throw "PSGallery manifest name '$($galleryManifest.Name)' does not match '$ModuleName'."
            }
            if ($galleryManifest.Version -ne $manifest.Version) {
                throw "PSGallery manifest version '$($galleryManifest.Version)' does not match release manifest version '$($manifest.Version)'."
            }
            $galleryManifestData = Import-PowerShellDataFile -LiteralPath $galleryManifestPath
            if ($RequireReleaseNotes -and [String]::IsNullOrWhiteSpace($galleryManifestData.PrivateData.PSData.ReleaseNotes)) {
                throw 'PSGallery manifest release notes are empty.'
            }
            if ($PSBoundParameters.ContainsKey('ExpectedPrerelease') -and $galleryManifestData.PrivateData.PSData.Prerelease -ne $ExpectedPrerelease) {
                throw "PSGallery manifest prerelease '$($galleryManifestData.PrivateData.PSData.Prerelease)' does not match expected '$ExpectedPrerelease'."
            }

            $nuspecFiles = @(Get-ChildItem -LiteralPath $galleryValidationRoot -Filter '*.nuspec' -File -Recurse)
            if ($nuspecFiles.Count -ne 1) {
                throw "PSGallery package must contain exactly one nuspec file; found $($nuspecFiles.Count)."
            }

            [xml]$nuspec = Get-Content -LiteralPath $nuspecFiles[0].FullName -Raw -ErrorAction Stop
            $manifestPrerelease = [String]$manifestData.PrivateData.PSData.Prerelease
            $expectedGalleryVersion = if ($manifestPrerelease) {
                "$($manifest.Version)-$manifestPrerelease"
            }
            else {
                $manifest.Version.ToString()
            }
            $manifestReleaseNotes = ([String]$manifestData.PrivateData.PSData.ReleaseNotes -replace "`r`n|`r", "`n").Trim()
            $nuspecReleaseNotes = ([String]$nuspec.package.metadata.releaseNotes -replace "`r`n|`r", "`n").Trim()

            if ([String]$nuspec.package.metadata.id -ne $ModuleName) {
                throw "PSGallery nuspec ID '$($nuspec.package.metadata.id)' does not match '$ModuleName'."
            }
            if ([String]$nuspec.package.metadata.version -ne $expectedGalleryVersion) {
                throw "PSGallery nuspec version '$($nuspec.package.metadata.version)' does not match '$expectedGalleryVersion'."
            }
            if ($nuspecReleaseNotes -ne $manifestReleaseNotes) {
                throw 'PSGallery nuspec release notes do not match the release manifest.'
            }
        }
        catch {
            throw "PSGallery package validation failed for '$GalleryPackagePath': $($_.Exception.Message)"
        }
        finally {
            Remove-Item -LiteralPath $galleryValidationRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    [PSCustomObject]@{
        ModulePath         = $releaseModulePath
        ManifestPath       = $releaseManifestPath
        PackagePath        = $PackagePath
        GalleryPackagePath = $GalleryPackagePath
        Name               = $manifest.Name
        Version            = $manifest.Version
    }
}
