if (-not (Test-Path -LiteralPath $env:CHANGELOG_PATH -PathType Leaf)) {
    throw "Changelog file was not found at '$env:CHANGELOG_PATH'."
}

$normalizedVersion = $env:RELEASE_VERSION.Trim()
if ($normalizedVersion.StartsWith('v')) {
    $normalizedVersion = $normalizedVersion.Substring(1)
}
if ($normalizedVersion -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') {
    throw "Release version '$env:RELEASE_VERSION' must be a v-prefixed or plain semantic version like 'v1.2.3'."
}

$releaseHeading = 'v{0}' -f $normalizedVersion
$resolvedChangelogPath = (Resolve-Path -LiteralPath $env:CHANGELOG_PATH).ProviderPath
$content = [System.IO.File]::ReadAllText($resolvedChangelogPath)
$content = $content -replace "`r`n|`n|`r", "`r`n"

$escapedVersion = [Regex]::Escape($normalizedVersion)
if ([Regex]::IsMatch($content, "(?m)^##[ \t]+v?$escapedVersion(?:[ \t]+-[^\r\n]*)?[ \t]*\r?$")) {
    throw "Changelog section '## $releaseHeading' already exists in '$env:CHANGELOG_PATH'."
}

$unreleasedMatch = [Regex]::Match($content, "(?ms)^##[ \t]+Unreleased[ \t]*\r?\n(?<body>.*?)(?=^##[ \t]+|\z)")
if (-not $unreleasedMatch.Success) {
    throw "Could not find changelog section '## Unreleased' in '$env:CHANGELOG_PATH'."
}

$changelogRoot = Split-Path -Path $resolvedChangelogPath -Parent
$fragmentDirectory = if ([System.IO.Path]::IsPathRooted($env:CHANGELOG_DIRECTORY)) {
    $env:CHANGELOG_DIRECTORY
}
else {
    Join-Path -Path $changelogRoot -ChildPath $env:CHANGELOG_DIRECTORY
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
            Type    = $match.Groups['type'].Value
            Content = $fragmentContent
        }
    }
)

$releaseBodyParts = [System.Collections.Generic.List[String]]::new()
$unreleasedBody = $unreleasedMatch.Groups['body'].Value.Trim()
$changelogHeadings = [ordered]@{
    added      = 'Added'
    changed    = 'Changed'
    deprecated = 'Deprecated'
    removed    = 'Removed'
    fixed      = 'Fixed'
    security   = 'Security'
    breaking   = 'Breaking'
}
$changelogTypesByHeading = @{}
$categorizedContent = @{}
foreach ($changelogType in $changelogHeadings.Keys) {
    $changelogTypesByHeading[$changelogHeadings[$changelogType]] = $changelogType
    $categorizedContent[$changelogType] = [System.Collections.Generic.List[String]]::new()
}

$uncategorizedLines = [System.Collections.Generic.List[String]]::new()
$sectionLines = [System.Collections.Generic.List[String]]::new()
$currentType = $null
$inFence = $false
$fenceCharacter = $null
$fenceLength = 0

foreach ($line in @($unreleasedBody -split "`r`n")) {
    $headingMatch = if (-not $inFence) { [Regex]::Match($line, '^###[ \t]+(?<heading>[^\r\n]+?)[ \t]*$') }
    if ($headingMatch.Success) {
        if ($currentType) {
            $sectionBody = ($sectionLines.ToArray() -join "`r`n").Trim()
            if (-not [String]::IsNullOrWhiteSpace($sectionBody)) {
                $categorizedContent[$currentType].Add($sectionBody)
            }
            $sectionLines.Clear()
        }

        $heading = $headingMatch.Groups['heading'].Value
        $currentType = $changelogTypesByHeading[$heading]
        if ($currentType) {
            continue
        }
    }

    if ($currentType) {
        $sectionLines.Add($line)
    }
    else {
        $uncategorizedLines.Add($line)
    }

    $fenceMatch = [Regex]::Match($line, '^[ \t]*(?<fence>`{3,}|~{3,})')
    if (-not $inFence -and $fenceMatch.Success) {
        $inFence = $true
        $fenceCharacter = $fenceMatch.Groups['fence'].Value.Substring(0, 1)
        $fenceLength = $fenceMatch.Groups['fence'].Value.Length
    }
    elseif ($inFence) {
        $closingFencePattern = '^[ \t]*{0}{{{1},}}[ \t]*$' -f [Regex]::Escape($fenceCharacter), $fenceLength
        if ([Regex]::IsMatch($line, $closingFencePattern)) {
            $inFence = $false
            $fenceCharacter = $null
            $fenceLength = 0
        }
    }
}
if ($currentType) {
    $sectionBody = ($sectionLines.ToArray() -join "`r`n").Trim()
    if (-not [String]::IsNullOrWhiteSpace($sectionBody)) {
        $categorizedContent[$currentType].Add($sectionBody)
    }
}
foreach ($fragment in @($fragments | Sort-Object -Property Pull, Name)) {
    $categorizedContent[$fragment.Type].Add($fragment.Content)
}

$uncategorizedBody = ($uncategorizedLines.ToArray() -join "`r`n").Trim()
if (-not [String]::IsNullOrWhiteSpace($uncategorizedBody)) {
    $releaseBodyParts.Add($uncategorizedBody)
}
foreach ($changelogType in $changelogHeadings.Keys) {
    if ($categorizedContent[$changelogType].Count -gt 0) {
        $sectionBody = $categorizedContent[$changelogType].ToArray() -join "`r`n"
        $releaseBodyParts.Add("### $($changelogHeadings[$changelogType])`r`n`r`n$sectionBody")
    }
}

if ($releaseBodyParts.Count -eq 0) {
    throw "No unreleased changelog entries or changelog fragments were found for '$releaseHeading'."
}

$releaseBody = ($releaseBodyParts.ToArray() -join "`r`n`r`n")
$newSection = "## Unreleased`r`n`r`n## $releaseHeading - $((Get-Date).ToString('yyyy-MM-dd'))`r`n`r`n$releaseBody`r`n`r`n"
$updatedContent = '{0}{1}{2}' -f @(
    $content.Substring(0, $unreleasedMatch.Index)
    $newSection
    $content.Substring($unreleasedMatch.Index + $unreleasedMatch.Length)
)

[System.IO.File]::WriteAllText($resolvedChangelogPath, $updatedContent, [System.Text.UTF8Encoding]::new($false))
foreach ($fragment in $fragments) {
    Remove-Item -LiteralPath $fragment.Path
}

$outputPath = if ($env:RELEASE_NOTES_PATH) {
    $env:RELEASE_NOTES_PATH
}
elseif ($env:RUNNER_TEMP) {
    Join-Path -Path $env:RUNNER_TEMP -ChildPath 'release-notes.md'
}
else {
    Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'release-notes.md'
}
New-Item -Path (Split-Path -Path $outputPath -Parent) -ItemType Directory -Force | Out-Null
$releaseBody | Set-Content -LiteralPath $outputPath -Encoding utf8

@(
    "release_version=$releaseHeading"
    "release_notes_path=$outputPath"
) | Add-Content -LiteralPath $env:GITHUB_OUTPUT
