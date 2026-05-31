if (-not $env:PR_NUMBER) {
    throw 'validate-release-intent requires a pull request number. Run it from pull_request_target or pass pr-number.'
}

. (Join-Path -Path $PSScriptRoot -ChildPath '../_shared/release-intent-core.ps1')

$issueLabelsRoute = 'repos/{0}/issues/{1}/labels' -f $env:GITHUB_REPOSITORY, $env:PR_NUMBER
$pullFilesRoute = 'repos/{0}/pulls/{1}/files' -f $env:GITHUB_REPOSITORY, $env:PR_NUMBER
$issueCommentsRoute = 'repos/{0}/issues/{1}/comments' -f $env:GITHUB_REPOSITORY, $env:PR_NUMBER

$labels = @(gh api $issueLabelsRoute --paginate --jq '.[].name')
$changedFiles = @(gh api $pullFilesRoute --paginate --jq '.[].filename')
$removedFiles = @(gh api $pullFilesRoute --paginate --jq '.[] | select(.status == "removed") | .filename')

$messages = [System.Collections.Generic.List[String]]::new()

$activeChangedFiles = @($changedFiles | Where-Object { $_ -notin $removedFiles })
$escapedDirectory = [Regex]::Escape($env:CHANGELOG_DIRECTORY.TrimEnd('/'))
$fragmentPattern = "^$escapedDirectory/$env:PR_NUMBER\.(?<impact>patch|minor|major)\.(?<type>added|changed|fixed|removed|deprecated|security|breaking)\.md$"
$changelogFiles = @(
    $activeChangedFiles |
        Where-Object { $_ -eq $env:CHANGELOG_DIRECTORY -or $_ -like "$($env:CHANGELOG_DIRECTORY.TrimEnd('/'))/*" } |
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
foreach ($path in @($changelogFiles | Where-Object { -not [Regex]::IsMatch($_, $fragmentPattern) })) {
    $messages.Add("Changelog fragment '$path' must be named '$($env:CHANGELOG_DIRECTORY.TrimEnd('/'))/$env:PR_NUMBER.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md'.")
}
$intentState = Resolve-ReleaseIntentState -Labels $labels -Fragments $matchingFragments -HasChangelogFilesForNone ($changelogFiles.Count -gt 0) -Context "PR #$env:PR_NUMBER"
foreach ($message in $intentState.Messages) {
    $messages.Add($message)
}

$isValid = $messages.Count -eq 0

@(
    "is_valid=$($isValid.ToString().ToLowerInvariant())"
    "release_impact=$($intentState.ReleaseImpact)"
    "changelog_type=$($intentState.ChangelogType)"
) | Add-Content -LiteralPath $env:GITHUB_OUTPUT

$marker = '<!-- atlassianps-release-intent -->'
$commentQuery = '.[] | select(.user.login == "github-actions[bot]") | select(.body | startswith("{0}")) | .id' -f $marker
$existingCommentId = gh api $issueCommentsRoute --paginate --jq $commentQuery |
    Select-Object -First 1

if ($isValid) {
    if ($existingCommentId) {
        $commentRoute = 'repos/{0}/issues/comments/{1}' -f $env:GITHUB_REPOSITORY, $existingCommentId
        gh api --method DELETE $commentRoute | Out-Null
    }

    Write-Host "Release intent is valid: release:$($intentState.ReleaseImpact) changelog:$($intentState.ChangelogType)"
    return
}

$messageLines = @(
    $marker
    '## Release Intent Needs Attention'
    ''
    '_This comment is managed by the release-intent workflow._'
    ''
    'This PR must declare how it affects releases before it can be merged.'
    ''
    'Required labels:'
    ''
    '- exactly one of `release:none`, `release:patch`, `release:minor`, or `release:major`'
    '- for user-facing changes, either exactly one `changelog:*` label or one valid custom changelog fragment, not both'
    ''
    'Problems found:'
    ''
)
foreach ($message in $messages) {
    $messageLines += "- $message"
}
$fragmentTemplate = '{0}/{1}.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md' -f $env:CHANGELOG_DIRECTORY, $env:PR_NUMBER
$messageLines += @(
    ''
    'Custom changelog fragments must be named:'
    ''
    $fragmentTemplate
)

$body = $messageLines -join [Environment]::NewLine
$bodyJson = @{ body = $body } | ConvertTo-Json -Compress

if ($existingCommentId) {
    $commentRoute = 'repos/{0}/issues/comments/{1}' -f $env:GITHUB_REPOSITORY, $existingCommentId
    $bodyJson | gh api --method PATCH $commentRoute --input - | Out-Null
}
else {
    $bodyJson | gh api --method POST $issueCommentsRoute --input - | Out-Null
}

foreach ($message in $messages) {
    Write-Error $message -ErrorAction Continue
}

exit 1
