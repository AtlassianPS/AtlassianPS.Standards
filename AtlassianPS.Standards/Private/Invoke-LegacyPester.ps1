function Invoke-LegacyPester {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [Hashtable]$Parameters
    )

    return (Invoke-Pester @Parameters)
}
