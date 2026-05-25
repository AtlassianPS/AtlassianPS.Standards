function Resolve-ModuleSource {
    <#
    .SYNOPSIS
        Resolves a module manifest path for source or release test runs.

    .DESCRIPTION
        Resolves the repository root, switches to the Release root when tests are
        running from a built artifact, and returns the module manifest path for the
        requested module.

    .PARAMETER ModuleName
        Name of the module directory and manifest file to resolve.

    .PARAMETER StartPath
        Directory or file path to start repository-root discovery from. Defaults to the current directory.

    .PARAMETER MarkerFileName
        Repository-root marker file name. Defaults to CODEOWNERS.

    .OUTPUTS
        String. The resolved module manifest path.

    .EXAMPLE
        Resolve-AtlassianPSModuleSource -ModuleName 'JiraPS' -StartPath $PSScriptRoot

        Resolves JiraPS/JiraPS.psd1 from source tests, or Release/JiraPS/JiraPS.psd1 from release-artifact tests.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$StartPath = '.',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS'
    )

    $root = Resolve-ProjectRoot -StartPath $StartPath -MarkerFileName $MarkerFileName
    $resolvedStartPath = (Resolve-Path -LiteralPath $StartPath).ProviderPath

    $releaseRoot = Join-Path -Path $root -ChildPath 'Release'
    if ($resolvedStartPath.StartsWith($releaseRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $root = $releaseRoot
    }

    $moduleManifest = Join-Path -Path $root -ChildPath "$ModuleName/$ModuleName.psd1"
    if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
        throw "Could not find module '$ModuleName' at '$moduleManifest'."
    }

    Write-Verbose "Using module at: $moduleManifest"
    return $moduleManifest
}
