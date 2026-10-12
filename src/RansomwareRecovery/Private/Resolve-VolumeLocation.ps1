function Get-LocalVolume {
    [CmdletBinding()]
    param()

    if ($null -eq $script:LocalVolumes) {
        $script:LocalVolumes = @(
            Get-CimInstance -ClassName Win32_Volume |
                Where-Object { $_.Name -and $_.Name -notlike '\\?\*' } |
                Select-Object -Property Name, DeviceID
        )
    }
    $script:LocalVolumes
}

function Get-NetworkDriveRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DriveLetter
    )

    if (-not $script:NetworkDrives.ContainsKey($DriveLetter)) {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$DriveLetter' AND DriveType=4"
        $script:NetworkDrives[$DriveLetter] = if ($disk) { $disk.ProviderName } else { $null }
    }
    $script:NetworkDrives[$DriveLetter]
}

function Resolve-VolumeLocation {
    <#
    .SYNOPSIS
        Splits a full path into the snapshot-bearing root (local volume or SMB share)
        and the path relative to that root.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $fullPath = $Path -replace '^\\\\\?\\UNC\\', '\\' -replace '^\\\\\?\\', ''

    if ($fullPath -match '^[A-Za-z]:') {
        $networkRoot = Get-NetworkDriveRoot -DriveLetter $fullPath.Substring(0, 2).ToUpperInvariant()
        if ($networkRoot) {
            $fullPath = $networkRoot.TrimEnd('\') + $fullPath.Substring(2)
        }
    }

    if ($fullPath -match '^\\\\(?<server>[^\\]+)\\(?<share>[^\\]+)(?:\\(?<rest>.*))?$') {
        return [pscustomobject]@{
            Kind         = 'Smb'
            Root         = '\\{0}\{1}' -f $Matches.server, $Matches.share
            RelativePath = [string]$Matches.rest
        }
    }

    $volume = Get-LocalVolume |
        Where-Object { $fullPath.StartsWith($_.Name, [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object -Property { $_.Name.Length } -Descending |
        Select-Object -First 1

    if (-not $volume) {
        throw "Cannot determine which volume holds '$Path'."
    }

    [pscustomobject]@{
        Kind         = 'Local'
        Root         = $volume.DeviceID
        RelativePath = $fullPath.Substring($volume.Name.Length)
    }
}
