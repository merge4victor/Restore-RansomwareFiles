function Get-ShadowSnapshot {
    <#
    .SYNOPSIS
        Lists the shadow copies (previous versions) available for the volume or share
        that holds a path, newest first.

    .DESCRIPTION
        For local paths, reads Win32_ShadowCopy for the volume (requires an elevated
        session). For UNC paths and mapped network drives, asks the file server for its
        @GMT snapshot tokens, which is what Explorer's "Previous Versions" tab uses.

        The path does not need to exist; only its volume or share is used.

    .PARAMETER Path
        A file or folder path on the volume or share to inspect.

    .EXAMPLE
        Get-ShadowSnapshot -Path '\\fileserver\share'

        Check that the file server still has snapshots before starting a recovery.
    #>
    [CmdletBinding()]
    [OutputType('RansomwareRecovery.Snapshot')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path
    )

    process {
        foreach ($item in $Path) {
            $location = Resolve-VolumeLocation -Path $PSCmdlet.GetUnresolvedProviderPathFromPSPath($item)

            $snapshots = if ($location.Kind -eq 'Smb') {
                foreach ($token in Get-SmbSnapshotToken -ShareRoot $location.Root) {
                    [pscustomobject]@{
                        PSTypeName   = 'RansomwareRecovery.Snapshot'
                        Kind         = 'Smb'
                        Root         = $location.Root
                        Id           = $token
                        SnapshotTime = ConvertFrom-GmtToken -Token $token
                        SnapshotRoot = '{0}\{1}' -f $location.Root, $token
                    }
                }
            }
            else {
                try {
                    $shadowCopies = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction Stop
                }
                catch {
                    throw "Cannot read local shadow copies for '$item'. Run PowerShell as Administrator. $($_.Exception.Message)"
                }

                foreach ($shadow in $shadowCopies | Where-Object VolumeName -EQ $location.Root) {
                    [pscustomobject]@{
                        PSTypeName   = 'RansomwareRecovery.Snapshot'
                        Kind         = 'Local'
                        Root         = $location.Root
                        Id           = $shadow.ID
                        SnapshotTime = $shadow.InstallDate.ToUniversalTime()
                        SnapshotRoot = $shadow.DeviceObject
                    }
                }
            }

            $snapshots | Sort-Object -Property SnapshotTime -Descending
        }
    }
}
