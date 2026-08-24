function Invoke-Lint {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath = $env:BHProjectPath,

        [Parameter()]
        [String]$ModulePath = $env:BHModulePath,

        [Parameter()]
        [String]$BuildScriptPath,

        [Parameter()]
        [String]$StyleTestPath,

        [Parameter()]
        [String]$AnalyzerSettingsPath,

        [Parameter()]
        [String[]]$AnalyzerPaths,

        [Parameter()]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$PesterVerbosity = 'Normal',

        [Parameter()]
        [Version]$MinimumPesterVersion = [Version]'5.9.0',

        [Parameter()]
        [ValidateSet('Error', 'Warning', 'Information', 'ParseError')]
        [String[]]$Severity = @('Error', 'Warning'),

        [Parameter()]
        [Switch]$SkipStyleTests,

        [Parameter()]
        [Switch]$SkipScriptAnalyzer,

        [Parameter()]
        [Version]$MaximumPesterVersion = [Version]'5.9.999'
    )

    if (-not $ProjectPath) {
        throw 'ProjectPath is required. Provide -ProjectPath or set $env:BHProjectPath.'
    }

    $projectPathResolved = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
    $failures = [System.Collections.Generic.List[String]]::new()
    $styleFailures = 0
    $analyzerIssueCount = 0
    $isGitHubActions = [bool]$env:GITHUB_ACTIONS
    $writeLintMessage = {
        param(
            [Parameter(Mandatory)]
            [String]$Color,

            [Parameter(Mandatory)]
            [String]$Message
        )

        if (Get-Command -Name Write-Build -ErrorAction SilentlyContinue) {
            Write-Build $Color $Message
            return
        }

        Write-Output $Message
    }
    $getProjectRelativePath = {
        param(
            [Parameter(Mandatory)]
            [String]$BasePath,

            [Parameter(Mandatory)]
            [String]$TargetPath
        )

        $getRelativePathMethod = [System.IO.Path].GetMethod('GetRelativePath', [Type[]]@([String], [String]))
        if ($getRelativePathMethod) {
            return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath)
        }

        if ($TargetPath.StartsWith($BasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $TargetPath.Substring($BasePath.Length).TrimStart('\', '/')
        }

        return $TargetPath
    }
    function Write-LocalWorkflowCommand {
        [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSAvoidUsingWriteHost', '',
            Justification = 'GitHub Actions workflow commands must reach stdout; Write-Output is captured by Invoke-Build pipelines.'
        )]
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String]$Command
        )

        Write-Host $Command
    }

    if (-not $BuildScriptPath -and $env:BHProjectName) {
        $BuildScriptPath = Join-Path -Path $projectPathResolved -ChildPath "$($env:BHProjectName).build.ps1"
    }

    if (-not $StyleTestPath) {
        $StyleTestPath = Join-Path -Path $projectPathResolved -ChildPath 'Tests/Style.Tests.ps1'
    }

    if (-not $AnalyzerSettingsPath) {
        $moduleBase = $ExecutionContext.SessionState.Module.ModuleBase
        if (-not $moduleBase) {
            throw 'Unable to resolve AtlassianPS.Standards module base path.'
        }

        $AnalyzerSettingsPath = Join-Path -Path $moduleBase -ChildPath 'PSScriptAnalyzerSettings.psd1'
    }

    if (-not $AnalyzerPaths) {
        $AnalyzerPaths = @(
            $ModulePath
            (Join-Path -Path $projectPathResolved -ChildPath 'Tests')
            (Join-Path -Path $projectPathResolved -ChildPath 'Tools')
            $BuildScriptPath
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    }

    if (-not (Test-Path -LiteralPath $AnalyzerSettingsPath -PathType Leaf)) {
        throw "Analyzer settings file was not found at '$AnalyzerSettingsPath'."
    }

    if ($AnalyzerPaths.Count -eq 0 -and -not $SkipScriptAnalyzer) {
        throw 'No analyzer paths were discovered. Provide -AnalyzerPaths or set build environment paths.'
    }

    if (-not $SkipStyleTests) {
        if (Test-Path -LiteralPath $StyleTestPath -PathType Leaf) {
            & $writeLintMessage -Color Gray -Message 'Running style tests...'
            $pesterVersion = Get-Module -Name 'Pester' -ListAvailable |
                Sort-Object -Property Version -Descending |
                Where-Object {
                    $_.Version -ge $MinimumPesterVersion -and
                    $_.Version -le $MaximumPesterVersion
                } |
                Select-Object -First 1 -ExpandProperty Version
            if (-not $pesterVersion) {
                throw "Pester version between $MinimumPesterVersion and $MaximumPesterVersion is required, but no installed version satisfies that range."
            }

            $loadedPester = Get-Module -Name 'Pester' |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1
            if ((-not $loadedPester) -or ($loadedPester.Version -ne $pesterVersion)) {
                if ($loadedPester) {
                    Get-Module -Name 'Pester' | Remove-Module -Force -ErrorAction SilentlyContinue
                }
                Import-Module -Name 'Pester' -RequiredVersion $pesterVersion -ErrorAction Stop
            }

            $pesterConfigHash = @{
                Run    = @{
                    PassThru = $true
                    Path     = $StyleTestPath
                }
                Output = @{
                    Verbosity = $PesterVerbosity
                }
            }
            $pesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash
            $testResults = Invoke-Pester -Configuration $pesterConfig

            $styleFailures = [int]$testResults.FailedCount
            if ($styleFailures -gt 0) {
                $failures.Add("$styleFailures style test(s) failed.")
            }
            else {
                & $writeLintMessage -Color Green -Message 'Style tests: passed.'
            }
        }
        else {
            & $writeLintMessage -Color Yellow -Message "Style tests skipped because '$StyleTestPath' was not found."
        }
    }

    if (-not $SkipScriptAnalyzer) {
        & $writeLintMessage -Color Gray -Message 'Running PSScriptAnalyzer...'

        $analyzerParams = @{
            Settings = $AnalyzerSettingsPath
            Severity = $Severity
            Recurse  = $true
        }
        $results = @(
            foreach ($path in $AnalyzerPaths) {
                Invoke-ScriptAnalyzer -Path $path @analyzerParams
            }
        )

        foreach ($result in $results) {
            $color = if ($result.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
            $location = if ($result.ScriptName) { $result.ScriptName } else { '<unknown>' }
            & $writeLintMessage -Color $color -Message "[$($result.Severity)] ${location}:$($result.Line) - $($result.RuleName): $($result.Message)"

            if ($isGitHubActions -and $result.ScriptPath) {
                $level = if ($result.Severity -eq 'Error') { 'error' } else { 'warning' }
                $relativePath = & $getProjectRelativePath -BasePath $projectPathResolved -TargetPath $result.ScriptPath
                $message = ($result.Message -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')
                Write-LocalWorkflowCommand -Command "::${level} file=$relativePath,line=$($result.Line),col=$($result.Column),title=$($result.RuleName)::$message"
            }
        }

        $analyzerIssueCount = @($results).Count
        if ($analyzerIssueCount -gt 0) {
            $failures.Add("$analyzerIssueCount PSScriptAnalyzer issue(s) found.")
        }
        else {
            & $writeLintMessage -Color Green -Message 'PSScriptAnalyzer: no issues found.'
        }
    }

    if ($failures.Count -gt 0) {
        throw ("Lint failed:`n  - " + ($failures -join "`n  - "))
    }

    return [PSCustomObject]@{
        StyleFailedCount   = $styleFailures
        AnalyzerIssueCount = $analyzerIssueCount
        AnalyzerPathCount  = $AnalyzerPaths.Count
    }
}
