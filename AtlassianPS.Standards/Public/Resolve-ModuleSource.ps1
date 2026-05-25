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
        [String]$StartPath = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS'
    )

    $projectRoot = Resolve-ProjectRoot -StartPath $StartPath -MarkerFileName $MarkerFileName
    ${/} = [System.IO.Path]::DirectorySeparatorChar
    $resolvedStartPath = (Resolve-Path -LiteralPath $StartPath).ProviderPath

    if ($resolvedStartPath -like "*${/}Release${/}*") {
        $projectRoot = Join-Path -Path $projectRoot -ChildPath 'Release'
    }

    $moduleManifest = Join-Path -Path $projectRoot -ChildPath "$ModuleName/$ModuleName.psd1"
    if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
        throw "Could not find module '$ModuleName' at '$moduleManifest'."
    }

    Write-Verbose "Using module at: $moduleManifest"
    return $moduleManifest
}
