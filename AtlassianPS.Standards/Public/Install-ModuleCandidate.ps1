function Install-ModuleCandidate {
    <#
    .SYNOPSIS
        Acquires and imports one exact alpha or beta into an isolated directory.

    .DESCRIPTION
        Gallery acquisition explicitly opts into prereleases. Local release archives
        require a SHA256 digest. Both routes verify the full manifest version and
        loaded path. Use a fresh process when changing candidate versions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9.]*$')]
        [String]
        $ModuleName,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+-(alpha|beta)\d{4}$')]
        [String]
        $RequiredVersion,

        [Parameter(Mandatory)]
        [String]
        $DestinationPath,

        [Parameter()]
        [String]
        $PackagePath,

        [Parameter()]
        [String]
        $PackageSha256
    )

    if (Get-Module -Name $ModuleName -All) {
        throw "Module '$ModuleName' is already loaded. Provision candidates in a fresh process."
    }

    if ($PackagePath -and $PackageSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'Local candidate archives require a SHA256 digest.'
    }

    if ($PackageSha256 -and -not $PackagePath) {
        throw 'PackageSha256 requires PackagePath.'
    }

    if ($PackagePath -and (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash -cne $PackageSha256.ToUpperInvariant()) {
        throw 'Candidate archive SHA256 mismatch.'
    }

    if (-not $PSCmdlet.ShouldProcess("$ModuleName $RequiredVersion", 'Acquire and import exact candidate')) { return }

    $root = Join-Path $DestinationPath ([Guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $root -ItemType Directory -Force

    if ($PackagePath) {
        Expand-Archive -LiteralPath $PackagePath -DestinationPath $root -ErrorAction Stop
    }
    else {
        Save-Module -Name $ModuleName -RequiredVersion $RequiredVersion -AllowPrerelease `
            -Repository PSGallery -Path $root -ErrorAction Stop
    }

    $manifests = @(Get-ChildItem -LiteralPath $root -Filter "$ModuleName.psd1" -Recurse -File)
    if ($manifests.Count -ne 1) {
        throw "Expected one '$ModuleName' candidate manifest, found $($manifests.Count)."
    }

    $manifestPath = $manifests[0].FullName
    $data = Import-PowerShellDataFile -LiteralPath $manifestPath -ErrorAction Stop
    $fullVersion = "$($data.ModuleVersion)-$($data.PrivateData.PSData.Prerelease)"

    if ($fullVersion -cne $RequiredVersion) {
        throw "Acquired '$fullVersion', expected exact candidate '$RequiredVersion'."
    }

    $expectedModulePath = Join-Path $manifests[0].DirectoryName $data.RootModule
    $expectedModulePath = (Resolve-Path -LiteralPath $expectedModulePath).ProviderPath

    $env:PSModulePath = $root + [IO.Path]::PathSeparator + $env:PSModulePath
    $loaded = Import-Module -Name $manifestPath -Global -Force -PassThru -ErrorAction Stop

    if (
        $loaded.Path -cne $expectedModulePath -or
        $loaded.Version -ne [Version]($RequiredVersion.Split('-')[0]) -or
        [String]$loaded.PrivateData.PSData.Prerelease -cne $RequiredVersion.Split('-')[1]
    ) {
        throw 'Loaded candidate path or full version differs from the acquired artifact.'
    }

    [PSCustomObject]@{
        Name         = $ModuleName
        FullVersion  = $fullVersion
        ManifestPath = $manifestPath
        ModulePath   = $loaded.Path
        RootPath     = $root
    }
}
