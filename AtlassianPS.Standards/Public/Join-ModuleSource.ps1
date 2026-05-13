function Join-ModuleSource {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ReleaseModulePath,

        [Parameter()]
        [String[]]$SourceFolders = @('Public', 'Private'),

        [Parameter()]
        [String[]]$RegionsToKeep = @('Dependencies', 'Configuration'),

        [Parameter()]
        [Boolean]$RemoveSourceFolders = $true
    )

    $resolvedReleaseModulePath = (Resolve-Path -LiteralPath $ReleaseModulePath).ProviderPath
    $releaseRootPath = [System.IO.Path]::GetFullPath($resolvedReleaseModulePath)
    if (-not $releaseRootPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $releaseRootPath += [System.IO.Path]::DirectorySeparatorChar
    }

    $validatedSourceFolders = @(
        foreach ($folder in $SourceFolders) {
            if ([string]::IsNullOrWhiteSpace($folder)) {
                throw 'SourceFolders cannot contain empty values.'
            }

            if ([System.IO.Path]::IsPathRooted($folder)) {
                throw "Source folder '$folder' must be relative to the release module path."
            }

            $sourceFolderPath = Join-Path -Path $resolvedReleaseModulePath -ChildPath $folder
            $resolvedSourceFolderPath = [System.IO.Path]::GetFullPath($sourceFolderPath)
            if (-not $resolvedSourceFolderPath.StartsWith($releaseRootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Source folder '$folder' resolves outside release module path '$resolvedReleaseModulePath'."
            }

            [PSCustomObject]@{
                Name = $folder
                Path = $resolvedSourceFolderPath
            }
        }
    )

    $moduleName = Split-Path -Path $resolvedReleaseModulePath -Leaf
    $targetFile = Join-Path -Path $resolvedReleaseModulePath -ChildPath "$moduleName.psm1"

    if (-not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
        throw "Module source file '$targetFile' was not found."
    }

    $content = Get-Content -Encoding UTF8 -LiteralPath $targetFile
    $capture = $false
    $regions = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($region in $RegionsToKeep) {
        $null = $regions.Add($region)
    }

    $compiled = [System.Text.StringBuilder]::new()

    foreach ($line in $content) {
        if ($line -match '^#region\s+(.+)$') {
            $capture = $regions.Contains($Matches[1].Trim())
        }

        if ($capture) {
            $null = $compiled.Append($line)
            $null = $compiled.Append("`r`n")
        }

        if ($capture -and $line -match '^#endregion\b') {
            $capture = $false
        }
    }

    $sourceFiles = foreach ($sourceFolder in $validatedSourceFolders) {
        if (Test-Path -LiteralPath $sourceFolder.Path -PathType Container) {
            Get-ChildItem -LiteralPath $sourceFolder.Path -Filter '*.ps1' -File -ErrorAction SilentlyContinue
        }
    }
    $sourceFiles = @(
        $sourceFiles | Sort-Object -Property FullName
    )

    foreach ($file in $sourceFiles) {
        $fileContent = Get-Content -LiteralPath $file.FullName -Raw
        $null = $compiled.Append($fileContent)
        if ($fileContent -and $fileContent[-1] -ne "`n") {
            $null = $compiled.Append("`r`n")
        }
    }

    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($targetFile, $compiled.ToString(), $utf8Bom)

    if ($RemoveSourceFolders) {
        foreach ($sourceFolder in $validatedSourceFolders) {
            if (Test-Path -LiteralPath $sourceFolder.Path -PathType Container) {
                Remove-Item -LiteralPath $sourceFolder.Path -Recurse -Force
            }
        }
    }

    return $targetFile
}
