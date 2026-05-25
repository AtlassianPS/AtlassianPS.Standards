function New-AtlassianPSPesterRunScriptBlock {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory scriptblock only; does not change system state.')]
    [CmdletBinding()]
    [OutputType([ScriptBlock])]
    param()

    [ScriptBlock]::Create(@'
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
'@)
}
