function Write-OutputValue {
    param(
        [Parameter(Mandatory)]
        [String]$Name,

        [Parameter()]
        [AllowNull()]
        [String]$Value
    )

    if ($null -eq $Value) {
        $Value = ''
    }

    $Value = $Value -replace "`r`n|`r|`n", ' '
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value ('{0}={1}' -f $Name, $Value)
}

if (-not $env:COMMIT_SHA) {
    throw 'plan-merged-release requires COMMIT_SHA. Run it from a push workflow or pass commit-sha.'
}
if (-not $env:GITHUB_REPOSITORY) {
    throw 'plan-merged-release requires GITHUB_REPOSITORY.'
}

$validReleaseImpacts = @('none', 'patch', 'minor', 'major')
$validChangelogTypes = @('added', 'changed', 'fixed', 'removed', 'deprecated', 'security', 'breaking')
$commitPullsRoute = 'repos/{0}/commits/{1}/pulls' -f $env:GITHUB_REPOSITORY, $env:COMMIT_SHA
$pullRequestJson = gh api $commitPullsRoute --jq '.[] | select(.merged_at != null) | { number, title, user: .user.login }' |
    Select-Object -First 1

if (-not $pullRequestJson) {
    Write-OutputValue -Name should_release -Value 'false'
    Write-OutputValue -Name skip_reason -Value 'no associated merged pull request'
    return
}

$pullRequest = $pullRequestJson | ConvertFrom-Json
$prNumber = [String]$pullRequest.number
$prTitle = [String]$pullRequest.title
$prAuthor = [String]$pullRequest.user

$labelsRoute = 'repos/{0}/issues/{1}/labels' -f $env:GITHUB_REPOSITORY, $prNumber
$labels = @(gh api $labelsRoute --paginate --jq '.[].name')
$releaseLabels = @($labels | Where-Object { $_ -like 'release:*' } | Sort-Object -Unique)
$changelogLabels = @($labels | Where-Object { $_ -like 'changelog:*' } | Sort-Object -Unique)
$validReleaseLabels = @($releaseLabels | Where-Object { ($_ -replace '^release:', '') -in $validReleaseImpacts })
$validChangelogLabels = @($changelogLabels | Where-Object { ($_ -replace '^changelog:', '') -in $validChangelogTypes })

foreach ($label in @($releaseLabels | Where-Object { ($_ -replace '^release:', '') -notin $validReleaseImpacts })) {
    throw "Unknown release label '$label'. Use one of: release:none, release:patch, release:minor, release:major."
}
foreach ($label in @($changelogLabels | Where-Object { ($_ -replace '^changelog:', '') -notin $validChangelogTypes })) {
    throw "Unknown changelog label '$label'. Use one of: changelog:added, changelog:changed, changelog:fixed, changelog:removed, changelog:deprecated, changelog:security, changelog:breaking."
}
if ($validReleaseLabels.Count -ne 1) {
    throw "Merged PR #$prNumber must have exactly one release label."
}

$releaseImpact = $validReleaseLabels[0] -replace '^release:', ''
Write-OutputValue -Name pr_number -Value $prNumber
Write-OutputValue -Name pr_title -Value $prTitle
Write-OutputValue -Name pr_author -Value $prAuthor
Write-OutputValue -Name release_impact -Value $releaseImpact

if ($releaseImpact -eq 'none') {
    Write-OutputValue -Name should_release -Value 'false'
    Write-OutputValue -Name skip_reason -Value 'release:none'
    return
}

if ($validChangelogLabels.Count -gt 1) {
    throw "Merged PR #$prNumber must have at most one changelog label."
}

