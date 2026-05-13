function Invoke-StyleLintTests {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$StyleTestPath,

        [Parameter()]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$PesterVerbosity = 'Normal',

        [Parameter()]
        [Version]$MinimumPesterVersion = [Version]'5.7.0'
    )

    $pesterVersion = Import-PesterVersion -MinimumVersion $MinimumPesterVersion
    if (-not $pesterVersion) {
        $pesterVersion = [Version]'5.7.0'
    }

    if ($pesterVersion.Major -ge 5) {
        $pesterConfigHash = @{
            Run    = @{
                PassThru = $true
                Path     = $StyleTestPath
            }
            Output = @{
                Verbosity = $PesterVerbosity
            }
        }
        $pesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash
        return (Invoke-Pester -Configuration $pesterConfig)
    }

    return (Invoke-Pester -Script $StyleTestPath -PassThru)
}
