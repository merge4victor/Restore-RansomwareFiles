if (-not ('RansomwareRecovery.SmbSnapshot' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'Private\SmbSnapshot.cs')
}

$script:LocalVolumes = $null
$script:NetworkDrives = @{}

foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private'), (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1') {
    . $file.FullName
}

Export-ModuleMember -Function (Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1').BaseName
