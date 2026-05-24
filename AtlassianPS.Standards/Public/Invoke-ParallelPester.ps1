function Invoke-ParallelPester {
    <#
    .SYNOPSIS
        Runs Pester test files in parallel on PowerShell 7 and sequentially on Windows PowerShell 5.1.

    .DESCRIPTION
        Executes each discovered test file in its own invocation, using Start-ThreadJob
        on PowerShell 7+ with a per-file timeout. This preserves isolation between
        integration files while preventing one hung runspace from blocking summary
        and result generation for all other files.
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

    $testFiles = @()
    foreach ($item in $Path) {
        $resolvedPath = Resolve-Path -Path $item -ErrorAction SilentlyContinue
        if ($resolvedPath) {
            foreach ($pathInfo in $resolvedPath) {
                if (Test-Path -LiteralPath $pathInfo.ProviderPath -PathType Container) {
                    $testFiles += Get-ChildItem -LiteralPath $pathInfo.ProviderPath -Filter '*.Tests.ps1' -File
                }
                else {
                    $testFiles += Get-Item -LiteralPath $pathInfo.ProviderPath
                }
            }
        }
    }
    $testFiles = @($testFiles | Sort-Object -Property FullName -Unique)

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
    $results = @()
    $runTestBodyText = @'
param($testFile, $projectRoot, $tagFilter, $excludeTagFilter, $outputVerbosity, $tempResultsDir, $generateXml)

try {
    function Get-PesterTestInBlock {
        param($Block)
        foreach ($test in $Block.Tests) { $test }
        foreach ($childBlock in $Block.Blocks) { Get-PesterTestInBlock -Block $childBlock }
    }

    Import-Module Pester -MinimumVersion 5.0 -Force
    Set-Location $projectRoot

    $config = New-PesterConfiguration
    $config.Run.Path = $testFile.FullName
    $config.Run.PassThru = $true
    $config.Output.Verbosity = $outputVerbosity
    if ($generateXml -and $tempResultsDir) {
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = Join-Path $tempResultsDir "$($testFile.BaseName).xml"
    }
    if ($tagFilter) { $config.Filter.Tag = $tagFilter }
    if ($excludeTagFilter) { $config.Filter.ExcludeTag = $excludeTagFilter }

    $result = Invoke-Pester -Configuration $config
    $failedTests = @()
    $skippedTests = @()
    $allTests = foreach ($container in $result.Containers) {
        foreach ($block in $container.Blocks) { Get-PesterTestInBlock -Block $block }
    }
    foreach ($test in $allTests) {
        if ($test.Result -eq 'Failed') {
            $failedTests += [PSCustomObject]@{
                Name = if ($test.ExpandedPath) { $test.ExpandedPath } else { $test.Name }
                ErrorMessage = if ($test.ErrorRecord) { $test.ErrorRecord[0].Exception.Message } else { 'Unknown error' }
            }
        }
        if ($test.Result -eq 'Skipped') {
            $skippedTests += [PSCustomObject]@{
                Name = if ($test.ExpandedPath) { $test.ExpandedPath } else { $test.Name }
                Reason = if ($test.ErrorRecord) { ($test.ErrorRecord | ForEach-Object { $_.Exception.Message }) -join '; ' } else { 'No skip reason reported' }
            }
        }
    }
    [PSCustomObject]@{
        File = $testFile.Name
        Passed = $result.PassedCount
        Failed = $result.FailedCount
        Skipped = $result.SkippedCount
        Duration = $result.Duration
        Success = $result.FailedCount -eq 0
        FailedTests = $failedTests
        SkippedTests = $skippedTests
        XmlPath = if ($generateXml) { Join-Path $tempResultsDir "$($testFile.BaseName).xml" } else { $null }
    }
}
catch {
    [PSCustomObject]@{
        File = $testFile.Name
        Passed = 0
        Failed = 1
        Skipped = 0
        Duration = [TimeSpan]::Zero
        Success = $false
        Error = $_.Exception.Message
        FailedTests = @([PSCustomObject]@{ Name = 'Script execution'; ErrorMessage = $_.Exception.Message })
        SkippedTests = @()
        XmlPath = $null
    }
}
'@

    if ($canParallel) {
        $jobInfos = New-Object System.Collections.Generic.List[Object]
        foreach ($testFile in $testFiles) {
            $job = Start-ThreadJob `
                -ScriptBlock ([ScriptBlock]::Create($runTestBodyText)) `
                -ArgumentList @($testFile, $resolvedProjectRoot, $Tag, $ExcludeTag, $Output, $tempResultsDir, $generateXml) `
                -ThrottleLimit $ThrottleLimit `
                -StreamingHost $Host `
                -Name "Pester:$($testFile.BaseName)"
            $jobInfos.Add([PSCustomObject]@{ File = $testFile; Job = $job })
        }

        foreach ($info in $jobInfos) {
            $job = $info.Job
            $file = $info.File
            $finished = Wait-Job -Job $job -Timeout $PerFileTimeoutSeconds
            if (-not $finished) {
                Write-Warning "Test file [$($file.Name)] exceeded ${PerFileTimeoutSeconds}s budget; stopping the runspace and recording an orchestrator timeout."
                try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch { Write-Warning "Stop-Job [$($job.Name)] threw: $_" }
                $results += [PSCustomObject]@{
                    File         = $file.Name
                    Passed       = 0
                    Failed       = 1
                    Skipped      = 0
                    Duration     = [TimeSpan]::FromSeconds($PerFileTimeoutSeconds)
                    Success      = $false
                    Error        = "Per-file orchestrator timeout (${PerFileTimeoutSeconds}s)."
                    FailedTests  = @([PSCustomObject]@{ Name = 'Orchestrator timeout'; ErrorMessage = "Test file [$($file.Name)] timed out after ${PerFileTimeoutSeconds}s." })
                    SkippedTests = @()
                    XmlPath      = $null
                }
            }
            else {
                try {
                    $jobOutput = Receive-Job -Job $job -ErrorAction Stop 6> $null
                    if ($null -ne $jobOutput) { $results += $jobOutput }
                }
                catch {
                    Write-Warning "Receive-Job [$($job.Name)] threw: $_"
                    $results += [PSCustomObject]@{
                        File         = $file.Name
                        Passed       = 0
                        Failed       = 1
                        Skipped      = 0
                        Duration     = [TimeSpan]::Zero
                        Success      = $false
                        Error        = "Receive-Job failed: $_"
                        FailedTests  = @([PSCustomObject]@{ Name = 'Receive-Job failure'; ErrorMessage = $_.Exception.Message })
                        SkippedTests = @()
                        XmlPath      = $null
                    }
                }
            }
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Remove-Job [$($job.Name)] threw: $_" }
        }
    }
    else {
        $runTestFile = [ScriptBlock]::Create($runTestBodyText)
        foreach ($testFile in $testFiles) {
            $results += & $runTestFile $testFile $resolvedProjectRoot $Tag $ExcludeTag $Output $tempResultsDir $generateXml
        }
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
