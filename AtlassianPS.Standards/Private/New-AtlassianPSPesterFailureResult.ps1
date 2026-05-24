function New-AtlassianPSPesterFailureResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory result object only; does not change system state.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$File,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Message,

        [Parameter()]
        [TimeSpan]$Duration = [TimeSpan]::Zero
    )

    [PSCustomObject]@{
        File         = $File
        Passed       = 0
        Failed       = 1
        Skipped      = 0
        Duration     = $Duration
        Success      = $false
        Error        = $Message
        FailedTests  = @([PSCustomObject]@{ Name = $Name; ErrorMessage = $Message })
        SkippedTests = @()
        XmlPath      = $null
    }
}
