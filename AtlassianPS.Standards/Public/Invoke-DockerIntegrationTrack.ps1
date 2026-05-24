function Invoke-DockerIntegrationTrack {
    <#
    .SYNOPSIS
        Runs a Docker Compose-backed integration-test track with teardown and log capture.

    .DESCRIPTION
        Applies environment defaults, starts Docker Compose, invokes an optional
        readiness/provisioning script, runs the supplied test script block, captures
        service logs on failure, and tears the compose stack down in a finally block.

        Product-specific provisioning stays in the readiness script; this helper only
        owns the lifecycle pattern shared across AtlassianPS module repositories.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'No Invoke-Expression is used; suppression retained only for conservative static rules around command invocation scriptblocks.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ComposeFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ServiceName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [ScriptBlock]$TestScriptBlock,

        [Parameter()]
        [String]$WaitScriptPath,

        [Parameter()]
        [Object[]]$WaitScriptArgumentList = @(),

        [Parameter()]
        [Hashtable]$EnvironmentDefault = @{},

        [Parameter()]
        [String]$LogPath,

        [Parameter()]
        [Switch]$SkipDockerCheck,

        [Parameter()]
        [Switch]$SkipTeardown
    )

    if (-not $SkipDockerCheck -and -not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is required for this integration track. See https://docs.docker.com/get-docker/.'
    }

    $resolvedComposeFile = (Resolve-Path -LiteralPath $ComposeFile).ProviderPath
    if (-not $LogPath) {
        $LogPath = Join-Path -Path (Split-Path -Path $resolvedComposeFile -Parent) -ChildPath "$ServiceName-container.log"
    }

    foreach ($name in $EnvironmentDefault.Keys) {
        if ([String]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
            [Environment]::SetEnvironmentVariable($name, [String]$EnvironmentDefault[$name])
        }
    }

    $startedAt = Get-Date
    try {
        docker compose -f $resolvedComposeFile up -d
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose up failed with exit code $LASTEXITCODE."
        }

        if ($WaitScriptPath) {
            $resolvedWaitScriptPath = (Resolve-Path -LiteralPath $WaitScriptPath).ProviderPath
            & $resolvedWaitScriptPath @WaitScriptArgumentList
            if ($LASTEXITCODE -ne 0) {
                throw "Wait script '$resolvedWaitScriptPath' failed with exit code $LASTEXITCODE."
            }
        }

        & $TestScriptBlock
        if ($LASTEXITCODE -ne 0) {
            throw "Integration test script failed with exit code $LASTEXITCODE."
        }

        return [PSCustomObject]@{
            ComposeFile = $resolvedComposeFile
            ServiceName = $ServiceName
            LogPath     = $LogPath
            Duration    = (Get-Date) - $startedAt
        }
    }
    catch {
        try {
            docker compose -f $resolvedComposeFile logs $ServiceName > $LogPath
        }
        catch {
            Write-Warning "Failed to capture Docker service logs for '$ServiceName': $_"
        }
        throw
    }
    finally {
        if (-not $SkipTeardown) {
            docker compose -f $resolvedComposeFile down -v
        }
    }
}
