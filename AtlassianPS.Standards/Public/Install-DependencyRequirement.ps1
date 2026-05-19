function Install-DependencyRequirement {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildRequirementsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ManifestPath
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
        if (-not $requiredVersion) {
            $requiredVersion = Get-RequirementValue -Requirement $Requirement -Name 'ModuleVersion'
        }
        if (-not $requiredVersion) {
            throw "Module requirement '$moduleName' in '$SourcePath' must specify RequiredVersion or ModuleVersion."
        }

        return [PSCustomObject]@{
            ModuleName      = $moduleName
            RequiredVersion = $requiredVersion
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

    if (-not (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default
    }

    $installedCount = 0
    $alreadyPresentCount = 0
    foreach ($requirement in $requirements) {
        $moduleName = $requirement.ModuleName
        $requiredVersion = [string]$requirement.RequiredVersion

        $installedModule = Get-Module -Name $moduleName -ListAvailable |
            Where-Object { $_.Version.ToString() -eq $requiredVersion } |
            Select-Object -First 1

        if ($installedModule) {
            Write-Verbose "Dependency '$moduleName' $requiredVersion already installed."
            $alreadyPresentCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess("$moduleName $requiredVersion", 'Install module dependency')) {
            Write-Verbose "Installing dependency '$moduleName' $requiredVersion."
            Install-Module -Name $moduleName `
                -RequiredVersion $requiredVersion `
                -Scope CurrentUser `
                -Repository 'PSGallery' `
                -AllowClobber `
                -Force
            $installedCount++
        }
    }

    return [PSCustomObject]@{
        TotalRequirementCount = $requirements.Count
        InstalledCount        = $installedCount
        AlreadyPresentCount   = $alreadyPresentCount
    }
}
