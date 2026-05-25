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
        [String]$VersionToPublish,

        [Parameter()]
        [String]$ReleaseNotes
    )

    if (-not (Test-Path -LiteralPath $BuiltManifestPath -PathType Leaf)) {
        throw "Built module manifest '$BuiltManifestPath' was not found."
    }

    function ConvertTo-VersionDescriptor {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$VersionText
        )

        $trimmedVersion = $VersionText.Trim()
        if ($trimmedVersion -match '^v') {
            $trimmedVersion = $trimmedVersion.Substring(1)
        }

        if ($trimmedVersion -notmatch '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-(?<prerelease>[0-9A-Za-z][0-9A-Za-z\.-]*))?$') {
            throw "Invalid semantic version '$VersionText'. Expected format: <major>.<minor>.<patch>[-prerelease]."
        }

        return [PSCustomObject]@{
            Major           = [int]$matches.major
            Minor           = [int]$matches.minor
            Patch           = [int]$matches.patch
            PreReleaseLabel = $matches.prerelease
            CoreVersion     = [Version]::new([int]$matches.major, [int]$matches.minor, [int]$matches.patch)
        }
    }

    function Compare-VersionDescriptor {
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Left,
            [Parameter(Mandatory)]
            [PSCustomObject]$Right
        )

        $coreComparison = $Left.CoreVersion.CompareTo($Right.CoreVersion)
        if ($coreComparison -ne 0) {
            return $coreComparison
        }

        if ([string]::IsNullOrEmpty($Left.PreReleaseLabel) -and [string]::IsNullOrEmpty($Right.PreReleaseLabel)) {
            return 0
        }

        if ([string]::IsNullOrEmpty($Left.PreReleaseLabel)) {
            return 1
        }

        if ([string]::IsNullOrEmpty($Right.PreReleaseLabel)) {
            return -1
        }

        return [string]::CompareOrdinal($Left.PreReleaseLabel, $Right.PreReleaseLabel)
    }

    $normalizedVersion = ConvertTo-VersionDescriptor -VersionText $VersionToPublish

    if ($PSBoundParameters.ContainsKey('ReleaseNotes') -and [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
        throw 'ReleaseNotes cannot be empty when provided.'
    }

    $published = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
    if ($published) {
        $latestPublished = ConvertTo-VersionDescriptor -VersionText $published.Version.ToString()
        if ((Compare-VersionDescriptor -Left $normalizedVersion -Right $latestPublished) -le 0) {
            throw "Version must be greater than latest published version: $($published.Version)"
        }
    }

    $versionString = "{0}.{1}.{2}" -f $normalizedVersion.Major, $normalizedVersion.Minor, $normalizedVersion.Patch
    if ($PSCmdlet.ShouldProcess($BuiltManifestPath, "Set module version to $versionString")) {
        $parameters = @{
            Path          = $BuiltManifestPath
            ModuleVersion = $versionString
        }

        $parameters.Prerelease = if ($normalizedVersion.PreReleaseLabel) { $normalizedVersion.PreReleaseLabel } else { '' }

        if ($PSBoundParameters.ContainsKey('ReleaseNotes')) {
            $parameters.ReleaseNotes = $ReleaseNotes
        }

        Update-ModuleManifest @parameters
    }

    return $versionString
}
