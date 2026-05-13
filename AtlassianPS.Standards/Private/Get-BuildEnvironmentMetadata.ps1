function Get-BuildEnvironmentMetadata {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [String]$ProjectPath
    )

    $buildSystem = 'Unknown'
    $branchName = ''
    $commitHash = ''
    $buildNumber = '0'
    $commitMessage = ''

    if ($env:GITHUB_ACTIONS) {
        $buildSystem = 'GitHub Actions'
        $branchName = if ($env:GITHUB_HEAD_REF) { $env:GITHUB_HEAD_REF } else { $env:GITHUB_REF_NAME }
        $commitHash = $env:GITHUB_SHA
        $buildNumber = $env:GITHUB_RUN_NUMBER
        $commitMessage = $env:GITHUB_EVENT_HEAD_COMMIT_MESSAGE
    }
    else {
        $branchName = git -C $ProjectPath rev-parse --abbrev-ref HEAD 2>$null
        $commitHash = git -C $ProjectPath rev-parse HEAD 2>$null
        $commitMessage = (git -C $ProjectPath log -1 --pretty=%B 2>$null) -join "`n"
    }

    return [PSCustomObject]@{
        BuildSystem   = $buildSystem
        BranchName    = $branchName
        CommitHash    = $commitHash
        BuildNumber   = $buildNumber
        CommitMessage = $commitMessage
    }
}
