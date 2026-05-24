function Import-DotEnvFile {
    <#
    .SYNOPSIS
        Loads KEY=value pairs from a .env file into process environment variables.

    .DESCRIPTION
        Parses a .env-style file and sets each assignment with
        [System.Environment]::SetEnvironmentVariable so the values are visible via
        $env:NAME for the lifetime of the current process.

        Blank lines and whole-line comments are skipped. Quoted values preserve #
        characters inside the quotes. Unquoted values treat only whitespace followed
        by # as an inline comment marker, so tokens like abc#123 are preserved.

    .PARAMETER Path
        Path to the .env file. Missing files are ignored.

    .PARAMETER ExcludeName
        Environment variable names to skip while loading the file.

    .OUTPUTS
        PSCustomObject records describing loaded variable names. Values are not
        emitted to avoid leaking secrets to build logs.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Loading a .env file into process-scoped environment variables is intentional and idempotent.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [Parameter()]
        [String[]]$ExcludeName = @()
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $excluded = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $ExcludeName) {
        if (-not [String]::IsNullOrWhiteSpace($name)) {
            $null = $excluded.Add($name)
        }
    }

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -notmatch '^\s*([^#=]+?)\s*=\s*(.*)$') { continue }

        $name = $matches[1].Trim()
        if ([String]::IsNullOrEmpty($name)) { continue }
        if ($excluded.Contains($name)) { continue }

        $rawValue = $matches[2].TrimStart()
        if ($rawValue.Length -gt 0 -and ($rawValue[0] -eq '"' -or $rawValue[0] -eq "'")) {
            $quote = $rawValue[0]
            $endIndex = $rawValue.IndexOf($quote, 1)
            $value = if ($endIndex -gt 0) {
                $rawValue.Substring(1, $endIndex - 1)
            }
            else {
                $rawValue.Substring(1)
            }
        }
        else {
            $value = if ($rawValue -match '^(.*?)\s+#') {
                $matches[1]
            }
            else {
                $rawValue
            }
            $value = $value.TrimEnd()
        }

        [System.Environment]::SetEnvironmentVariable($name, $value)
        [PSCustomObject]@{
            Name = $name
        }
    }
}
