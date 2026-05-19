function Update-DependencyReference {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$BuildRequirementsPath = (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Tools/build.requirements.psd1'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ManifestPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AtlassianPS.Standards.psd1'),

        [Parameter()]
        [Switch]$SkipBuildRequirement,

        [Parameter()]
        [Switch]$SkipManifestRequirement,

        [Parameter()]
        [Switch]$AllowLookupFailure
    )

    function Get-FileTextState {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$Path
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Required file was not found: '$Path'."
        }

        $resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
        $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
            $text = $text.Substring(1)
        }

        $newLine = if ($text -match "`r`n") { "`r`n" } elseif ($text -match "`n") { "`n" } else { [System.Environment]::NewLine }

        return [PSCustomObject]@{
            Path    = $resolvedPath
            Text    = $text
            HasBom  = $hasBom
            NewLine = $newLine
        }
    }

    function Set-FileTextState {
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [PSCustomObject]$State,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [String]$Text
        )

        $normalizedText = $Text -replace "`r?`n", $State.NewLine
        if (-not $normalizedText.EndsWith($State.NewLine)) {
            $normalizedText += $State.NewLine
        }

        if ($PSCmdlet.ShouldProcess($State.Path, 'Write updated dependency content')) {
            $encoding = [System.Text.UTF8Encoding]::new($State.HasBom)
            [System.IO.File]::WriteAllText($State.Path, $normalizedText, $encoding)
        }
    }

    function Get-DataFileExpressionValue {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$Path
        )

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw "Unable to parse data file '$Path': $($parseErrors[0].Message)"
        }

        if (-not $ast.EndBlock -or $ast.EndBlock.Statements.Count -eq 0) {
            throw "Data file '$Path' does not contain a supported data expression."
        }

        $statement = $ast.EndBlock.Statements[0]
        if ($statement -isnot [System.Management.Automation.Language.PipelineAst]) {
            throw "Data file '$Path' does not contain a supported data expression."
        }

        $pipelineElement = $statement.PipelineElements[0]
        if ($pipelineElement -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
            throw "Data file '$Path' does not contain a supported data expression."
        }

        return [PSCustomObject]@{
            ExpressionAst = $pipelineElement.Expression
            Value         = $pipelineElement.Expression.SafeGetValue()
        }
    }

    function Get-RequirementPropertyValue {
        [CmdletBinding()]
        [OutputType([String])]
        param(
            [Parameter(Mandatory)]
            [Object]$Requirement,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$Name
        )

        if ($Requirement -is [System.Collections.IDictionary]) {
            if ($Requirement.Contains($Name)) {
                return [string]$Requirement[$Name]
            }

            return $null
        }

        if ($Requirement.PSObject.Properties.Name -contains $Name) {
            return [string]$Requirement.$Name
        }

        return $null
    }

    function ConvertTo-BuildRequirementsContent {
        [CmdletBinding()]
        [OutputType([String])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [Object[]]$Requirements,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$NewLine
        )

        $lines = [System.Collections.Generic.List[String]]::new()
        $lines.Add('@(')
        foreach ($requirement in $Requirements) {
            $moduleName = ([string]$requirement.ModuleName).Replace('"', '\"')
            $requiredVersion = ([string]$requirement.RequiredVersion).Replace('"', '\"')
            $lines.Add("    @{ ModuleName = ""$moduleName""; RequiredVersion = ""$requiredVersion"" }")
        }
        $lines.Add(')')

        return ($lines -join $NewLine)
    }

    function Get-ModuleVersionString {
        [CmdletBinding()]
        [OutputType([String])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$ModuleName,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Collections.IDictionary]$Cache,

            [Parameter()]
            [Switch]$AllowLookupFailure
        )

        $cacheKey = $ModuleName.ToLowerInvariant()
        if ($Cache.Contains($cacheKey)) {
            return $Cache[$cacheKey]
        }

        $latestVersion = $null
        try {
            $latest = Find-Module -Name $ModuleName -Repository 'PSGallery' -ErrorAction Stop
            if ($latest -and $latest.Version) {
                $latestVersion = [string]$latest.Version
            }
        }
        catch {
            if ($AllowLookupFailure) {
                Write-Warning "Unable to resolve latest version for module '$ModuleName'. Keeping existing version."
            }
            else {
                throw "Unable to resolve latest version for module '$ModuleName'. Use -AllowLookupFailure to continue without updating that module. Original error: $($_.Exception.Message)"
            }
        }

        $Cache[$cacheKey] = $latestVersion
        return $latestVersion
    }

    function Test-IsVersionUpgrade {
        [CmdletBinding()]
        [OutputType([Boolean])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$CurrentVersion,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$LatestVersion
        )

        if ($CurrentVersion -eq $LatestVersion) {
            return $false
        }

        $currentVersionObject = $null
        $latestVersionObject = $null
        $currentParsed = [System.Version]::TryParse($CurrentVersion, [ref]$currentVersionObject)
        $latestParsed = [System.Version]::TryParse($LatestVersion, [ref]$latestVersionObject)

        if ($currentParsed -and $latestParsed) {
            return $latestVersionObject -gt $currentVersionObject
        }

        return $true
    }

    function Get-DependencyUpdateRecord {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$FilePath,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$ModuleName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$CurrentVersion,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$LatestVersion
        )

        return [PSCustomObject]@{
            FilePath       = $FilePath
            ModuleName     = $ModuleName
            CurrentVersion = $CurrentVersion
            LatestVersion  = $LatestVersion
        }
    }

    function Get-ManifestRequirementVersionContent {
        [CmdletBinding()]
        [OutputType([String])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$Content,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$ModuleName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$VersionProperty,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$LatestVersion
        )

        $escapedModuleName = [System.Text.RegularExpressions.Regex]::Escape($ModuleName)
        $moduleNamePattern = [System.Text.RegularExpressions.Regex]::new("ModuleName\s*=\s*['""]$escapedModuleName['""]")
        $moduleNameMatch = $moduleNamePattern.Match($Content)
        if (-not $moduleNameMatch.Success) {
            return $Content
        }

        $blockStartIndex = $Content.LastIndexOf('@{', $moduleNameMatch.Index, $moduleNameMatch.Index + 1)
        if ($blockStartIndex -lt 0) {
            return $Content
        }

        $blockEndIndex = $Content.IndexOf('}', $moduleNameMatch.Index)
        if ($blockEndIndex -lt 0) {
            return $Content
        }

        $blockLength = ($blockEndIndex - $blockStartIndex) + 1
        $blockContent = $Content.Substring($blockStartIndex, $blockLength)
        $replacementValue = '${head}' + $LatestVersion + '${tail}'
        $updatedBlockContent = [System.Text.RegularExpressions.Regex]::Replace(
            $blockContent,
            "(?<head>$VersionProperty\s*=\s*['""])[^'""]+(?<tail>['""])",
            $replacementValue,
            1
        )

        if ($updatedBlockContent -eq $blockContent) {
            return $Content
        }

        return $Content.Remove($blockStartIndex, $blockLength).Insert($blockStartIndex, $updatedBlockContent)
    }

    $versionCache = @{}
    $dependencyUpdates = [System.Collections.Generic.List[Object]]::new()
    $buildRequirementUpdated = $false
    $manifestUpdated = $false

    if (-not $SkipBuildRequirement) {
        $buildState = Get-FileTextState -Path $BuildRequirementsPath
        $buildData = Get-DataFileExpressionValue -Path $buildState.Path

        if ($buildData.ExpressionAst -is [System.Management.Automation.Language.HashtableAst]) {
            throw "Unsupported build requirements format in '$($buildState.Path)'. PSDepend hashtable format is no longer supported; use array entries with ModuleName/RequiredVersion."
        }
        if (
            $buildData.ExpressionAst -isnot [System.Management.Automation.Language.ArrayExpressionAst] -and
            $buildData.ExpressionAst -isnot [System.Management.Automation.Language.ArrayLiteralAst]
        ) {
            throw "Unsupported build requirements format in '$($buildState.Path)'. Use array entries with ModuleName and RequiredVersion."
        }

        $buildRequirementEntries = if ($buildData.Value -is [System.Collections.IDictionary]) {
            @($buildData.Value)
        }
        else {
            @($buildData.Value)
        }

        $updatedRequirements = [System.Collections.Generic.List[Object]]::new()
        foreach ($requirementEntry in $buildRequirementEntries) {
            if ($requirementEntry -is [string]) {
                throw "Invalid requirement entry '$requirementEntry' in '$($buildState.Path)'. Expected ModuleName with RequiredVersion."
            }

            $moduleName = Get-RequirementPropertyValue -Requirement $requirementEntry -Name 'ModuleName'
            if (-not $moduleName) {
                throw "Invalid requirement entry in '$($buildState.Path)': missing ModuleName."
            }

            $currentVersion = Get-RequirementPropertyValue -Requirement $requirementEntry -Name 'RequiredVersion'
            if (-not $currentVersion) {
                $currentVersion = Get-RequirementPropertyValue -Requirement $requirementEntry -Name 'ModuleVersion'
            }
            if (-not $currentVersion) {
                throw "Module requirement '$moduleName' in '$($buildState.Path)' must specify RequiredVersion or ModuleVersion."
            }

            $updatedVersion = $currentVersion
            $latestVersion = Get-ModuleVersionString -ModuleName $moduleName -Cache $versionCache -AllowLookupFailure:$AllowLookupFailure
            if ($latestVersion -and (Test-IsVersionUpgrade -CurrentVersion $currentVersion -LatestVersion $latestVersion)) {
                $updatedVersion = $latestVersion
                $buildRequirementUpdated = $true
                $dependencyUpdates.Add(
                    (Get-DependencyUpdateRecord `
                        -FilePath $buildState.Path `
                        -ModuleName $moduleName `
                        -CurrentVersion $currentVersion `
                        -LatestVersion $latestVersion)
                )
            }

            $updatedRequirements.Add([PSCustomObject]@{
                    ModuleName      = $moduleName
                    RequiredVersion = $updatedVersion
                })
        }

        if ($buildRequirementUpdated) {
            $updatedBuildContent = ConvertTo-BuildRequirementsContent -Requirements @($updatedRequirements) -NewLine $buildState.NewLine
            if ($PSCmdlet.ShouldProcess($buildState.Path, 'Update dependency versions in build requirements')) {
                Set-FileTextState -State $buildState -Text $updatedBuildContent
            }
        }
    }

    if (-not $SkipManifestRequirement) {
        $manifestState = Get-FileTextState -Path $ManifestPath
        $manifestContent = $manifestState.Text
        $updatedManifestContent = $manifestContent
        $manifestData = Get-DataFileExpressionValue -Path $manifestState.Path
        if ($manifestData.Value -isnot [System.Collections.IDictionary]) {
            throw "Module manifest '$($manifestState.Path)' must resolve to a hashtable."
        }

        $requiredModules = @($manifestData.Value['RequiredModules'])
        foreach ($requiredModule in $requiredModules) {
            $moduleName = Get-RequirementPropertyValue -Requirement $requiredModule -Name 'ModuleName'
            if (-not $moduleName) {
                continue
            }

            $versionProperty = if (Get-RequirementPropertyValue -Requirement $requiredModule -Name 'RequiredVersion') {
                'RequiredVersion'
            }
            elseif (Get-RequirementPropertyValue -Requirement $requiredModule -Name 'ModuleVersion') {
                'ModuleVersion'
            }
            else {
                $null
            }

            if (-not $versionProperty) {
                continue
            }

            $currentVersion = Get-RequirementPropertyValue -Requirement $requiredModule -Name $versionProperty
            if (-not $currentVersion -or $currentVersion -eq 'latest') {
                continue
            }

            $latestVersion = Get-ModuleVersionString -ModuleName $moduleName -Cache $versionCache -AllowLookupFailure:$AllowLookupFailure
            if (-not $latestVersion -or -not (Test-IsVersionUpgrade -CurrentVersion $currentVersion -LatestVersion $latestVersion)) {
                continue
            }

            $dependencyUpdates.Add(
                (Get-DependencyUpdateRecord `
                    -FilePath $manifestState.Path `
                    -ModuleName $moduleName `
                    -CurrentVersion $currentVersion `
                    -LatestVersion $latestVersion)
            )

            $updatedManifestContent = Get-ManifestRequirementVersionContent `
                -Content $updatedManifestContent `
                -ModuleName $moduleName `
                -VersionProperty $versionProperty `
                -LatestVersion $latestVersion
        }

        if ($updatedManifestContent -ne $manifestContent) {
            $manifestUpdated = $true
            if ($PSCmdlet.ShouldProcess($manifestState.Path, 'Update dependency versions in module manifest')) {
                Set-FileTextState -State $manifestState -Text $updatedManifestContent
            }
        }
    }

    $uniqueModuleNames = @(
        $dependencyUpdates.ModuleName |
            Sort-Object -Unique
    )

    return [PSCustomObject]@{
        BuildRequirementUpdated = $buildRequirementUpdated
        ManifestUpdated         = $manifestUpdated
        UpdatedModuleCount      = $uniqueModuleNames.Count
        UpdatedModuleName       = $uniqueModuleNames
        UpdateDetail            = @($dependencyUpdates)
    }
}
