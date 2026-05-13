function Write-BuildInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        [String]$VersionToPublish,

        [Parameter()]
        [PSObject]$BuildInfo
    )

    if (-not $BuildInfo) {
        $BuildInfo = Get-BuildEnvironmentInfo -VersionToPublish $VersionToPublish
    }

    $writer = if (Get-Command -Name Write-Build -ErrorAction SilentlyContinue) {
        {
            param([String]$Message)
            Write-Build Gray $Message
        }
    }
    else {
        {
            param([String]$Message)
            Write-Output $Message
        }
    }

    & $writer ''
    & $writer ('BHBuildSystem:              {0}' -f $BuildInfo.BuildSystem)
    & $writer '-------------------------------------------------------'
    & $writer ('BHProjectName:              {0}' -f $BuildInfo.ProjectName)
    & $writer ('BHProjectPath:              {0}' -f $BuildInfo.ProjectPath)
    & $writer ('BHModulePath:               {0}' -f $BuildInfo.ModulePath)
    & $writer ('BHPSModuleManifest:         {0}' -f $BuildInfo.ModuleManifest)
    & $writer ('BHBuildOutput:              {0}' -f $BuildInfo.BuildOutputPath)
    & $writer ('builtManifestPath:          {0}' -f $BuildInfo.BuiltManifestPath)
    & $writer '-------------------------------------------------------'
    & $writer ('BHBranchName:               {0}' -f $BuildInfo.BranchName)
    & $writer ('BHCommitHash:               {0}' -f $BuildInfo.CommitHash)
    & $writer ('BHCommitMessage:            {0}' -f $BuildInfo.CommitMessage)
    & $writer ('BHBuildNumber:              {0}' -f $BuildInfo.BuildNumber)
    & $writer ('VersionToPublish:           {0}' -f $BuildInfo.VersionToPublish)
    & $writer '-------------------------------------------------------'
    & $writer ('PowerShell version:         {0}' -f $PSVersionTable.PSVersion.ToString())
    & $writer ('OS:                         {0}' -f $BuildInfo.OS)
    & $writer ('OS Version:                 {0}' -f $BuildInfo.OSVersion)
    & $writer ''
}
