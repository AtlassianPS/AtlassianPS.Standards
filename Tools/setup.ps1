#requires -Module PowerShellGet
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
$moduleSourcePath = Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psm1'

if (-not (Test-Path -LiteralPath $moduleSourcePath -PathType Leaf)) {
    throw "Module source file was not found at '$moduleSourcePath'."
}

Import-Module -Name $moduleSourcePath -Force -ErrorAction Stop

$null = AtlassianPS.Standards\Install-DependencyRequirement `
    -BuildRequirementsPath (Join-Path -Path $projectRoot -ChildPath 'Tools/build.requirements.psd1') `
    -ManifestPath (Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1')
