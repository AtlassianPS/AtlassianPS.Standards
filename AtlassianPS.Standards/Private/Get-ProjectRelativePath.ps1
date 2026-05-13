function Get-ProjectRelativePath {
    [CmdletBinding()]
    [OutputType([String])]
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
