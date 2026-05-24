function Resolve-ProjectRoot {
    <#
    .SYNOPSIS
        Resolves a repository root by walking up from a starting path.

    .DESCRIPTION
        Walks from StartPath up to the filesystem root until a configured marker
        file is found. AtlassianPS repositories use CODEOWNERS as the default root
        marker for test and build helper discovery.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$StartPath = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS'
    )

    $candidate = (Resolve-Path -LiteralPath $StartPath).ProviderPath
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -Path $candidate -Parent
    }

    while ($candidate -and ($candidate -ne [System.IO.Path]::GetPathRoot($candidate))) {
        if (Test-Path -LiteralPath (Join-Path -Path $candidate -ChildPath $MarkerFileName) -PathType Leaf) {
            return $candidate
        }

        $candidate = Split-Path -Path $candidate -Parent
    }

    throw "Could not find project root marker '$MarkerFileName' in any parent of '$StartPath'."
}
