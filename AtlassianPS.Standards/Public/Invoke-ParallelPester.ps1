function Invoke-ParallelPester {
    <#
    .SYNOPSIS
        Runs Pester test files in parallel on PowerShell 7 and sequentially on Windows PowerShell 5.1.

    .DESCRIPTION
        Executes each discovered test file in its own invocation, using Start-ThreadJob
        on PowerShell 7+ with a per-file timeout. This preserves isolation between
        integration files while preventing one hung runspace from blocking summary
        and result generation for all other files.

    .PARAMETER Path
        Test directory paths or explicit test file paths. Directories are searched for *.Tests.ps1 files.

    .PARAMETER ThrottleLimit
        Maximum number of concurrently running test files on PowerShell 7+.

    .PARAMETER Tag
        Pester tags to include.

    .PARAMETER ExcludeTag
        Pester tags to exclude.

    .PARAMETER Output
        Pester output verbosity.

    .PARAMETER OutputPath
        Optional merged NUnit XML output path.

    .PARAMETER ProjectRoot
        Repository root used as the working directory for each Pester invocation.

    .PARAMETER EnvironmentFilePath
        Optional .env file to load before running tests. Defaults to .env under ProjectRoot.

    .PARAMETER EnvironmentExcludeName
        Environment variable names to skip when loading EnvironmentFilePath.

    .PARAMETER PerFileTimeoutSeconds
        Per-test-file timeout budget for parallel runs.

    .PARAMETER SuiteName
        Suite name used when merging NUnit XML output.

    .OUTPUTS
        PSCustomObject with Passed, Failed, Skipped, Duration, and per-file Results.

    .EXAMPLE
        Invoke-AtlassianPSParallelPester -Path './Tests/Integration' -Tag Integration -ThrottleLimit 4 -OutputPath 'Test-Integration.xml'

        Runs integration test files in parallel and writes one merged test result file.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive build/test helper with colored operator output.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [String[]]$Path = './Tests/Integration/',

        [Parameter()]
        [ValidateRange(1, 64)]
        [Int]$ThrottleLimit = 4,

        [Parameter()]
        [String[]]$Tag,

        [Parameter()]
        [String[]]$ExcludeTag,

        [Parameter()]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$Output = 'Normal',

        [Parameter()]
        [String]$OutputPath,

        [Parameter()]
        [String]$ProjectRoot = (Get-Location).Path,

        [Parameter()]
        [String]$EnvironmentFilePath,

        [Parameter()]
        [String[]]$EnvironmentExcludeName = @(),

        [Parameter()]
        [ValidateRange(1, [Int]::MaxValue)]
        [Int]$PerFileTimeoutSeconds = 600,

        [Parameter()]
        [String]$SuiteName = 'AtlassianPS Pester Tests'
    )

    $canParallel = $PSVersionTable.PSVersion.Major -ge 7
    if (-not $canParallel) {
        Write-Warning 'PowerShell 5.1 detected: running tests sequentially. Use PowerShell 7+ for parallel execution.'
    }

    $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
    if (-not $EnvironmentFilePath) {
        $EnvironmentFilePath = Join-Path -Path $resolvedProjectRoot -ChildPath '.env'
    }
    $null = Import-DotEnvFile -Path $EnvironmentFilePath -ExcludeName $EnvironmentExcludeName

    $testFiles = @(Resolve-AtlassianPSPesterTestFile -Path $Path)

    if ($testFiles.Count -eq 0) {
        Write-Warning "No test files found in: $($Path -join ', ')"
        return [PSCustomObject]@{
            Passed  = 0
            Failed  = 0
            Skipped = 0
            Results = @()
        }
    }

    $tempResultsDir = $null
    $generateXml = [Boolean]$OutputPath
    if ($generateXml) {
        $tempResultsDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "AtlassianPS-TestResults-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $null = New-Item -ItemType Directory -Path $tempResultsDir -Force
    }

    $executionMode = if ($canParallel) { "ThrottleLimit=$ThrottleLimit" } else { 'sequential (PS 5.1)' }
    Write-Host "Running $($testFiles.Count) test files ($executionMode)" -ForegroundColor Cyan
    Write-Host ''

    $startTime = Get-Date
    $runTestScriptBlock = New-AtlassianPSPesterRunScriptBlock

    if ($canParallel) {
        $results = Invoke-AtlassianPSPesterJobSet `
            -TestFile $testFiles `
            -RunTestScriptBlock $runTestScriptBlock `
            -ProjectRoot $resolvedProjectRoot `
            -Tag $Tag `
            -ExcludeTag $ExcludeTag `
            -Output $Output `
            -TempResultsDir $tempResultsDir `
            -GenerateXml $generateXml `
            -ThrottleLimit $ThrottleLimit `
            -PerFileTimeoutSeconds $PerFileTimeoutSeconds `
            -StreamingHost $Host
    }
    else {
        $results = Invoke-AtlassianPSPesterFileSet `
            -TestFile $testFiles `
            -RunTestScriptBlock $runTestScriptBlock `
            -ProjectRoot $resolvedProjectRoot `
            -Tag $Tag `
            -ExcludeTag $ExcludeTag `
            -Output $Output `
            -TempResultsDir $tempResultsDir `
            -GenerateXml $generateXml
    }

    $endTime = Get-Date
    $totalDuration = $endTime - $startTime
    $summary = Write-AtlassianPSPesterSummary -Results $results -Duration $totalDuration

    if ($OutputPath -and (Test-Path -LiteralPath $tempResultsDir -PathType Container)) {
        Merge-AtlassianPSPesterXml -TempResultsDir $tempResultsDir -OutputPath $OutputPath -SuiteName $SuiteName -Duration $totalDuration -Summary $summary -ProjectRoot $resolvedProjectRoot
    }

    if ($summary.Failed -gt 0) {
        throw "$($summary.Failed) test(s) failed."
    }

    return [PSCustomObject]@{
        Passed   = $summary.Passed
        Failed   = $summary.Failed
        Skipped  = $summary.Skipped
        Duration = $totalDuration
        Results  = $results
    }
}
