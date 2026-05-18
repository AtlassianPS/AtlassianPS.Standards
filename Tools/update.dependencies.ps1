#requires -Module PowerShellGet

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$requirementsPath = Join-Path $PSScriptRoot 'build.requirements.psd1'
$setupScriptPath = Join-Path $PSScriptRoot 'setup.ps1'

function Get-LatestModuleVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    try {
        $latest = Find-Module -Name $ModuleName -Repository PSGallery -ErrorAction Stop
        return $latest.Version.ToString()
    }
    catch {
        Write-Warning "Unable to resolve latest version for module '$ModuleName'. Keeping existing version."
        Write-Warning $_
        return $null
    }
}

function Update-DependencyRequirement {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
        Write-Warning "Dependency file '$requirementsPath' not found."
        return
    }

    $content = [System.IO.File]::ReadAllText($requirementsPath)
    $modulePattern = '(?m)^(?<indent>\s*)@\{\s*ModuleName\s*=\s*"(?<name>[^"]+)"\s*;\s*RequiredVersion\s*=\s*"(?<version>[^"]+)"\s*\}\s*$'
    $matches = [System.Text.RegularExpressions.Regex]::Matches($content, $modulePattern)

    if ($matches.Count -eq 0) {
        Write-Warning "No ModuleName/RequiredVersion entries found in '$requirementsPath'."
        return
    }

    $updatedContent = $content
    foreach ($match in $matches) {
        $moduleName = $match.Groups['name'].Value
        $currentVersion = $match.Groups['version'].Value

        Write-Output "Checking for module: $moduleName"
        $latestVersion = Get-LatestModuleVersion -ModuleName $moduleName
        if (-not $latestVersion -or ([version]$latestVersion -le [version]$currentVersion)) {
            continue
        }

        Write-Output "Updating ${moduleName}: v$currentVersion --> $latestVersion"
        $updatedContent = $updatedContent.Replace(
            $match.Value,
            ('{0}@{{ ModuleName = "{1}"; RequiredVersion = "{2}" }}' -f $match.Groups['indent'].Value, $moduleName, $latestVersion)
        )
    }

    $updatedContent = $updatedContent -replace "`r?`n", "`r`n"
    if (-not $updatedContent.EndsWith("`r`n")) {
        $updatedContent += "`r`n"
    }

    if ($updatedContent -ne $content -and $PSCmdlet.ShouldProcess($requirementsPath, 'Update dependency requirements')) {
        [System.IO.File]::WriteAllText($requirementsPath, $updatedContent, [System.Text.UTF8Encoding]::new($true))
    }
}

function Update-PinnedPSScriptAnalyzerSettingsUri {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $settingsFilePath = 'standards/PSScriptAnalyzerSettings.psd1'
    $commitApiUri = "https://api.github.com/repos/AtlassianPS/.github/commits?path=$settingsFilePath&sha=master&per_page=1"

    Write-Output "Checking pinned .github commit for $settingsFilePath"
    try {
        $response = Invoke-RestMethod -Uri $commitApiUri -Method Get -ErrorAction Stop
    }
    catch {
        throw "Unable to query latest commit for shared PSScriptAnalyzer settings. $($_.Exception.Message)"
    }

    if (-not $response -or -not $response[0] -or -not $response[0].sha) {
        throw 'No commit data returned for shared PSScriptAnalyzer settings.'
    }

    $latestCommit = $response[0].sha
    $newUri = "https://raw.githubusercontent.com/AtlassianPS/.github/$latestCommit/$settingsFilePath"
    $setupContent = [System.IO.File]::ReadAllText($setupScriptPath)
    $oldUriPattern = "(?m)^\$psScriptAnalyzerSettingsUri = 'https://raw\.githubusercontent\.com/AtlassianPS/\.github/[^']+/standards/PSScriptAnalyzerSettings\.psd1'$"
    $newUriLine = "`$psScriptAnalyzerSettingsUri = '$newUri'"

    if ($setupContent -notmatch $oldUriPattern) {
        Write-Warning 'Unable to locate pinned PSScriptAnalyzer URI in setup.ps1; skipping.'
        return
    }

    $updatedContent = [System.Text.RegularExpressions.Regex]::Replace(
        $setupContent,
        $oldUriPattern,
        $newUriLine,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
    if ($updatedContent -eq $setupContent) {
        Write-Output 'Pinned PSScriptAnalyzer URI already up to date.'
        return
    }

    if ($PSCmdlet.ShouldProcess($setupScriptPath, 'Update pinned PSScriptAnalyzer settings URI')) {
        $updatedContent = $updatedContent -replace "`r?`n", "`r`n"
        [System.IO.File]::WriteAllText($setupScriptPath, $updatedContent, [System.Text.UTF8Encoding]::new($true))
        Write-Output "Updated pinned PSScriptAnalyzer URI to commit $latestCommit"
    }
}

Update-DependencyRequirement
Update-PinnedPSScriptAnalyzerSettingsUri
