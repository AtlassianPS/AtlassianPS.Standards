function Initialize-IntegrationEnvironment {
    <#
    .SYNOPSIS
        Loads and validates shared integration-test environment configuration.

    .DESCRIPTION
        Loads an optional .env file, selects a deployment track, validates required
        environment variables for that track, and returns a normalized object with
        track metadata and requested environment values.

        Product-specific helpers should pass their Cloud/Data Center schemas here,
        then read the validated environment variables directly when constructing
        JiraPS or ConfluencePS-specific test objects. Values are not returned to
        avoid accidentally writing secrets to build logs.

    .PARAMETER TrackEnvironmentVariableName
        Environment variable name that selects the integration track, for example CI_JIRA_TYPE.

    .PARAMETER DefaultTrack
        Track to use when TrackEnvironmentVariableName is unset.

    .PARAMETER RequiredVariableByTrack
        Hashtable keyed by track name, with required environment variable names as values.

    .PARAMETER OptionalVariableByTrack
        Hashtable keyed by track name, with optional environment variable names as values.

    .PARAMETER DotEnvPath
        Optional .env file to load before validating variables.

    .PARAMETER DotEnvExcludeName
        Environment variable names to skip when loading DotEnvPath.

    .PARAMETER WarnOnly
        Writes a warning and returns null instead of throwing when required variables are missing.

    .OUTPUTS
        PSCustomObject with Track, IsDefaultTrack, RequiredVariables, and OptionalVariables. Returns null in WarnOnly mode when required variables are missing.

    .EXAMPLE
        Initialize-AtlassianPSIntegrationEnvironment -TrackEnvironmentVariableName 'CI_JIRA_TYPE' -DefaultTrack 'Cloud' -RequiredVariableByTrack @{ Cloud = @('JIRA_CLOUD_URL'); Server = @('CI_JIRA_URL') }

        Validates the variables required by the selected integration test track.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$TrackEnvironmentVariableName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DefaultTrack,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Hashtable]$RequiredVariableByTrack,

        [Parameter()]
        [Hashtable]$OptionalVariableByTrack = @{},

        [Parameter()]
        [String]$DotEnvPath,

        [Parameter()]
        [String[]]$DotEnvExcludeName = @(),

        [Parameter()]
        [Switch]$WarnOnly
    )

    if ($DotEnvPath) {
        $null = Import-AtlassianPSDotEnvFile -Path $DotEnvPath -ExcludeName $DotEnvExcludeName
    }

    $track = [Environment]::GetEnvironmentVariable($TrackEnvironmentVariableName)
    if ([String]::IsNullOrWhiteSpace($track)) {
        $track = $DefaultTrack
    }

    $validTracks = @($RequiredVariableByTrack.Keys)
    if ($track -notin $validTracks) {
        throw "Invalid $TrackEnvironmentVariableName '$track'. Must be one of: $($validTracks -join ', ')."
    }

    $requiredVariables = @($RequiredVariableByTrack[$track])
    $optionalVariables = if ($OptionalVariableByTrack.ContainsKey($track)) {
        @($OptionalVariableByTrack[$track])
    }
    else {
        @()
    }

    $missing = @(
        foreach ($name in $requiredVariables) {
            if ([String]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name))) {
                $name
            }
        }
    )

    if ($missing.Count -gt 0) {
        $message = "Required environment variables for the $track integration test track are not set: $($missing -join ', ')"
        if ($WarnOnly) {
            Write-Warning $message
            return $null
        }
        throw $message
    }

    return [PSCustomObject]@{
        Track             = $track
        IsDefaultTrack    = $track -eq $DefaultTrack
        RequiredVariables = $requiredVariables
        OptionalVariables = $optionalVariables
    }
}
