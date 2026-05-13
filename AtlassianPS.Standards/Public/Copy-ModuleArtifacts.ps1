function Copy-ModuleArtifacts {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputPath,

        [Parameter()]
        [String[]]$AdditionalFiles = @(),

        [Parameter()]
        [Switch]$IncludeTests
    )

    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
    $sourceModulePath = Join-Path -Path $resolvedProjectPath -ChildPath $ModuleName
    if (-not (Test-Path -LiteralPath $sourceModulePath -PathType Container)) {
        throw "Module source path '$sourceModulePath' was not found."
    }

    if (-not (Test-Path -LiteralPath $BuildOutputPath -PathType Container)) {
        $null = New-Item -Path $BuildOutputPath -ItemType Directory -Force
    }

    $releaseModulePath = Join-Path -Path $BuildOutputPath -ChildPath $ModuleName
    if (-not (Test-Path -LiteralPath $releaseModulePath -PathType Container)) {
        $null = New-Item -Path $releaseModulePath -ItemType Directory -Force
    }
    Copy-Item -Path "$sourceModulePath/*" -Destination $releaseModulePath -Recurse -Force

    foreach ($file in $AdditionalFiles) {
        $sourceFile = if ([System.IO.Path]::IsPathRooted($file)) {
            $file
        }
        else {
            Join-Path -Path $resolvedProjectPath -ChildPath $file
        }

        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
            throw "Artifact source file '$sourceFile' was not found."
        }

        Copy-Item -Path $sourceFile -Destination $releaseModulePath -Force
    }

    if ($IncludeTests) {
        $testsPath = Join-Path -Path $resolvedProjectPath -ChildPath 'Tests'
        if (Test-Path -LiteralPath $testsPath -PathType Container) {
            Copy-Item -Path $testsPath -Destination $BuildOutputPath -Recurse -Force
        }
    }

    return [PSCustomObject]@{
        SourceModulePath  = $sourceModulePath
        ReleaseModulePath = $releaseModulePath
    }
}
