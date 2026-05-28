function Get-ReleaseNotesFromChangelog {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ChangelogPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ReleaseVersion
    )

    if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
        throw "Changelog file was not found at '$ChangelogPath'."
    }

    $normalizedVersion = $ReleaseVersion.Trim()
    if ($normalizedVersion.StartsWith('v')) {
        $normalizedVersion = $normalizedVersion.Substring(1)
    }

    $escapedVersion = [System.Text.RegularExpressions.Regex]::Escape($normalizedVersion)
    $content = Get-Content -LiteralPath $ChangelogPath -Raw
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $content,
        "(?ms)^##[ \t]+v?$escapedVersion(?:[ \t]+-[^\r\n]*)?[ \t]*\r?\n(?<body>.*?)(?=^##[ \t]+|\z)"
    )

    if (-not $match.Success) {
        throw "Could not find changelog section '## v$normalizedVersion' in '$ChangelogPath'."
    }

    $releaseNotes = $match.Groups['body'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
        throw "Changelog section '## v$normalizedVersion' in '$ChangelogPath' is empty."
    }

    return , $releaseNotes
}
