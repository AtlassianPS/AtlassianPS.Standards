function Set-ModuleManifestVersion {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuiltManifestPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$VersionToPublish
    )

    if (-not (Get-Command -Name 'Metadata\Update-Metadata' -ErrorAction SilentlyContinue)) {
        throw "Metadata\Update-Metadata is not available. Ensure the required metadata tooling is installed."
    }

    if (-not (Test-Path -LiteralPath $BuiltManifestPath -PathType Leaf)) {
        throw "Built module manifest '$BuiltManifestPath' was not found."
    }

    [System.Management.Automation.SemanticVersion]$normalizedVersion = $VersionToPublish.TrimStart('v')

    $published = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
    if ($published) {
        [System.Management.Automation.SemanticVersion]$latestPublished = $published.Version
        if ($normalizedVersion -le $latestPublished) {
            throw "Version must be greater than latest published version: $latestPublished"
        }
    }

    $versionString = "{0}.{1}.{2}" -f $normalizedVersion.Major, $normalizedVersion.Minor, $normalizedVersion.Patch
    if ($PSCmdlet.ShouldProcess($BuiltManifestPath, "Set module version to $versionString")) {
        Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'ModuleVersion' -Value $versionString

        if ($normalizedVersion.PreReleaseLabel) {
            Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'Prerelease' -Value $normalizedVersion.PreReleaseLabel
        }
        else {
            Metadata\Update-Metadata -Path $BuiltManifestPath -PropertyName 'Prerelease' -Value ''
        }
    }

    return $versionString
}
