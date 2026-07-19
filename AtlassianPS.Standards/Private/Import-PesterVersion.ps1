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
    if ((-not $loadedPester) -or ($loadedPester.Version -ne $pesterVersionToUse)) {
        if ($loadedPester) {
            Get-Module -Name 'Pester' | Remove-Module -Force -ErrorAction SilentlyContinue
        }
        # Pester test scripts execute outside this module scope. Load commands globally so
        # they remain available after this helper returns on every PowerShell platform.
        Import-Module -Name 'Pester' -RequiredVersion $pesterVersionToUse -Global -ErrorAction Stop
    }

    return $pesterVersionToUse
}
