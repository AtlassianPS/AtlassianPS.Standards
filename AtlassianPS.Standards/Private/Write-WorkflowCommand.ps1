function Write-WorkflowCommand {
    <#
    .SYNOPSIS
        Emit a GitHub Actions workflow command on stdout.
    .DESCRIPTION
        GitHub Actions workflow commands must reach stdout for the runner to
        parse them as inline annotations.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage(
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
