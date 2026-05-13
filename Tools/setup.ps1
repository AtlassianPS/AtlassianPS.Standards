#requires -Module PowerShellGet
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function ConvertTo-NormalizedRequirement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object]$Requirement
    )

    if ($Requirement -is [string]) {
        throw "Module requirement '$Requirement' must specify RequiredVersion or ModuleVersion."
    }

    $moduleName = $null
    if ($Requirement -is [System.Collections.IDictionary]) {
        $moduleName = [string]$Requirement['ModuleName']
    }
    else {
        $moduleName = [string]$Requirement.ModuleName
    }
    if (-not $moduleName) {
        throw "Invalid module requirement entry: missing ModuleName."
    }

    $requiredVersion = $null
    if ($Requirement -is [System.Collections.IDictionary]) {
        if ($Requirement.Contains('RequiredVersion') -and $Requirement['RequiredVersion']) {
            $requiredVersion = [string]$Requirement['RequiredVersion']
        }
        elseif ($Requirement.Contains('ModuleVersion') -and $Requirement['ModuleVersion']) {
            $requiredVersion = [string]$Requirement['ModuleVersion']
        }
    }
    else {
        if ($Requirement.PSObject.Properties.Name -contains 'RequiredVersion' -and $Requirement.RequiredVersion) {
            $requiredVersion = [string]$Requirement.RequiredVersion
        }
        elseif ($Requirement.PSObject.Properties.Name -contains 'ModuleVersion' -and $Requirement.ModuleVersion) {
            $requiredVersion = [string]$Requirement.ModuleVersion
        }
    }

    if (-not $requiredVersion) {
        throw "Module requirement '$moduleName' must specify RequiredVersion or ModuleVersion."
    }

    return [PSCustomObject]@{
        ModuleName      = $moduleName
        RequiredVersion = $requiredVersion
    }
}

$requirementsPath = Join-Path -Path $PSScriptRoot -ChildPath 'build.requirements.psd1'
$manifestPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1'

$buildRequirements = @(Import-PowerShellDataFile -Path $requirementsPath)
$manifestData = Import-PowerShellDataFile -Path $manifestPath
$manifestRequirements = @($manifestData.RequiredModules)

$requirementsByName = @{}

foreach ($entry in $buildRequirements) {
    $normalized = ConvertTo-NormalizedRequirement -Requirement $entry
    $requirementsByName[$normalized.ModuleName.ToLowerInvariant()] = $normalized
}

foreach ($entry in $manifestRequirements) {
    $normalized = ConvertTo-NormalizedRequirement -Requirement $entry
    $requirementsByName[$normalized.ModuleName.ToLowerInvariant()] = $normalized
}

$requirements = @($requirementsByName.Values | Sort-Object -Property ModuleName)

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
