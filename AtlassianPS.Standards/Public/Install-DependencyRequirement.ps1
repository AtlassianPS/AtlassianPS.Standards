<#
.SYNOPSIS
Installs required module dependencies for AtlassianPS standards workflows.

.DESCRIPTION
Reads dependency requirements from the build requirements data file and the
module manifest, normalizes entries to ModuleName/RequiredVersion pairs, and
installs any missing versions from PSGallery for the current user.

.PARAMETER BuildRequirementsPath
Path to the build requirements data file (for example, Tools/build.requirements.psd1).

.PARAMETER ManifestPath
Path to the module manifest file containing RequiredModules entries.

.OUTPUTS
PSCustomObject

.EXAMPLE
Install-DependencyRequirement -BuildRequirementsPath './Tools/build.requirements.psd1' -ManifestPath './AtlassianPS.Standards/AtlassianPS.Standards.psd1'
#>
function Install-DependencyRequirement {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildRequirementsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ManifestPath,

        [Parameter()]
        [Object[]]$CandidateRequirement = @(),

        [Parameter()]
        [String]$CandidateRoot = (Join-Path ([IO.Path]::GetTempPath()) 'AtlassianPS-Candidates')
    )

    function Get-RequirementValue {
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

    function ConvertTo-ModuleRequirement {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [Object]$Requirement,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]$SourcePath
        )

        if ($Requirement -is [string]) {
            throw "Invalid requirement entry '$Requirement' in '$SourcePath'. Expected ModuleName with RequiredVersion or ModuleVersion."
        }

        $moduleName = Get-RequirementValue -Requirement $Requirement -Name 'ModuleName'
        if (-not $moduleName) {
            throw "Invalid requirement entry in '$SourcePath': missing ModuleName."
        }

        $requiredVersion = Get-RequirementValue -Requirement $Requirement -Name 'RequiredVersion'
        $minimumVersion = Get-RequirementValue -Requirement $Requirement -Name 'ModuleVersion'
        $maximumVersion = Get-RequirementValue -Requirement $Requirement -Name 'MaximumVersion'
        if ($maximumVersion -match '^(?<prefix>\d+(?:\.\d+){0,2})\.\*$') {
            $maximumParts = @($Matches.prefix.Split('.'))
            while ($maximumParts.Count -lt 4) { $maximumParts += [Int]::MaxValue.ToString() }
            $maximumVersion = $maximumParts -join '.'
        }
        if (-not $requiredVersion -and -not $minimumVersion) {
            throw "Module requirement '$moduleName' in '$SourcePath' must specify RequiredVersion or ModuleVersion."
        }

        return [PSCustomObject]@{
            ModuleName      = $moduleName
            RequiredVersion = $requiredVersion
            MinimumVersion  = $minimumVersion
            MaximumVersion  = $maximumVersion
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

    $resolvedBuildRequirementsPath = (Resolve-Path -LiteralPath $BuildRequirementsPath).ProviderPath
    $resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath).ProviderPath

    $buildRequirementsData = Get-DataFileExpressionValue -Path $resolvedBuildRequirementsPath
    if ($buildRequirementsData.ExpressionAst -is [System.Management.Automation.Language.HashtableAst]) {
        throw "Unsupported build requirements format in '$resolvedBuildRequirementsPath'. Use array entries with ModuleName and RequiredVersion."
    }
    if (
        $buildRequirementsData.ExpressionAst -isnot [System.Management.Automation.Language.ArrayExpressionAst] -and
        $buildRequirementsData.ExpressionAst -isnot [System.Management.Automation.Language.ArrayLiteralAst]
    ) {
        throw "Unsupported build requirements format in '$resolvedBuildRequirementsPath'. Use array entries with ModuleName and RequiredVersion."
    }

    $buildRequirementEntries = if ($buildRequirementsData.Value -is [System.Collections.IDictionary]) { @($buildRequirementsData.Value) } else { @($buildRequirementsData.Value) }

    $manifestData = Get-DataFileExpressionValue -Path $resolvedManifestPath
    if ($manifestData.Value -isnot [System.Collections.IDictionary]) {
        throw "Module manifest '$resolvedManifestPath' must resolve to a hashtable."
    }
    $requirementsByName = @{}

    foreach ($requirementEntry in $buildRequirementEntries) {
        $requirement = ConvertTo-ModuleRequirement -Requirement $requirementEntry -SourcePath $resolvedBuildRequirementsPath
        $requirementsByName[$requirement.ModuleName.ToLowerInvariant()] = $requirement
    }

    foreach ($requirementEntry in @($manifestData.Value['RequiredModules'])) {
        $requirement = ConvertTo-ModuleRequirement -Requirement $requirementEntry -SourcePath $resolvedManifestPath
        $requirementsByName[$requirement.ModuleName.ToLowerInvariant()] = $requirement
    }

    $requirements = @($requirementsByName.Values | Sort-Object -Property ModuleName)
    $candidatesByName = @{}
    foreach ($candidate in $CandidateRequirement) {
        $key = ([String]$candidate.ModuleName).ToLowerInvariant()
        if (-not $requirementsByName.ContainsKey($key) -or $candidatesByName.ContainsKey($key)) {
            throw "Candidate '$key' must identify one declared dependency."
        }
        if ([String]$candidate.RequiredVersion -notmatch '^\d+\.\d+\.\d+-(alpha|beta)\d{4}$') {
            throw "Candidate '$key' requires an exact alpha or beta version."
        }
        $numericVersion = [Version]($candidate.RequiredVersion.Split('-')[0])
        $bounds = $requirementsByName[$key]
        if (($bounds.RequiredVersion -and $numericVersion -ne [Version]$bounds.RequiredVersion) -or
            ($bounds.MinimumVersion -and $numericVersion -lt [Version]$bounds.MinimumVersion) -or
            ($bounds.MaximumVersion -and $numericVersion -gt [Version]$bounds.MaximumVersion)) {
            throw "Candidate '$key' falls outside the declared numeric dependency bounds."
        }
        $candidatesByName[$key] = $candidate
    }

    if (-not (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default
    }

    $installedCount = 0
    $alreadyPresentCount = 0
    $orderedRequirements = $requirements | Sort-Object @{ Expression = { $candidatesByName.ContainsKey($_.ModuleName.ToLowerInvariant()) } }, ModuleName
    foreach ($requirement in $orderedRequirements) {
        $moduleName = $requirement.ModuleName
        $requiredVersion = [string]$requirement.RequiredVersion
        $candidate = $candidatesByName[$moduleName.ToLowerInvariant()]
        if ($candidate) {
            if ($PSCmdlet.ShouldProcess("$moduleName $($candidate.RequiredVersion)", 'Provision exact candidate dependency')) {
                $candidateParameters = @{
                    ModuleName      = $moduleName
                    RequiredVersion = $candidate.RequiredVersion
                    DestinationPath = $CandidateRoot
                }
                if ($candidate.PackagePath) {
                    $candidateParameters.PackagePath = $candidate.PackagePath
                    $candidateParameters.PackageSha256 = $candidate.PackageSha256
                }
                $null = Install-ModuleCandidate @candidateParameters -ErrorAction Stop
                $installedCount++
            }
            continue
        }

        $installedModule = Get-Module -Name $moduleName -ListAvailable |
            Where-Object {
                -not $_.PrivateData.PSData.Prerelease -and
                (-not $requiredVersion -or $_.Version -eq [Version]$requiredVersion) -and
                (-not $requirement.MinimumVersion -or $_.Version -ge [Version]$requirement.MinimumVersion) -and
                (-not $requirement.MaximumVersion -or $_.Version -le [Version]$requirement.MaximumVersion)
            } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($installedModule) {
            Write-Verbose "Dependency '$moduleName' $requiredVersion already installed."
            $alreadyPresentCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess("$moduleName $requiredVersion", 'Install module dependency')) {
            Write-Verbose "Installing dependency '$moduleName' $requiredVersion."
            $installParameters = @{
                Name               = $moduleName
                Scope              = 'CurrentUser'
                Repository         = 'PSGallery'
                SkipPublisherCheck = $true
                AllowClobber       = $true
                Force              = $true
                ErrorAction        = 'Stop'
            }
            if ($requiredVersion) { $installParameters.RequiredVersion = $requiredVersion }
            else {
                $installParameters.MinimumVersion = $requirement.MinimumVersion
                if ($requirement.MaximumVersion) { $installParameters.MaximumVersion = $requirement.MaximumVersion }
            }
            Install-Module @installParameters
            $installedCount++
        }
    }

    return [PSCustomObject]@{
        TotalRequirementCount = $requirements.Count
        InstalledCount        = $installedCount
        AlreadyPresentCount   = $alreadyPresentCount
    }
}
