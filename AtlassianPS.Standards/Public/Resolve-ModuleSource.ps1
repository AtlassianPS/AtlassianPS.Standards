function Resolve-ModuleSource {
    <#
    .SYNOPSIS
        Resolves a module manifest path for source or release test runs.

    .DESCRIPTION
        Resolves the repository root, switches to the Release root when tests are
        running from a built artifact, and returns the module manifest path for the
        requested module.
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
