function Receive-AtlassianPSPesterJob {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Build helper warning output is operator-facing.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$JobInfo,

        [Parameter(Mandatory)]
        [ValidateRange(1, [Int]::MaxValue)]
        [Int]$PerFileTimeoutSeconds
    )

    $job = $JobInfo.Job
    $file = $JobInfo.File
    $elapsed = (Get-Date) - $JobInfo.StartedAt

    if ($job.State -eq 'Completed') {
        try {
            return Receive-Job -Job $job -ErrorAction Stop 6> $null
        }
        catch {
            Write-Warning "Receive-Job [$($job.Name)] threw: $_"
            return New-AtlassianPSPesterFailureResult -File $file.Name -Name 'Receive-Job failure' -Message $_.Exception.Message -Duration $elapsed
        }
        finally {
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Remove-Job [$($job.Name)] threw: $_" }
        }
    }

    if ($job.State -in 'Failed', 'Stopped') {
        try {
            $null = Receive-Job -Job $job -ErrorAction SilentlyContinue 6> $null
        }
        finally {
            try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Remove-Job [$($job.Name)] threw: $_" }
        }

        return New-AtlassianPSPesterFailureResult -File $file.Name -Name 'Pester job failure' -Message "Pester job ended in state '$($job.State)'." -Duration $elapsed
    }

    Write-Warning "Test file [$($file.Name)] exceeded ${PerFileTimeoutSeconds}s budget; stopping the runspace and recording an orchestrator timeout."
    try { Stop-Job -Job $job -ErrorAction SilentlyContinue } catch { Write-Warning "Stop-Job [$($job.Name)] threw: $_" }
    try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { Write-Warning "Remove-Job [$($job.Name)] threw: $_" }

    New-AtlassianPSPesterFailureResult `
        -File $file.Name `
        -Name 'Orchestrator timeout' `
        -Message "Test file [$($file.Name)] timed out after ${PerFileTimeoutSeconds}s." `
        -Duration ([TimeSpan]::FromSeconds($PerFileTimeoutSeconds))
}
