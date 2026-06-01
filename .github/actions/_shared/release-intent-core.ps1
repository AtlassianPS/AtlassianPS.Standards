function Resolve-ReleaseIntentState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String[]]$Labels = @(),

        [Parameter()]
        [Object[]]$Fragments = @(),

        [Parameter()]
        [Boolean]$HasChangelogFilesForNone,

        [Parameter()]
        [String]$Context = 'Pull request'
    )

    $validReleaseImpacts = @('none', 'patch', 'minor', 'major')
    $validChangelogTypes = @('added', 'changed', 'fixed', 'removed', 'deprecated', 'security', 'breaking')
    $messages = [System.Collections.Generic.List[String]]::new()

    $releaseLabels = @($Labels | Where-Object { $_ -like 'release:*' } | Sort-Object -Unique)
    $changelogLabels = @($Labels | Where-Object { $_ -like 'changelog:*' } | Sort-Object -Unique)

    foreach ($label in @($releaseLabels | Where-Object { ($_ -replace '^release:', '') -notin $validReleaseImpacts })) {
        $messages.Add("Unknown release label '$label'. Use one of: release:none, release:patch, release:minor, release:major.")
    }
    foreach ($label in @($changelogLabels | Where-Object { ($_ -replace '^changelog:', '') -notin $validChangelogTypes })) {
        $messages.Add("Unknown changelog label '$label'. Use one of: changelog:added, changelog:changed, changelog:fixed, changelog:removed, changelog:deprecated, changelog:security, changelog:breaking.")
    }

    $validReleaseLabels = @($releaseLabels | Where-Object { ($_ -replace '^release:', '') -in $validReleaseImpacts })
    if ($validReleaseLabels.Count -ne 1) {
        $messages.Add('Add exactly one release label: release:none, release:patch, release:minor, or release:major.')
    }
    $releaseImpact = if ($validReleaseLabels.Count -eq 1) { $validReleaseLabels[0] -replace '^release:', '' } else { $null }

    $validChangelogLabels = @($changelogLabels | Where-Object { ($_ -replace '^changelog:', '') -in $validChangelogTypes })
    $changelogTypeFromLabel = if ($validChangelogLabels.Count -eq 1) { $validChangelogLabels[0] -replace '^changelog:', '' } else { $null }
    $fragment = if ($Fragments.Count -eq 1) { $Fragments[0] } else { $null }
    $resolvedChangelogType = if ($fragment) { $fragment.Type } else { $changelogTypeFromLabel }

    if ($Fragments.Count -gt 1) {
        $messages.Add("Use at most one changelog fragment for $Context.")
    }

    if ($releaseImpact -eq 'none') {
        if ($validChangelogLabels.Count -gt 0) {
            $messages.Add('release:none must not be combined with changelog labels.')
        }
        if ($HasChangelogFilesForNone) {
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
        if ($fragment -and $validChangelogLabels.Count -gt 0) {
            $messages.Add('Use either one changelog label or one custom changelog fragment, not both.')
        }
        if ($fragment -and $fragment.Impact -ne $releaseImpact) {
            $messages.Add("Changelog fragment impact '$($fragment.Impact)' must match release label 'release:$releaseImpact'.")
        }
        if ($resolvedChangelogType -eq 'breaking' -and $releaseImpact -ne 'major') {
            $messages.Add('changelog:breaking and breaking changelog fragments require release:major.')
        }
    }

    return [PSCustomObject]@{
        IsValid       = $messages.Count -eq 0
        Messages      = $messages.ToArray()
        ReleaseImpact = $releaseImpact
        ChangelogType = $resolvedChangelogType
        Fragment      = $fragment
    }
}
