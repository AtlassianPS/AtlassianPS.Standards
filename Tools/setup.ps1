#requires -Module PowerShellGet
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$requirementsPath = Join-Path -Path $PSScriptRoot -ChildPath 'build.requirements.psd1'
$requirements = Import-PowerShellDataFile -Path $requirementsPath

if (-not (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default
}

foreach ($requirement in $requirements) {
    $moduleName = $requirement.ModuleName
    $requiredVersion = [version]$requirement.RequiredVersion

    $installed = Get-Module -Name $moduleName -ListAvailable |
        Where-Object { $_.Version -eq $requiredVersion } |
        Select-Object -First 1

    if ($installed) {
        Write-Verbose "Dependency '$moduleName' $requiredVersion already installed."
        continue
    }

    Write-Verbose "Installing dependency '$moduleName' $requiredVersion."
    Install-Module -Name $moduleName `
        -RequiredVersion $requiredVersion `
        -Scope CurrentUser `
        -Repository 'PSGallery' `
        -AllowClobber `
        -Force
}
