function Invoke-ModulePublishDryRun {
    <#
    .SYNOPSIS
        Creates and validates a release package without publishing it.

    .DESCRIPTION
        Packages the built module directory and validates that the release module,
        manifest, package archive, manifest name, and manifest version are present.
        This is intended for CI build jobs that need to exercise the publish path
        without contacting PowerShell Gallery.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$PackagePath
    )

    if (-not $PackagePath) {
        $PackagePath = New-ModulePackage -BuildOutputPath $BuildOutputPath -ModuleName $ModuleName
    }

    $result = Test-ModulePackage `
        -BuildOutputPath $BuildOutputPath `
        -ModuleName $ModuleName `
        -PackagePath $PackagePath

    return $result
}
