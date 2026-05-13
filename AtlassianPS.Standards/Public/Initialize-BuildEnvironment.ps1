function Initialize-BuildEnvironment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputFolder = 'Release',

        [Parameter()]
        [String]$VersionToPublish,

        [Parameter()]
        [Switch]$ResetBuildEnvironmentVariables
    )

    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath

    if ($ResetBuildEnvironmentVariables) {
        Remove-Item -Path env:\BH* -ErrorAction SilentlyContinue
    }

    $env:BHProjectName = $ProjectName
    $env:BHProjectPath = $resolvedProjectPath
    $env:BHModulePath = Join-Path -Path $env:BHProjectPath -ChildPath $env:BHProjectName
    $env:BHPSModulePath = $env:BHModulePath
    $env:BHPSModuleManifest = Join-Path -Path $env:BHModulePath -ChildPath "$($env:BHProjectName).psd1"
    $env:BHBuildOutput = Join-Path -Path $env:BHProjectPath -ChildPath $BuildOutputFolder

    $metadata = Get-BuildEnvironmentMetadata -ProjectPath $env:BHProjectPath
    $env:BHBuildSystem = $metadata.BuildSystem
    $env:BHBranchName = $metadata.BranchName
    $env:BHCommitHash = $metadata.CommitHash
    $env:BHBuildNumber = $metadata.BuildNumber
    $env:BHCommitMessage = $metadata.CommitMessage

    return Get-BuildEnvironmentInfo -VersionToPublish $VersionToPublish
}
