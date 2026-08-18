function Import-PesterVersion {
    [CmdletBinding()]
    [OutputType([Version])]
    param(
        [Parameter()]
        [Version]$MinimumVersion = [Version]'5.7.0',

        [Parameter()]
        [Version]$MaximumVersion
    )

    $pesterVersionToUse = Get-UsablePesterVersion -MinimumVersion $MinimumVersion -MaximumVersion $MaximumVersion
    $loadedPester = Get-Module -Name 'Pester' | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($loadedPester -and $loadedPester.Version -ne $pesterVersionToUse) {
        Get-Module -Name 'Pester' | Remove-Module -Force -ErrorAction SilentlyContinue
    }
    Import-Module -Name 'Pester' -RequiredVersion $pesterVersionToUse -Global -ErrorAction Stop

    return $pesterVersionToUse
}
