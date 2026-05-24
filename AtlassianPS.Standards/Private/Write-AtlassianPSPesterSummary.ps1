function Write-AtlassianPSPesterSummary {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive build/test helper with colored operator output.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [Object[]]$Results,

        [Parameter(Mandatory)]
        [TimeSpan]$Duration
    )

    $totalPassed = 0
    $totalFailed = 0
    $totalSkipped = 0
    $allFailedTests = @()
    $allSkippedTests = @()

    foreach ($result in $Results) {
        $totalPassed += $result.Passed
        $totalFailed += $result.Failed
        $totalSkipped += $result.Skipped
        if ($result.Error) {
            Write-Host "[ERROR] $($result.File): $($result.Error)" -ForegroundColor Red
        }
        foreach ($failedTest in @($result.FailedTests)) {
            $allFailedTests += [PSCustomObject]@{ File = $result.File; Test = $failedTest.Name; ErrorMessage = $failedTest.ErrorMessage }
        }
        foreach ($skippedTest in @($result.SkippedTests)) {
            $allSkippedTests += [PSCustomObject]@{ File = $result.File; Test = $skippedTest.Name; Reason = $skippedTest.Reason }
        }
    }

    if ($allFailedTests.Count -gt 0) {
        Write-Host ''
        Write-Host '========== FAILED TESTS ==========' -ForegroundColor Red
        foreach ($failedTest in $allFailedTests) {
            Write-Host "  $($failedTest.File)" -ForegroundColor Yellow -NoNewline
            Write-Host ' :: ' -NoNewline
            Write-Host "$($failedTest.Test)" -ForegroundColor White
            Write-Host "    $($failedTest.ErrorMessage)" -ForegroundColor DarkGray
        }
        Write-Host '==================================' -ForegroundColor Red
        Write-Host ''
    }

    if ($allSkippedTests.Count -gt 0) {
        Write-Host ''
        Write-Host '========== SKIPPED TESTS ==========' -ForegroundColor Yellow
        foreach ($skippedTest in $allSkippedTests) {
            Write-Host "  $($skippedTest.File)" -ForegroundColor Yellow -NoNewline
            Write-Host ' :: ' -NoNewline
            Write-Host "$($skippedTest.Test)" -ForegroundColor White
            Write-Host "    $($skippedTest.Reason)" -ForegroundColor DarkGray
        }
        Write-Host '===================================' -ForegroundColor Yellow
        Write-Host ''
    }

    Write-Host ''
    Write-Host '========== TEST SUMMARY ==========' -ForegroundColor Cyan
    Write-Host "  Total:   $($totalPassed + $totalFailed + $totalSkipped)" -ForegroundColor White
    Write-Host "  Passed:  $totalPassed" -ForegroundColor Green
    Write-Host "  Failed:  $totalFailed" -ForegroundColor $(if ($totalFailed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Skipped: $totalSkipped" -ForegroundColor Yellow
    Write-Host "  Duration: $($Duration.ToString('hh\:mm\:ss\.fff'))" -ForegroundColor White
    Write-Host '==================================' -ForegroundColor Cyan

    return [PSCustomObject]@{
        Passed  = $totalPassed
        Failed  = $totalFailed
        Skipped = $totalSkipped
    }
}
