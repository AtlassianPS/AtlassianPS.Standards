function Initialize-ModuleTestEnvironment {
    <#
    .SYNOPSIS
        Imports a module under test only when the on-disk source changed.

    .DESCRIPTION
        Resolves a module manifest, computes a lightweight source fingerprint from
        PowerShell and C# source files, and reuses the already-loaded module when it
        matches the current source tree. This gives Pester BeforeAll blocks a shared
        replacement for repo-local TestTools.ps1 import bootstrapping.

    .PARAMETER ModuleName
        Name of the module under test.

    .PARAMETER StartPath
        Directory or file path to start repository-root discovery from. Defaults to the current directory.

    .PARAMETER MarkerFileName
        Repository-root marker file name. Defaults to CODEOWNERS.

    .PARAMETER Global
        Imports the module into the global session state. Use this when Pester tests need the module visible outside the helper scope.

    .OUTPUTS
        String. The manifest path used to import or reuse the module under test.

    .EXAMPLE
        BeforeAll {
            Import-Module AtlassianPS.Standards
            $script:moduleToTest = Initialize-AtlassianPSModuleTestEnvironment -ModuleName 'JiraPS' -StartPath $PSScriptRoot
        }

        Imports JiraPS for a Pester file, reusing the loaded module when its source fingerprint is unchanged.
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
