function Invoke-AtlassianPSPesterJobSet {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TestFile,

        [Parameter(Mandatory)]
        [ScriptBlock]$RunTestScriptBlock,

        [Parameter(Mandatory)]
        [String]$ProjectRoot,

        [Parameter()]
        [String[]]$Tag,

        [Parameter()]
        [String[]]$ExcludeTag,

        [Parameter(Mandatory)]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$Output,

        [Parameter()]
        [String]$TempResultsDir,

        [Parameter()]
        [Boolean]$GenerateXml,

        [Parameter(Mandatory)]
        [ValidateRange(1, 64)]
        [Int]$ThrottleLimit,

        [Parameter(Mandatory)]
        [ValidateRange(1, [Int]::MaxValue)]
        [Int]$PerFileTimeoutSeconds,

        [Parameter(Mandatory)]
        [System.Management.Automation.Host.PSHost]$StreamingHost
    )

    $results = @()
    $pendingJobs = [System.Collections.Generic.List[Object]]::new()
    foreach ($file in $TestFile) {
        $job = Start-ThreadJob `
            -ScriptBlock $RunTestScriptBlock `
            -ArgumentList @($file, $ProjectRoot, $Tag, $ExcludeTag, $Output, $TempResultsDir, $GenerateXml) `
            -ThrottleLimit $ThrottleLimit `
            -StreamingHost $StreamingHost `
            -Name "Pester:$($file.BaseName)"

        $pendingJobs.Add([PSCustomObject]@{
                File      = $file
                Job       = $job
                StartedAt = Get-Date
            })
    }

    while ($pendingJobs.Count -gt 0) {
        $now = Get-Date
        $ready = @(
            foreach ($info in $pendingJobs) {
                if ($info.Job.State -notin 'NotStarted', 'Running') {
                    $info
                }
                elseif (($now - $info.StartedAt).TotalSeconds -ge $PerFileTimeoutSeconds) {
                    $info
                }
            }
        )

        if ($ready.Count -eq 0) {
            $remainingSeconds = @(
                foreach ($info in $pendingJobs) {
                    [Math]::Max(1, $PerFileTimeoutSeconds - [Int](($now - $info.StartedAt).TotalSeconds))
                }
            ) | Sort-Object | Select-Object -First 1
            $jobs = @($pendingJobs | ForEach-Object { $_.Job })
            $null = Wait-Job -Job $jobs -Any -Timeout ([Math]::Min(5, $remainingSeconds))
            continue
        }

        foreach ($info in $ready) {
            $jobOutput = Receive-AtlassianPSPesterJob -JobInfo $info -PerFileTimeoutSeconds $PerFileTimeoutSeconds
            if ($null -ne $jobOutput) { $results += $jobOutput }
            $null = $pendingJobs.Remove($info)
        }
    }

    return $results
}
