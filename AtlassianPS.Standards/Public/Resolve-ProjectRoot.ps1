function Resolve-ProjectRoot {
    <#
    .SYNOPSIS
        Resolves a repository root from a starting path.

    .DESCRIPTION
        Uses git rev-parse when StartPath is inside a Git worktree, then falls
        back to walking parent directories until a configured marker file is found.
        The fallback supports copied release artifacts and non-Git test fixtures.

    .PARAMETER StartPath
        Directory or file path to start searching from. Defaults to the current directory.

    .PARAMETER MarkerFileName
        Repository-root marker file name. Defaults to CODEOWNERS.

    .OUTPUTS
        String. The resolved repository root path.

    .EXAMPLE
        Resolve-AtlassianPSProjectRoot -StartPath $PSScriptRoot

        Resolves the repository root for a test file or helper script.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$StartPath = '.',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS'
    )

    $resolvedStartPath = (Resolve-Path -LiteralPath $StartPath).ProviderPath
    $candidate = if (Test-Path -LiteralPath $resolvedStartPath -PathType Leaf) {
        Split-Path -Path $resolvedStartPath -Parent
    }
    else {
        $resolvedStartPath
    }

    if (Get-Command -Name git -ErrorAction SilentlyContinue) {
        try {
            $gitRoot = & git -C $candidate rev-parse --show-toplevel 2>&1
            if ($LASTEXITCODE -eq 0 -and -not [String]::IsNullOrWhiteSpace($gitRoot)) {
                return (Resolve-Path -LiteralPath ([String]$gitRoot).Trim()).ProviderPath
            }
        }
        catch {
            Write-Verbose "git rev-parse did not resolve a project root: $($_.Exception.Message)"
        }
    }

    while ($candidate -and ($candidate -ne [System.IO.Path]::GetPathRoot($candidate))) {
        if (Test-Path -LiteralPath (Join-Path -Path $candidate -ChildPath $MarkerFileName) -PathType Leaf) {
            return $candidate
        }

        $candidate = Split-Path -Path $candidate -Parent
    }

    throw "Could not find project root marker '$MarkerFileName' in any parent of '$StartPath'."
}
