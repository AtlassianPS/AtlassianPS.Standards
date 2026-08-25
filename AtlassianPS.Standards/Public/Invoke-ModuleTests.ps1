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
        [Version]$MinimumPesterVersion = [Version]'5.9.0',

        [Parameter()]
        [Version]$MaximumPesterVersion = [Version]'5.9.999',

        [Parameter()]
        [String]$ResultOutputPath
    )

    $resolvedTestPath = (Resolve-Path -LiteralPath $TestPath).ProviderPath
    $pesterVersion = Import-PesterVersion -MinimumVersion $MinimumPesterVersion -MaximumVersion $MaximumPesterVersion
    if (-not $pesterVersion) {
        $pesterVersion = [Version]'5.9.0'
    }

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

    if ($pesterVersion.Major -ge 5) {
        $pesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash
        $testResults = Invoke-Pester -Configuration $pesterConfig
    }
    else {
        $invokePesterParams = @{
            Script       = $resolvedTestPath
            PassThru     = $true
            OutputFile   = $ResultOutputPath
            OutputFormat = 'NUnitXml'
        }

        if ($pesterConfigHash.Filter.Tag) {
            $invokePesterParams.Tag = $pesterConfigHash.Filter.Tag
        }

        if ($pesterConfigHash.Filter.ExcludeTag.Count -gt 0) {
            $invokePesterParams.ExcludeTag = $pesterConfigHash.Filter.ExcludeTag
        }

        $testResults = Invoke-Pester @invokePesterParams
    }

    $containerFailureCount = 0
    if ($testResults.PSObject.Properties.Name -contains 'ContainersFailedCount') {
        $containerFailureCount = [int]$testResults.ContainersFailedCount
    }

    if (($testResults.FailedCount -gt 0) -or ($containerFailureCount -gt 0)) {
        throw ("Pester reported failures. Failed tests: {0}; failed containers: {1}." -f $testResults.FailedCount, $containerFailureCount)
    }

    return $testResults
}
