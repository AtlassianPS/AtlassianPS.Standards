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
        [String]$ReleaseNotes,

        [Parameter()]
        [Switch]$EnforceGreaterThanPublished
    )

    if (-not (Test-Path -LiteralPath $BuiltManifestPath -PathType Leaf)) {
        throw "Module manifest '$BuiltManifestPath' was not found."
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

    # A targeted edit (vs Update-ModuleManifest) keeps the committed source manifest free of
    # reformatting churn. Returns updated text; the parent governs the file write via ShouldProcess.
    function Set-ManifestScalar {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
        [OutputType([String])]
        param(
            [Parameter(Mandatory)]
            [String]$Content,

            [Parameter(Mandatory)]
            [String]$Key,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [String]$Value,

            # Multiline matches a single-quoted literal spanning lines with '' escapes (ReleaseNotes).
            [Switch]$Multiline,

            [Switch]$AllowMissing
        )

        $escapedKey = [Regex]::Escape($Key)
        $valueToken = if ($Multiline) { "'(?:[^']|'')*'" } else { "(?<q>['`"])[^'`"]*\k<q>" }
        # New-ModuleManifest comments optional metadata placeholders. Consume that marker so
        # setting Prerelease or ReleaseNotes turns the placeholder into a real assignment.
        $pattern = "(?<![\w-])(?:#[ \t]*)?(?<assignment>$escapedKey[ \t]*=[ \t]*)$valueToken"

        if (-not [Regex]::IsMatch($Content, $pattern)) {
            if ($AllowMissing) {
                return $Content
            }
            throw "Manifest key '$Key' with a quoted value was not found in '$BuiltManifestPath'."
        }

        $escapedValue = $Value -replace "'", "''"
        $evaluator = {
            param($match)
            '{0}''{1}''' -f $match.Groups['assignment'].Value, $escapedValue
        }.GetNewClosure()

        return [Regex]::Replace($Content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
    }

    $normalizedVersion = ConvertTo-VersionDescriptor -VersionText $VersionToPublish

    if ($PSBoundParameters.ContainsKey('ReleaseNotes') -and [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
        throw 'ReleaseNotes cannot be empty when provided.'
    }

    if ($EnforceGreaterThanPublished) {
        $published = Find-Module -Name $ModuleName -ErrorAction SilentlyContinue
        if ($published) {
            $latestPublished = ConvertTo-VersionDescriptor -VersionText $published.Version.ToString()
            if ((Compare-VersionDescriptor -Left $normalizedVersion -Right $latestPublished) -le 0) {
                throw "Version must be greater than latest published version: $($published.Version)"
            }
        }
    }

    $versionString = "{0}.{1}.{2}" -f $normalizedVersion.Major, $normalizedVersion.Minor, $normalizedVersion.Patch
    $prereleaseValue = if ($normalizedVersion.PreReleaseLabel) { $normalizedVersion.PreReleaseLabel } else { '' }

    if ($PSCmdlet.ShouldProcess($BuiltManifestPath, "Set module version to $versionString")) {
        $content = [System.IO.File]::ReadAllText($BuiltManifestPath)

        $content = Set-ManifestScalar -Content $content -Key 'ModuleVersion' -Value $versionString
        # Prerelease may be absent in minimal manifests; only required when setting a label.
        $content = Set-ManifestScalar -Content $content -Key 'Prerelease' -Value $prereleaseValue -AllowMissing:([string]::IsNullOrEmpty($prereleaseValue))
        if ($PSBoundParameters.ContainsKey('ReleaseNotes')) {
            $content = Set-ManifestScalar -Content $content -Key 'ReleaseNotes' -Value $ReleaseNotes -Multiline
        }

        $normalizedContent = $content -replace "`r`n", "`n" -replace "`r", "`n"
        if ($normalizedContent.Length -gt 0 -and -not $normalizedContent.EndsWith("`n")) {
            $normalizedContent += "`n"
        }

        $normalizedContent = $normalizedContent -replace "`n", "`r`n"
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($BuiltManifestPath, $normalizedContent, $utf8Bom)
    }

    return $versionString
}
