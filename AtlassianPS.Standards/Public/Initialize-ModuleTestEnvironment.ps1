function Initialize-ModuleTestEnvironment {
    <#
    .SYNOPSIS
        Imports a module under test only when the on-disk source changed.

    .DESCRIPTION
        Resolves a module manifest, computes a lightweight source fingerprint from
        PowerShell and C# source files, and reuses the already-loaded module when it
        matches the current source tree. This gives Pester BeforeAll blocks a shared
        replacement for repo-local TestTools.ps1 import bootstrapping.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$StartPath = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS',

        [Parameter()]
        [Switch]$Global
    )

    $manifestPath = Resolve-ModuleSource -ModuleName $ModuleName -StartPath $StartPath -MarkerFileName $MarkerFileName
    $moduleDir = Split-Path -Path $manifestPath -Parent

    $fingerprint = (
        Get-ChildItem -LiteralPath $moduleDir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.cs' } |
            ForEach-Object { $_.LastWriteTimeUtc.Ticks } |
            Measure-Object -Maximum
    ).Maximum

    $loaded = @(
        Get-Module -Name $ModuleName |
            Where-Object { $_.ModuleBase -eq $moduleDir } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
    )

    if ($loaded.Count -gt 0) {
        $cached = & $loaded[0] { $script:__AtlassianPSTestImportFingerprint }
        if ($cached -eq $fingerprint) {
            return $manifestPath
        }
    }

    Get-Module |
        Where-Object { $_.RequiredModules.Name -eq $ModuleName } |
        Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue

    Import-Module -Name $manifestPath -Force -Global:$Global -ErrorAction Stop

    $loadedModule = @(
        Get-Module -Name $ModuleName |
            Where-Object { $_.ModuleBase -eq $moduleDir } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
    )
    if ($loadedModule.Count -eq 0) {
        throw "Failed to load module '$ModuleName' from '$moduleDir'."
    }

    & $loadedModule[0] { param($Fingerprint) $script:__AtlassianPSTestImportFingerprint = $Fingerprint } $fingerprint

    return $manifestPath
}