$changelogDirectory = if ($env:CHANGELOG_DIRECTORY) { $env:CHANGELOG_DIRECTORY.TrimEnd('/') } else { '.changelog' }
$fragmentPattern = '^{0}/{1}\.(?<impact>patch|minor|major)\.(?<type>added|changed|fixed|removed|deprecated|security|breaking)\.md$' -f [Regex]::Escape($changelogDirectory), $prNumber
$fragmentFiles = @(
    if (Test-Path -LiteralPath $changelogDirectory -PathType Container) {
        Get-ChildItem -LiteralPath $changelogDirectory -Filter "$prNumber.*.md" |
            ForEach-Object { Join-Path -Path $changelogDirectory -ChildPath $_.Name }
    }
)
$matchingFragments = @(
    foreach ($path in $fragmentFiles) {
        $normalizedPath = $path -replace '\\', '/'
        $match = [Regex]::Match($normalizedPath, $fragmentPattern)
        if ($match.Success) {
            [PSCustomObject]@{
                Path   = $normalizedPath
                Impact = $match.Groups['impact'].Value
                Type   = $match.Groups['type'].Value
            }
        }
    }
)
foreach ($path in @($fragmentFiles | Where-Object { -not [Regex]::IsMatch(($_ -replace '\\', '/'), $fragmentPattern) })) {
    throw "Changelog fragment '$path' must be named '$changelogDirectory/$prNumber.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md'."
}
if ($matchingFragments.Count -gt 1) {
    throw "Merged PR #$prNumber must have at most one changelog fragment."
}

$changelogTypeFromLabel = if ($validChangelogLabels.Count -eq 1) { $validChangelogLabels[0] -replace '^changelog:', '' } else { $null }
$fragment = if ($matchingFragments.Count -eq 1) { $matchingFragments[0] } else { $null }
if ($fragment -and $changelogTypeFromLabel) {
    throw "Merged PR #$prNumber must use either one changelog label or one custom changelog fragment, not both."
}
if (-not $fragment -and -not $changelogTypeFromLabel) {
    throw "Merged PR #$prNumber must have one changelog label or one custom changelog fragment."
}
if ($fragment -and $fragment.Impact -ne $releaseImpact) {
    throw "Changelog fragment impact '$($fragment.Impact)' must match release label 'release:$releaseImpact'."
}

$changelogType = if ($fragment) { $fragment.Type } else { $changelogTypeFromLabel }
if ($changelogType -eq 'breaking' -and $releaseImpact -ne 'major') {
    throw 'changelog:breaking and breaking changelog fragments require release:major.'
}
Write-OutputValue -Name changelog_type -Value $changelogType

$versions = @(
    git tag --list 'v[0-9]*' |
        ForEach-Object {
            if ($_ -match '^v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$') {
                [PSCustomObject]@{
                    Major   = [Int]$Matches.major
                    Minor   = [Int]$Matches.minor
                    Patch   = [Int]$Matches.patch
                    Version = [Version]('{0}.{1}.{2}' -f $Matches.major, $Matches.minor, $Matches.patch)
                }
            }
        } |
        Sort-Object -Property Version -Descending
)
$latest = $versions | Select-Object -First 1
if (-not $latest) {
    $latest = [PSCustomObject]@{ Major = 0; Minor = 0; Patch = 0 }
}

$nextMajor = $latest.Major
$nextMinor = $latest.Minor
$nextPatch = $latest.Patch
switch ($releaseImpact) {
    'major' {
        $nextMajor += 1
        $nextMinor = 0
        $nextPatch = 0
    }
    'minor' {
        $nextMinor += 1
        $nextPatch = 0
    }
    'patch' {
        $nextPatch += 1
    }
}

$releaseVersion = '{0}.{1}.{2}' -f $nextMajor, $nextMinor, $nextPatch
$releaseTag = 'v{0}' -f $releaseVersion
git show-ref --verify --quiet "refs/tags/$releaseTag"
if ($LASTEXITCODE -eq 0) {
    throw "Computed release tag '$releaseTag' already exists."
}

Write-OutputValue -Name should_release -Value 'true'
Write-OutputValue -Name release_version -Value $releaseVersion
Write-OutputValue -Name release_tag -Value $releaseTag
if (-not $fragment) {
    $safeTitle = $prTitle -replace "`r`n|`r|`n", ' '
    Write-OutputValue -Name fragment_path -Value ('{0}/{1}.{2}.{3}.md' -f $changelogDirectory, $prNumber, $releaseImpact, $changelogType)
    Write-OutputValue -Name fragment_content -Value ('* {0} (#{1}, @{2})' -f $safeTitle, $prNumber, $prAuthor)
}
