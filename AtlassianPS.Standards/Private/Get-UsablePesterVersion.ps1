function Get-UsablePesterVersion {
    [CmdletBinding()]
    [OutputType([Version])]
    param(
        [Parameter(Mandatory)]
        [Version]$MinimumVersion,

        [Parameter()]
        [Version]$MaximumVersion
    )

    $availablePesterModules = @(
        Get-Module -Name 'Pester' -ListAvailable | Sort-Object -Property Version -Descending
    )

    if ($availablePesterModules.Count -eq 0) {
        throw "Pester version $MinimumVersion or newer is required, but no Pester module is installed."
    }

    $selectedModule = $availablePesterModules |
        Where-Object {
            $_.Version -ge $MinimumVersion -and (
                (-not $MaximumVersion) -or $_.Version -le $MaximumVersion
            )
        } |
        Select-Object -First 1

    if (-not $selectedModule) {
        if ($MaximumVersion) {
            throw "Pester version between $MinimumVersion and $MaximumVersion is required, but no installed version satisfies that range."
        }

        throw "Pester version $MinimumVersion or newer is required, but the highest available version is $($availablePesterModules[0].Version)."
    }

    return $selectedModule.Version
}
