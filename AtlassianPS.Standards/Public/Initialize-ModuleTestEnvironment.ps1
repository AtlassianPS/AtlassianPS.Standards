function Initialize-ModuleTestEnvironment {
    <#
    .SYNOPSIS
        Resolves and imports a module under test for Pester.

    .DESCRIPTION
        Resolves the source or release manifest for a module under test, removes any
        currently loaded copy of that module, then imports the manifest with -Force.
        Product-specific fixtures remain in the repository test helpers.

    .PARAMETER ModuleName
        Name of the module under test.

    .PARAMETER StartPath
        Directory or file path to start repository-root discovery from. Defaults to the current directory.

    .PARAMETER MarkerFileName
        Repository-root marker file name. Defaults to CODEOWNERS.

    .PARAMETER Global
        Imports the module into the global session state. Use this when Pester tests need the module visible outside the helper scope.

    .OUTPUTS
        String. The manifest path used to import the module under test.

    .EXAMPLE
        BeforeAll {
            Import-Module AtlassianPS.Standards
            $script:moduleToTest = Initialize-AtlassianPSModuleTestEnvironment -ModuleName 'JiraPS' -StartPath $PSScriptRoot
        }

        Imports JiraPS for a Pester file and returns the manifest path used for the import.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$StartPath = (Get-Location).Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$MarkerFileName = 'CODEOWNERS',

        [Parameter()]
        [Switch]$Global
    )

    $manifestPath = Resolve-ModuleSource -ModuleName $ModuleName -StartPath $StartPath -MarkerFileName $MarkerFileName
    Get-Module |
        Where-Object { $_.RequiredModules.Name -eq $ModuleName } |
        Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue

    Import-Module -Name $manifestPath -Force -Global:$Global -ErrorAction Stop

    return $manifestPath
}
