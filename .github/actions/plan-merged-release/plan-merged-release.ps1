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

    $changelogDirectory = if ($env:CHANGELOG_DIRECTORY) { $env:CHANGELOG_DIRECTORY.TrimEnd('/') } else { '.changelog' }
    $stableTags = @(git tag --merged $env:COMMIT_SHA --list 'v[0-9]*' | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' })
    $latestStableTag = $stableTags | Sort-Object { [Version]($_.Substring(1)) } -Descending | Select-Object -First 1
    $commits = if ($latestStableTag) {
        @(git rev-list "$latestStableTag..$env:COMMIT_SHA")
    }
    else {
        @(git rev-list $env:COMMIT_SHA)
    }

    $pullRequestsByNumber = @{}
    foreach ($commit in $commits) {
        $route = 'repos/{0}/commits/{1}/pulls' -f $env:GITHUB_REPOSITORY, $commit
        foreach ($pullRequest in @(gh api $route | ConvertFrom-Json | Where-Object { $_.merged_at })) {
            $pullRequestsByNumber[[String]$pullRequest.number] = $pullRequest
        }
    }

    if ($pullRequestsByNumber.Count -eq 0) {
        Write-OutputValue -Name should_release -Value 'false'
        Write-OutputValue -Name skip_reason -Value 'no merged pull requests since latest release tag'
        Write-Host "Skipping release: no merged pull requests found since '$latestStableTag'."
        return
    }

    $impactRank = @{ none = 0; patch = 1; minor = 2; major = 3 }
    $selectedImpact = 'none'
    foreach ($pullRequest in @($pullRequestsByNumber.Values | Sort-Object { [Int]$_.number })) {
        $prNumber = [String]$pullRequest.number
        $prTitle = [String]$pullRequest.title
        $prAuthor = [String]$pullRequest.user.login
        $labelsRoute = 'repos/{0}/issues/{1}/labels' -f $env:GITHUB_REPOSITORY, $prNumber
        $labels = @(gh api $labelsRoute --paginate --jq '.[].name')
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
                    [PSCustomObject]@{ Path = $normalizedPath; Impact = $match.Groups['impact'].Value; Type = $match.Groups['type'].Value }
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
        if ($intentState.ReleaseImpact -eq 'none') {
            continue
        }
        if ($impactRank[$intentState.ReleaseImpact] -gt $impactRank[$selectedImpact]) {
            $selectedImpact = $intentState.ReleaseImpact
        }
        if (-not $intentState.Fragment) {
            $fragmentPath = Join-Path -Path $changelogDirectory -ChildPath ('{0}.{1}.{2}.md' -f $prNumber, $intentState.ReleaseImpact, $intentState.ChangelogType)
            New-Item -Path (Split-Path -Path $fragmentPath -Parent) -ItemType Directory -Force | Out-Null
            ('* {0} (#{1}, @{2})' -f ($prTitle -replace "`r`n|`r|`n", ' '), $prNumber, $prAuthor) | Set-Content -LiteralPath $fragmentPath -Encoding utf8
        }
    }

    $releaseImpact = $selectedImpact
    Write-OutputValue -Name release_impact -Value $releaseImpact
    if ($releaseImpact -eq 'none') {
        Write-OutputValue -Name should_release -Value 'false'
        Write-OutputValue -Name skip_reason -Value 'release:none'
        Write-Host 'Skipping release: all merged pull requests since latest release tag have release:none.'
        return
    }
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
