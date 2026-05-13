function Write-LintMessage {
    [CmdletBinding()]
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
