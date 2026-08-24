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
        [Version]$MinimumPesterVersion = [Version]'5.9.0',

        [Parameter()]
        [Version]$MaximumPesterVersion = [Version]'5.9.999'
    )

    $pesterVersion = Import-PesterVersion -MinimumVersion $MinimumPesterVersion -MaximumVersion $MaximumPesterVersion
    if (-not $pesterVersion) {
        $pesterVersion = $MinimumPesterVersion
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
