function Invoke-Lint {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath = $env:BHProjectPath,

        [Parameter()]
        [String]$ModulePath = $env:BHModulePath,

        [Parameter()]
        [String]$BuildScriptPath,

        [Parameter()]
        [String]$StyleTestPath,

        [Parameter()]
        [String]$AnalyzerSettingsPath,

        [Parameter()]
        [String[]]$AnalyzerPaths,

        [Parameter()]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$PesterVerbosity = 'Normal',

        [Parameter()]
        [Version]$MinimumPesterVersion = [Version]'5.7.0',

        [Parameter()]
        [ValidateSet('Error', 'Warning', 'Information', 'ParseError')]
        [String[]]$Severity = @('Error', 'Warning'),

        [Parameter()]
        [Switch]$SkipStyleTests,

        [Parameter()]
        [Switch]$SkipScriptAnalyzer
    )

    if (-not $ProjectPath) {
        throw 'ProjectPath is required. Provide -ProjectPath or set $env:BHProjectPath.'
    }

    $projectPathResolved = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
    $failures = [System.Collections.Generic.List[String]]::new()
    $styleFailures = 0
    $analyzerIssueCount = 0
    $isGitHubActions = [bool]$env:GITHUB_ACTIONS
    $writeLintMessage = {
        param(
            [Parameter(Mandatory)]
            [String]$Color,

            [Parameter(Mandatory)]
            [String]$Message
        )

        if (Get-Command -Name Write-Build -ErrorAction SilentlyContinue) {
            Write-Build $Color $Message
            return
        }

        Write-Output $Message
    }

    if (-not $BuildScriptPath -and $env:BHProjectName) {
        $BuildScriptPath = Join-Path -Path $projectPathResolved -ChildPath "$($env:BHProjectName).build.ps1"
    }

    if (-not $StyleTestPath) {
        $StyleTestPath = Join-Path -Path $projectPathResolved -ChildPath 'Tests/Style.Tests.ps1'
    }

    if (-not $AnalyzerSettingsPath) {
        $AnalyzerSettingsPath = Get-ScriptAnalyzerSettingsPath
    }

    if (-not $AnalyzerPaths) {
        $AnalyzerPaths = @(
            $ModulePath
            (Join-Path -Path $projectPathResolved -ChildPath 'Tests')
            (Join-Path -Path $projectPathResolved -ChildPath 'Tools')
            $BuildScriptPath
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    }

    if (-not (Test-Path -LiteralPath $AnalyzerSettingsPath -PathType Leaf)) {
        throw "Analyzer settings file was not found at '$AnalyzerSettingsPath'."
    }

    if ($AnalyzerPaths.Count -eq 0 -and -not $SkipScriptAnalyzer) {
        throw 'No analyzer paths were discovered. Provide -AnalyzerPaths or set build environment paths.'
    }

    if (-not $SkipStyleTests) {
        if (Test-Path -LiteralPath $StyleTestPath -PathType Leaf) {
            & $writeLintMessage -Color Gray -Message 'Running style tests...'
            $testResults = Invoke-StyleLintTests `
                -StyleTestPath $StyleTestPath `
                -PesterVerbosity $PesterVerbosity `
                -MinimumPesterVersion $MinimumPesterVersion

            $styleFailures = [int]$testResults.FailedCount
            if ($styleFailures -gt 0) {
                $failures.Add("$styleFailures style test(s) failed.")
            }
            else {
                & $writeLintMessage -Color Green -Message 'Style tests: passed.'
            }
        }
        else {
            & $writeLintMessage -Color Yellow -Message "Style tests skipped because '$StyleTestPath' was not found."
        }
    }

    if (-not $SkipScriptAnalyzer) {
        & $writeLintMessage -Color Gray -Message 'Running PSScriptAnalyzer...'

        $results = Invoke-ScriptAnalyzerLint `
            -AnalyzerPaths $AnalyzerPaths `
            -AnalyzerSettingsPath $AnalyzerSettingsPath `
            -Severity $Severity `
            -ProjectPath $projectPathResolved `
            -IsGitHubActions $isGitHubActions

        $analyzerIssueCount = @($results).Count
        if ($analyzerIssueCount -gt 0) {
            $failures.Add("$analyzerIssueCount PSScriptAnalyzer issue(s) found.")
        }
        else {
            & $writeLintMessage -Color Green -Message 'PSScriptAnalyzer: no issues found.'
        }
    }

    if ($failures.Count -gt 0) {
        throw ("Lint failed:`n  - " + ($failures -join "`n  - "))
    }

    return [PSCustomObject]@{
        StyleFailedCount   = $styleFailures
        AnalyzerIssueCount = $analyzerIssueCount
        AnalyzerPathCount  = $AnalyzerPaths.Count
    }
}
