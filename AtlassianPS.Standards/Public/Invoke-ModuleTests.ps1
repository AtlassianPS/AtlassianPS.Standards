function Invoke-ModuleTests {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$TestPath,

        [Parameter()]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$PesterVerbosity = 'Normal',

        [Parameter()]
        [String[]]$Tag,

        [Parameter()]
        [String[]]$ExcludeTag,

        [Parameter()]
        [String[]]$DefaultExcludeTag = @('Integration'),

        [Parameter()]
        [String[]]$ExcludePath = @(),

        [Parameter()]
        [Version]$MinimumPesterVersion = [Version]'6.2.0',

        [Parameter()]
        [Version]$MaximumPesterVersion = [Version]'6.999',

        [Parameter()]
        [String]$ResultOutputPath
    )

    $resolvedTestPath = (Resolve-Path -LiteralPath $TestPath).ProviderPath
    $null = Import-PesterVersion -MinimumVersion $MinimumPesterVersion -MaximumVersion $MaximumPesterVersion

    if (-not $ResultOutputPath) {
        $platformInfo = Get-HostPlatformInfo
        $resultRootPath = if ($env:BHProjectPath) {
            $env:BHProjectPath
        }
        else {
            Split-Path -Path $resolvedTestPath -Parent
        }
        $ResultOutputPath = Join-Path -Path $resultRootPath -ChildPath "Test-$($platformInfo.OS)-$($PSVersionTable.PSVersion.ToString()).xml"
    }

    $pesterConfigHash = @{
        Run        = @{
            PassThru = $true
            Path     = $resolvedTestPath
        }
        TestResult = @{
            Enabled      = $true
            OutputFormat = 'NUnitXml'
            OutputPath   = $ResultOutputPath
        }
        Output     = @{
            Verbosity = $PesterVerbosity
        }
        Filter     = @{
            ExcludeTag = @($DefaultExcludeTag)
        }
    }

    if ($ExcludePath.Count -gt 0) {
        $pesterConfigHash.Run.ExcludePath = @($ExcludePath)
    }

    if ($Tag) {
        $pesterConfigHash.Filter.Tag = $Tag
        $pesterConfigHash.Filter.ExcludeTag = @($pesterConfigHash.Filter.ExcludeTag | Where-Object { $_ -notin $Tag })
        if ($Tag -contains 'Integration') {
            $pesterConfigHash.Run.ExcludePath = @()
        }
    }

    if ($ExcludeTag) {
        $merged = @($pesterConfigHash.Filter.ExcludeTag) + @($ExcludeTag) | Select-Object -Unique
        if ($Tag) {
            $merged = @($merged | Where-Object { $_ -notin $Tag })
        }
        $pesterConfigHash.Filter.ExcludeTag = @($merged)
    }

    $pesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash
    $testResults = Invoke-Pester -Configuration $pesterConfig

    $failedBlockCount = 0
    if ($testResults.PSObject.Properties.Name -contains 'FailedBlocksCount') {
        $failedBlockCount = [int]$testResults.FailedBlocksCount
    }

    $failedContainerCount = 0
    if ($testResults.PSObject.Properties.Name -contains 'FailedContainersCount') {
        $failedContainerCount = [int]$testResults.FailedContainersCount
    }

    $failureCount = [int]$testResults.FailedCount + $failedBlockCount + $failedContainerCount
    if ($failureCount -gt 0) {
        throw ("Pester reported failures. Failed tests: {0}; failed blocks: {1}; failed containers: {2}." -f $testResults.FailedCount, $failedBlockCount, $failedContainerCount)
    }

    return $testResults
}
