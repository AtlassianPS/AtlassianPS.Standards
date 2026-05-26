function Invoke-ScriptAnalyzerLint {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String[]]$AnalyzerPaths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$AnalyzerSettingsPath,

        [Parameter()]
        [ValidateSet('Error', 'Warning', 'Information', 'ParseError')]
        [String[]]$Severity = @('Error', 'Warning'),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath,

        [Parameter()]
        [Boolean]$IsGitHubActions
    )

    $analyzerParams = @{
        Settings = $AnalyzerSettingsPath
        Severity = $Severity
        Recurse  = $true
    }

    $results = @(
        foreach ($path in $AnalyzerPaths) {
            Invoke-ScriptAnalyzer -Path $path @analyzerParams
        }
    )

    foreach ($result in $results) {
        $color = if ($result.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
        $location = if ($result.ScriptName) { $result.ScriptName } else { '<unknown>' }
        $message = "[$($result.Severity)] ${location}:$($result.Line) - $($result.RuleName): $($result.Message)"
        if (Get-Command -Name Write-Build -ErrorAction SilentlyContinue) {
            Write-Build $color $message
        }
        else {
            Write-Output $message
        }

        if ($IsGitHubActions -and $result.ScriptPath) {
            $level = if ($result.Severity -eq 'Error') { 'error' } else { 'warning' }
            $relativePath = Get-ProjectRelativePath -BasePath $ProjectPath -TargetPath $result.ScriptPath
            $message = ($result.Message -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')
            Write-WorkflowCommand -Command "::${level} file=$relativePath,line=$($result.Line),col=$($result.Column),title=$($result.RuleName)::$message"
        }
    }

    return $results
}
