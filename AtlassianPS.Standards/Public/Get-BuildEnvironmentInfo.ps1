function Get-BuildEnvironmentInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [String]$VersionToPublish
    )

    $platformInfo = Get-HostPlatformInfo
    $normalizedVersionToPublish = if ($VersionToPublish) { $VersionToPublish.TrimStart('v') } else { $null }
    $builtManifestPath = if ($env:BHBuildOutput -and $env:BHProjectName) {
        Join-Path -Path (Join-Path -Path $env:BHBuildOutput -ChildPath $env:BHProjectName) -ChildPath "$($env:BHProjectName).psd1"
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        BuildSystem       = $env:BHBuildSystem
        ProjectName       = $env:BHProjectName
        ProjectPath       = $env:BHProjectPath
        ModulePath        = $env:BHModulePath
        ModuleManifest    = $env:BHPSModuleManifest
        BuildOutputPath   = $env:BHBuildOutput
        BuiltManifestPath = $builtManifestPath
        BranchName        = $env:BHBranchName
        CommitHash        = $env:BHCommitHash
        CommitMessage     = $env:BHCommitMessage
        BuildNumber       = $env:BHBuildNumber
        VersionToPublish  = $normalizedVersionToPublish
        OS                = $platformInfo.OS
        OSVersion         = $platformInfo.OSVersion
    }
}
