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

. (Join-Path -Path $PSScriptRoot -ChildPath '../_shared/release-intent-core.ps1')

if (-not $env:GITHUB_REPOSITORY) {
    throw 'plan-merged-release requires GITHUB_REPOSITORY.'
}

$releaseImpact = $null
$fragment = $null
$manualReleaseImpact = if ($env:RELEASE_IMPACT) { $env:RELEASE_IMPACT.Trim().ToLowerInvariant() } else { '' }
$prereleaseLabel = if ($env:PRERELEASE_LABEL) { $env:PRERELEASE_LABEL.Trim().ToLowerInvariant() } else { '' }
if ($prereleaseLabel -and $prereleaseLabel -notmatch '^(?:alpha|beta|rc)(?:-\d+)?$') {
    throw "Prerelease label '$env:PRERELEASE_LABEL' must be alpha, beta, rc, or a numbered form like rc-2."
}

$isManualRelease = -not [String]::IsNullOrWhiteSpace($manualReleaseImpact)
if ($prereleaseLabel -and -not $isManualRelease) {
    throw 'Prerelease labels are only supported for manual releases.'
}

if ($isManualRelease) {
    if ($manualReleaseImpact -notin @('patch', 'minor', 'major')) {
        throw "Manual release impact '$env:RELEASE_IMPACT' must be patch, minor, or major."
    }

    $releaseImpact = $manualReleaseImpact
    Write-OutputValue -Name release_impact -Value $releaseImpact
}
else {
    if (-not $env:COMMIT_SHA) {
        throw 'plan-merged-release requires COMMIT_SHA. Run it from a push workflow or pass commit-sha.'
    }

    $commitPullsRoute = 'repos/{0}/commits/{1}/pulls' -f $env:GITHUB_REPOSITORY, $env:COMMIT_SHA
    $pullRequestJson = gh api $commitPullsRoute --jq '.[] | select(.merged_at != null) | { number, title, user: .user.login }' |
        Select-Object -First 1

    if (-not $pullRequestJson) {
        Write-OutputValue -Name should_release -Value 'false'
        Write-OutputValue -Name skip_reason -Value 'no associated merged pull request'
        Write-Host "Skipping release: no associated merged pull request for commit '$env:COMMIT_SHA'."
        return
    }

    $pullRequest = $pullRequestJson | ConvertFrom-Json
    $prNumber = [String]$pullRequest.number
    $prTitle = [String]$pullRequest.title
    $prAuthor = [String]$pullRequest.user

    $labelsRoute = 'repos/{0}/issues/{1}/labels' -f $env:GITHUB_REPOSITORY, $prNumber
    $labels = @(gh api $labelsRoute --paginate --jq '.[].name')
    Write-OutputValue -Name pr_number -Value $prNumber
    Write-OutputValue -Name pr_title -Value $prTitle
    Write-OutputValue -Name pr_author -Value $prAuthor

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
    $intentState = Resolve-ReleaseIntentState -Labels $labels -Fragments $matchingFragments -HasChangelogFilesForNone ($fragmentFiles.Count -gt 0) -Context "merged PR #$prNumber"
    if (-not $intentState.IsValid) {
        throw ($intentState.Messages -join [Environment]::NewLine)
    }

    $releaseImpact = $intentState.ReleaseImpact
    Write-OutputValue -Name release_impact -Value $releaseImpact
    if ($releaseImpact -eq 'none') {
        Write-OutputValue -Name should_release -Value 'false'
        Write-OutputValue -Name skip_reason -Value 'release:none'
        Write-Host "Skipping release: merged PR #$prNumber has release:none."
        return
    }

    $fragment = $intentState.Fragment
    $changelogType = $intentState.ChangelogType
    Write-OutputValue -Name changelog_type -Value $changelogType
}

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
if ($prereleaseLabel) {
    $releaseVersion = '{0}-{1}' -f $releaseVersion, $prereleaseLabel
}
$releaseTag = 'v{0}' -f $releaseVersion
git show-ref --verify --quiet "refs/tags/$releaseTag"
$tagExistsExitCode = $LASTEXITCODE
if ($tagExistsExitCode -eq 0) {
    throw "Computed release tag '$releaseTag' already exists."
}
if ($tagExistsExitCode -ne 1) {
    throw "Unable to verify whether release tag '$releaseTag' exists. git show-ref exited with $tagExistsExitCode."
}
$global:LASTEXITCODE = 0

Write-OutputValue -Name should_release -Value 'true'
Write-OutputValue -Name release_version -Value $releaseVersion
Write-OutputValue -Name release_tag -Value $releaseTag
if ($isManualRelease) {
    if ($prereleaseLabel) {
        Write-Host "Planned manual prerelease $releaseTag with release:$releaseImpact."
    }
    else {
        Write-Host "Planned manual release $releaseTag with release:$releaseImpact."
    }
}
else {
    Write-Host "Planned release $releaseTag from merged PR #$prNumber with release:$releaseImpact."
}
if (-not $isManualRelease -and -not $fragment) {
    $safeTitle = $prTitle -replace "`r`n|`r|`n", ' '
    Write-OutputValue -Name fragment_path -Value ('{0}/{1}.{2}.{3}.md' -f $changelogDirectory, $prNumber, $releaseImpact, $changelogType)
    Write-OutputValue -Name fragment_content -Value ('* {0} (#{1}, @{2})' -f $safeTitle, $prNumber, $prAuthor)
}
