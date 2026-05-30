function Test-ReleaseIntent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [String[]]$LabelName,

        [Parameter()]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [String[]]$ChangedFilePath,

        [Parameter(Mandatory)]
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int]$PullRequestNumber,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ChangelogDirectory = '.changelog'
    )

    $releaseLabels = @($LabelName | Where-Object { $_ -like 'release:*' } | Sort-Object -Unique)
    $changelogLabels = @($LabelName | Where-Object { $_ -like 'changelog:*' } | Sort-Object -Unique)
    $validReleaseImpacts = @('none', 'patch', 'minor', 'major')
    $validChangelogTypes = @('added', 'changed', 'fixed', 'removed', 'deprecated', 'security', 'breaking')
    $messages = [System.Collections.Generic.List[String]]::new()

    $unknownReleaseLabels = @(
        $releaseLabels |
            Where-Object { ($_ -replace '^release:', '') -notin $validReleaseImpacts }
    )
    foreach ($label in $unknownReleaseLabels) {
        $messages.Add("Unknown release label '$label'. Use one of: release:none, release:patch, release:minor, release:major.")
    }

    $unknownChangelogLabels = @(
        $changelogLabels |
            Where-Object { ($_ -replace '^changelog:', '') -notin $validChangelogTypes }
    )
    foreach ($label in $unknownChangelogLabels) {
        $messages.Add("Unknown changelog label '$label'. Use one of: changelog:added, changelog:changed, changelog:fixed, changelog:removed, changelog:deprecated, changelog:security, changelog:breaking.")
    }

    $validReleaseLabels = @($releaseLabels | Where-Object { ($_ -replace '^release:', '') -in $validReleaseImpacts })
    if ($validReleaseLabels.Count -ne 1) {
        $messages.Add('Add exactly one release label: release:none, release:patch, release:minor, or release:major.')
    }

    $releaseImpact = if ($validReleaseLabels.Count -eq 1) {
        $validReleaseLabels[0] -replace '^release:', ''
    }
    else {
        $null
    }

    $validChangelogLabels = @($changelogLabels | Where-Object { ($_ -replace '^changelog:', '') -in $validChangelogTypes })
    $changelogTypeFromLabel = if ($validChangelogLabels.Count -eq 1) {
        $validChangelogLabels[0] -replace '^changelog:', ''
    }
    else {
        $null
    }

    $escapedDirectory = [Regex]::Escape($ChangelogDirectory.TrimEnd('/'))
    $fragmentPattern = "^$escapedDirectory/$PullRequestNumber\.(?<impact>patch|minor|major)\.(?<type>added|changed|fixed|removed|deprecated|security|breaking)\.md$"
    $changelogFiles = @(
        $ChangedFilePath |
            Where-Object { $_ -eq $ChangelogDirectory -or $_ -like "$($ChangelogDirectory.TrimEnd('/'))/*" } |
            Sort-Object -Unique
    )
    $matchingFragments = @(
        foreach ($path in $changelogFiles) {
            $match = [Regex]::Match($path, $fragmentPattern)
            if ($match.Success) {
                [PSCustomObject]@{
                    Path   = $path
                    Impact = $match.Groups['impact'].Value
                    Type   = $match.Groups['type'].Value
                }
            }
        }
    )
    $invalidFragments = @(
        $changelogFiles |
            Where-Object { -not [Regex]::IsMatch($_, $fragmentPattern) }
    )

    foreach ($path in $invalidFragments) {
        $messages.Add("Changelog fragment '$path' must be named '$($ChangelogDirectory.TrimEnd('/'))/$PullRequestNumber.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md'.")
    }

    if ($matchingFragments.Count -gt 1) {
        $messages.Add("Use at most one changelog fragment for PR #$PullRequestNumber.")
    }

    $fragment = if ($matchingFragments.Count -eq 1) { $matchingFragments[0] } else { $null }
    $resolvedChangelogType = if ($fragment) {
        $fragment.Type
    }
    else {
        $changelogTypeFromLabel
    }

    if ($releaseImpact -eq 'none') {
        if ($validChangelogLabels.Count -gt 0) {
            $messages.Add('release:none must not be combined with changelog labels.')
        }

        if ($changelogFiles.Count -gt 0) {
            $messages.Add('release:none must not include changelog fragments.')
        }
    }
    elseif ($releaseImpact) {
        if ($validChangelogLabels.Count -gt 1) {
            $messages.Add('Add exactly one changelog label for user-facing changes.')
        }

        if (-not $fragment -and $validChangelogLabels.Count -ne 1) {
            $messages.Add('For release:patch, release:minor, or release:major, add exactly one changelog label or one valid changelog fragment.')
        }

        if ($fragment) {
            if ($fragment.Impact -ne $releaseImpact) {
                $messages.Add("Changelog fragment impact '$($fragment.Impact)' must match release label 'release:$releaseImpact'.")
            }

            if ($changelogTypeFromLabel -and $fragment.Type -ne $changelogTypeFromLabel) {
                $messages.Add("Changelog fragment type '$($fragment.Type)' must match label 'changelog:$changelogTypeFromLabel'.")
            }
        }

        if ($resolvedChangelogType -eq 'breaking' -and $releaseImpact -ne 'major') {
            $messages.Add('changelog:breaking and breaking changelog fragments require release:major.')
        }
    }

    return [PSCustomObject]@{
        IsValid              = $messages.Count -eq 0
        PullRequestNumber    = $PullRequestNumber
        ReleaseImpact        = $releaseImpact
        ChangelogType        = $resolvedChangelogType
        HasChangelogFragment = $null -ne $fragment
        ChangelogFragment    = if ($fragment) { $fragment.Path } else { $null }
        Messages             = [String[]]$messages
    }
}
