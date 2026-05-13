function Get-HostPlatformInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $isWindows = (-not (Get-Variable -Name IsWindows -ErrorAction Ignore)) -or $IsWindows
    $isLinux = (Get-Variable -Name IsLinux -ErrorAction Ignore) -and $IsLinux
    $isMacOS = (Get-Variable -Name IsMacOS -ErrorAction Ignore) -and $IsMacOS
    $isCoreCLR = $PSVersionTable.ContainsKey('PSEdition') -and $PSVersionTable.PSEdition -eq 'Core'

    $os = 'Unknown'
    $osVersion = $PSVersionTable.OS

    switch ($true) {
        { $isWindows } {
            $os = 'Windows'
            if (-not $isCoreCLR) {
                $osVersion = $PSVersionTable.BuildVersion.ToString()
            }
            break
        }
        { $isLinux } {
            $os = 'Linux'
            break
        }
        { $isMacOS } {
            $os = 'OSX'
            break
        }
    }

    return [PSCustomObject]@{
        OS        = $os
        OSVersion = $osVersion
    }
}
