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
    # Pester test scripts execute outside this module scope. Import globally even when the
    # selected version is already module-scoped so its commands remain available on Linux.
    Import-Module -Name 'Pester' -RequiredVersion $pesterVersionToUse -Global -ErrorAction Stop

    return $pesterVersionToUse
}
