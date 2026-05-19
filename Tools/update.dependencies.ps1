#requires -Module PowerShellGet

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [Switch]$SkipBuildRequirement,

    [Parameter()]
    [Switch]$SkipManifestRequirement
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
$moduleSourcePath = Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psm1'

try {
    Import-Module -Name $moduleSourcePath -Force -ErrorAction Stop
}
catch {
    throw "Failed to import AtlassianPS.Standards module source from '$moduleSourcePath'. Original error: $($_.Exception.Message)"
}

$result = AtlassianPS.Standards\Update-DependencyReference `
    -BuildRequirementsPath (Join-Path -Path $projectRoot -ChildPath 'Tools/build.requirements.psd1') `
    -ManifestPath (Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1') `
    -SkipBuildRequirement:$SkipBuildRequirement `
    -SkipManifestRequirement:$SkipManifestRequirement `
    -ErrorAction Stop

$result
