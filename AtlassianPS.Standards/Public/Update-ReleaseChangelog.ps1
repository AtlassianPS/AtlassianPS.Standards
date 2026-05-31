function Update-ReleaseChangelog {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ChangelogPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ReleaseVersion,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ChangelogDirectory = '.changelog',

        [Parameter()]
        [DateTime]$ReleaseDate = (Get-Date)
    )

    if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
        throw "Changelog file was not found at '$ChangelogPath'."
    }

    $normalizedVersion = $ReleaseVersion.Trim()
    if ($normalizedVersion.StartsWith('v')) {
        $normalizedVersion = $normalizedVersion.Substring(1)
    }
    if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
        throw "Release version '$ReleaseVersion' must be a v-prefixed or plain semantic version like 'v1.2.3'."
    }

    $releaseHeading = 'v{0}' -f $normalizedVersion
    $content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ChangelogPath).ProviderPath)
    $content = $content -replace "`r`n|`n|`r", "`r`n"

    $escapedVersion = [Regex]::Escape($normalizedVersion)
    if ([Regex]::IsMatch($content, "(?m)^##[ \t]+v?$escapedVersion(?:[ \t]+-[^\r\n]*)?[ \t]*\r?$")) {
        throw "Changelog section '## $releaseHeading' already exists in '$ChangelogPath'."
    }

    $unreleasedMatch = [Regex]::Match($content, "(?ms)^##[ \t]+Unreleased[ \t]*\r?\n(?<body>.*?)(?=^##[ \t]+|\z)")
    if (-not $unreleasedMatch.Success) {
        throw "Could not find changelog section '## Unreleased' in '$ChangelogPath'."
    }

    $changelogRoot = Split-Path -Path (Resolve-Path -LiteralPath $ChangelogPath).ProviderPath -Parent
    $fragmentDirectory = if ([System.IO.Path]::IsPathRooted($ChangelogDirectory)) {
        $ChangelogDirectory
    }
    else {
        Join-Path -Path $changelogRoot -ChildPath $ChangelogDirectory
    }

    $fragmentPattern = '^(?<pr>\d+)\.(?<impact>patch|minor|major)\.(?<type>added|changed|fixed|removed|deprecated|security|breaking)\.md$'
    $fragmentFiles = @(
        if (Test-Path -LiteralPath $fragmentDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $fragmentDirectory -Filter '*.md' |
                Sort-Object -Property Name
        }
    )

    $fragments = @(
        foreach ($fragmentFile in $fragmentFiles) {
            $match = [Regex]::Match($fragmentFile.Name, $fragmentPattern)
            if (-not $match.Success) {
                throw "Changelog fragment '$($fragmentFile.FullName)' must be named '<pr-number>.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md'."
            }

            $fragmentContent = [System.IO.File]::ReadAllText($fragmentFile.FullName).Trim()
            if ([String]::IsNullOrWhiteSpace($fragmentContent)) {
                throw "Changelog fragment '$($fragmentFile.FullName)' is empty."
            }

            [PSCustomObject]@{
                Path    = $fragmentFile.FullName
                Name    = $fragmentFile.Name
                Pull    = [Int]$match.Groups['pr'].Value
                Impact  = $match.Groups['impact'].Value
                Type    = $match.Groups['type'].Value
                Content = $fragmentContent
            }
        }
    )

    $releaseBodyParts = [System.Collections.Generic.List[String]]::new()
    $unreleasedBody = $unreleasedMatch.Groups['body'].Value.Trim()
    if (-not [String]::IsNullOrWhiteSpace($unreleasedBody)) {
        $releaseBodyParts.Add($unreleasedBody)
    }
    foreach ($fragment in @($fragments | Sort-Object -Property Pull, Name)) {
        $releaseBodyParts.Add($fragment.Content)
    }

    if ($releaseBodyParts.Count -eq 0) {
        throw "No unreleased changelog entries or changelog fragments were found for '$releaseHeading'."
    }

    $releaseBody = ($releaseBodyParts.ToArray() -join "`r`n")
    $newSection = "## Unreleased`r`n`r`n## $releaseHeading - $($ReleaseDate.ToString('yyyy-MM-dd'))`r`n`r`n$releaseBody`r`n`r`n"
    $updatedContent = '{0}{1}{2}' -f @(
        $content.Substring(0, $unreleasedMatch.Index)
        $newSection
        $content.Substring($unreleasedMatch.Index + $unreleasedMatch.Length)
    )

    if ($PSCmdlet.ShouldProcess($ChangelogPath, "Prepare changelog release section '$releaseHeading'")) {
        [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ChangelogPath).ProviderPath, $updatedContent, [System.Text.UTF8Encoding]::new($false))
        foreach ($fragment in $fragments) {
            Remove-Item -LiteralPath $fragment.Path
        }
    }

    return [PSCustomObject]@{
        ReleaseVersion        = $releaseHeading
        ChangelogPath         = (Resolve-Path -LiteralPath $ChangelogPath).ProviderPath
        ChangelogFragmentPath = [String[]]@($fragments | Select-Object -ExpandProperty Path)
        ReleaseNotes          = $releaseBody
    }
}
