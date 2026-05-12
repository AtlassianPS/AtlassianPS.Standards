Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$publicFunctions = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public/*.ps1') -ErrorAction SilentlyContinue)

foreach ($file in $publicFunctions) {
    . $file.FullName
}

Export-ModuleMember -Function $publicFunctions.BaseName
