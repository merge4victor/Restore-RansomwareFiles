function Restore-EncryptedFile {
    <#
    .SYNOPSIS
        Restores the clean original of each encrypted file from a shadow copy.

    .DESCRIPTION
        Takes the output of Find-EncryptedFile. For each encrypted file it looks for the
        original path in the volume's or share's snapshots, newest first, ignoring any
        snapshot taken at or after the cutoff (-Before, or by default the moment the
        encrypted file was last written). The first match is copied back to the original
        location.

        An existing file at the original path is never overwritten unless -Force is used.
        Encrypted files and ransom notes are left in place unless -QuarantinePath or
        -DeleteEncrypted is given, and are only removed after a successful restore.

        Supports -WhatIf: the snapshot that would be used is reported with status 'WhatIf'.

    .PARAMETER InputObject
        Objects from Find-EncryptedFile.

    .PARAMETER Before
        Only use snapshots taken before this time (local time unless specified). Use the
        time the infection started if the ransomware preserves file timestamps.

    .PARAMETER QuarantinePath
        Move restored encrypted files and ransom notes here, keeping their folder
        structure. Must not be inside the folders being scanned.

    .PARAMETER DeleteEncrypted
        Permanently delete restored encrypted files and ransom notes.

    .PARAMETER Force
        Overwrite a file that already exists at the original path.

    .EXAMPLE
        Find-EncryptedFile -Path D:\Shares -EncryptedExtension .locked | Restore-EncryptedFile -WhatIf

    .EXAMPLE
        Find-EncryptedFile -Path D:\Shares -EncryptedExtension .locked -RansomNotePattern 'HOW_TO_*' |
            Restore-EncryptedFile -QuarantinePath E:\Quarantine |
            Export-Csv restore-log.csv -NoTypeInformation
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Keep')]
    [OutputType('RansomwareRecovery.RestoreResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('RansomwareRecovery.FoundFile')]
        [pscustomobject[]] $InputObject,

        [datetime] $Before,

        [Parameter(Mandatory, ParameterSetName = 'Quarantine')]
        [string] $QuarantinePath,

        [Parameter(Mandatory, ParameterSetName = 'Delete')]
        [switch] $DeleteEncrypted,

        [switch] $Force
    )

    begin {
        $snapshotCache = @{}
        $removeMode = $PSCmdlet.ParameterSetName
        if ($removeMode -eq 'Quarantine') {
            $quarantineRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($QuarantinePath)
        }
        $cutoffOverride = if ($PSBoundParameters.ContainsKey('Before')) { $Before.ToUniversalTime() }
        $declinedStatus = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }

        function ConvertTo-Result ($Item, $Status, $Snapshot, $SourcePath, $Message) {
            [pscustomobject]@{
                PSTypeName   = 'RansomwareRecovery.RestoreResult'
                Type         = $Item.Type
                Path         = $Item.Path
                OriginalPath = $Item.OriginalPath
                Status       = $Status
                SnapshotTime = if ($Snapshot) { $Snapshot.SnapshotTime } else { $null }
                SourcePath   = $SourcePath
                RemovedTo    = $null
                Message      = $Message
            }
        }

        function Invoke-Removal ($Result) {
            if ($removeMode -eq 'Quarantine') {
                if ($PSCmdlet.ShouldProcess($Result.Path, "Move to quarantine '$quarantineRoot'")) {
                    $Result.RemovedTo = Move-ToQuarantine -Path $Result.Path -QuarantineRoot $quarantineRoot
                    return $true
                }
            }
            elseif ($PSCmdlet.ShouldProcess($Result.Path, 'Delete')) {
                [System.IO.File]::Delete($Result.Path)
                $Result.RemovedTo = '<deleted>'
                return $true
            }
            $false
        }
    }

    process {
        foreach ($item in $InputObject) {
            if ($item.Type -eq 'RansomNote') {
                $result = ConvertTo-Result $item 'Skipped'
                if ($removeMode -ne 'Keep') {
                    try {
                        if (Invoke-Removal $result) {
                            $result.Status = if ($removeMode -eq 'Quarantine') { 'Quarantined' } else { 'Deleted' }
                        }
                        else {
                            $result.Status = $declinedStatus
                        }
                    }
                    catch {
                        $result.Status = 'Failed'
                        $result.Message = $_.Exception.Message
                    }
                }
                $result
                continue
            }

            $original = $item.OriginalPath
            if (-not $Force -and [System.IO.File]::Exists($original)) {
                ConvertTo-Result $item 'AlreadyExists' -Message 'A file already exists at the original path. Use -Force to overwrite.'
                continue
            }

            try {
                $location = Resolve-VolumeLocation -Path $original
                if (-not $snapshotCache.ContainsKey($location.Root)) {
                    try {
                        $snapshotCache[$location.Root] = @{ Snapshots = @(Get-ShadowSnapshot -Path $original); Error = $null }
                    }
                    catch {
                        $snapshotCache[$location.Root] = @{ Snapshots = @(); Error = $_.Exception.Message }
                    }
                }
                $cached = $snapshotCache[$location.Root]
                if ($cached.Error) { throw $cached.Error }
            }
            catch {
                ConvertTo-Result $item 'Failed' -Message $_.Exception.Message
                continue
            }

            $cutoff = if ($cutoffOverride) { $cutoffOverride } else { $item.LastWriteTimeUtc }
            $snapshot = $null
            $source = $null
            foreach ($candidate in $cached.Snapshots) {
                if ($candidate.SnapshotTime -ge $cutoff) { continue }
                $candidatePath = Join-SnapshotPath -Snapshot $candidate -RelativePath $location.RelativePath
                if ([System.IO.File]::Exists($candidatePath)) {
                    $snapshot = $candidate
                    $source = $candidatePath
                    break
                }
            }

            if (-not $snapshot) {
                ConvertTo-Result $item 'NoSnapshot' -Message "No snapshot taken before $($cutoff.ToString('u')) contains the original file."
                continue
            }

            $result = ConvertTo-Result $item $declinedStatus $snapshot $source
            if (-not $PSCmdlet.ShouldProcess($original, "Restore from snapshot taken $($snapshot.SnapshotTime.ToString('u'))")) {
                $result
                continue
            }

            try {
                [System.IO.File]::Copy($source, $original, [bool]$Force)
                $result.Status = 'Restored'
            }
            catch {
                $result.Status = 'Failed'
                $result.Message = $_.Exception.Message
                $result
                continue
            }

            if ($removeMode -ne 'Keep') {
                try {
                    Invoke-Removal $result | Out-Null
                }
                catch {
                    $result.Message = "Restored, but could not remove the encrypted file: $($_.Exception.Message)"
                }
            }
            $result
        }
    }
}
