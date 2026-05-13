function Publish-ModuleRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ApiKey
    )

    $releasePath = Join-Path -Path $BuildOutputPath -ChildPath $ModuleName
    if (-not (Test-Path -LiteralPath $releasePath -PathType Container)) {
        throw "Expected release path '$releasePath' does not exist. Run the Build task before publishing."
    }

    Publish-Module -Path $releasePath -NuGetApiKey $ApiKey -ErrorAction Stop
}
