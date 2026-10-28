[CmdletBinding(DefaultParameterSetName = 'Artifact')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Artifact')]
    [String]$ArtifactPath,

    [Parameter(Mandatory, ParameterSetName = 'Gallery')]
    [String]$ModuleName,

    [Parameter(Mandatory, ParameterSetName = 'Gallery')]
    [String]$RequiredVersion,

    [Parameter(Mandatory, ParameterSetName = 'Stable')]
    [String]$StableModuleName
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../AtlassianPS.Standards/Public/Install-ModuleCandidate.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('candidate-acquisition-' + [Guid]::NewGuid().ToString('N'))
$savedConfigurationRoot = $env:ATLASSIANPS_CONFIGURATION_ROOT
$env:ATLASSIANPS_CONFIGURATION_ROOT = Join-Path $root 'configuration'
try {
    if ($PSCmdlet.ParameterSetName -eq 'Stable') {
        $null = New-Item -Path $root -ItemType Directory
        Save-Module -Name $StableModuleName -Repository PSGallery -Path $root -ErrorAction Stop
        $manifests = @(Get-ChildItem -LiteralPath $root -Filter "$StableModuleName.psd1" -Recurse -File)
        if ($manifests.Count -ne 1) { throw 'Stable acquisition did not resolve one manifest.' }
        $data = Import-PowerShellDataFile -LiteralPath $manifests[0].FullName
        if ($data.PrivateData.PSData.Prerelease) { throw 'Normal acquisition selected a prerelease.' }
        $env:PSModulePath = $root + [IO.Path]::PathSeparator + $env:PSModulePath
        $loaded = Import-Module $manifests[0].FullName -Global -Force -PassThru -ErrorAction Stop
        $expectedPath = (Resolve-Path (Join-Path $manifests[0].DirectoryName $data.RootModule)).ProviderPath
        if ($loaded.Path -cne $expectedPath -or $loaded.Version -ne [Version]$data.ModuleVersion -or $loaded.PrivateData.PSData.Prerelease) {
            throw 'Stable loaded path or full version differs from the acquired package.'
        }
        Write-Output "Stable acquisition selected $StableModuleName $($data.ModuleVersion)."
    }
    else {
        $parameters = @{ DestinationPath = $root }
        if ($ArtifactPath) {
            $ledger = Get-Content (Join-Path $ArtifactPath 'candidate-ledger.json') -Raw | ConvertFrom-Json
            $parameters.ModuleName = $ledger.ModuleName
            $parameters.RequiredVersion = $ledger.FullVersion
            $parameters.PackagePath = Join-Path $ArtifactPath "$($ledger.ModuleName).zip"
            $parameters.PackageSha256 = $ledger.PackageSha256
        }
        else {
            $parameters.ModuleName = $ModuleName
            $parameters.RequiredVersion = $RequiredVersion
        }
        Install-ModuleCandidate @parameters | ConvertTo-Json
    }
}
finally {
    $env:ATLASSIANPS_CONFIGURATION_ROOT = $savedConfigurationRoot
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
