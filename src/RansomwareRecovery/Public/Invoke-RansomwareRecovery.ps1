function Invoke-RansomwareRecovery {
    <#
    .SYNOPSIS
        Finds encrypted files under one or more folders, restores them from shadow copies,
        and writes a CSV log.

    .DESCRIPTION
        Runs Find-EncryptedFile followed by Restore-EncryptedFile, writes every result to
        RansomwareRecovery_<timestamp>.csv in -LogPath, and returns a summary.

        Always do a dry run with -WhatIf first; the CSV is still written and shows which
        snapshot each file would be restored from.

    .PARAMETER Path
        Folders to scan.

    .PARAMETER EncryptedExtension
        Suffixes the ransomware appended, e.g. '.locked'.

    .PARAMETER RansomNotePattern
        Wildcard patterns for ransom note file names.

    .PARAMETER Before
        Only use snapshots taken before this time.

    .PARAMETER QuarantinePath
        Move restored encrypted files and ransom notes here. Must be outside -Path.

    .PARAMETER DeleteEncrypted
        Permanently delete restored encrypted files and ransom notes.

    .PARAMETER Force
        Overwrite files that already exist at the original path.

    .PARAMETER LogPath
        Folder for the CSV log. Defaults to the current folder.

    .EXAMPLE
        Invoke-RansomwareRecovery -Path '\\fileserver\share' -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_*' -WhatIf

    .EXAMPLE
        Invoke-RansomwareRecovery -Path '\\fileserver\share' -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_*' -QuarantinePath 'E:\Quarantine' -LogPath 'E:\Logs'
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Keep')]
    [OutputType('RansomwareRecovery.Summary')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $EncryptedExtension,

        [string[]] $RansomNotePattern = @(),

        [datetime] $Before,

        [Parameter(Mandatory, ParameterSetName = 'Quarantine')]
        [string] $QuarantinePath,

        [Parameter(Mandatory, ParameterSetName = 'Delete')]
        [switch] $DeleteEncrypted,

        [switch] $Force,

        [string] $LogPath = (Get-Location -PSProvider FileSystem).Path
    )

    $started = Get-Date
    $scanRoots = foreach ($item in $Path) { $PSCmdlet.GetUnresolvedProviderPathFromPSPath($item).TrimEnd('\') + '\' }

    $restoreParameters = @{}
    foreach ($name in 'Before', 'QuarantinePath', 'DeleteEncrypted', 'Force') {
        if ($PSBoundParameters.ContainsKey($name)) { $restoreParameters[$name] = $PSBoundParameters[$name] }
    }

    if ($QuarantinePath) {
        $quarantineRoot = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($QuarantinePath).TrimEnd('\') + '\'
        foreach ($root in $scanRoots) {
            if ($quarantineRoot.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw "QuarantinePath '$QuarantinePath' must not be inside the scanned folder '$root'."
            }
        }
    }

    $logDirectory = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($LogPath)
    New-Item -ItemType Directory -Path $logDirectory -Force -WhatIf:$false -Confirm:$false | Out-Null
    $logFile = Join-Path $logDirectory ('RansomwareRecovery_{0:yyyyMMdd-HHmmss}.csv' -f $started)

    # Materialise the list first so quarantine moves cannot affect the directory walk.
    $found = @(Find-EncryptedFile -Path $Path -EncryptedExtension $EncryptedExtension -RansomNotePattern $RansomNotePattern)

    $processed = 0
    $results = @(
        $found | ForEach-Object {
            $processed++
            Write-Progress -Activity 'Restoring encrypted files' -Status $_.Path -PercentComplete ($processed * 100 / $found.Count)
            $_
        } | Restore-EncryptedFile @restoreParameters
    )
    Write-Progress -Activity 'Restoring encrypted files' -Completed

    if ($results.Count) {
        $results | Export-Csv -LiteralPath $logFile -NoTypeInformation -Encoding utf8 -WhatIf:$false -Confirm:$false
    }

    $counts = @{}
    foreach ($result in $results) { $counts[$result.Status] = 1 + [int]$counts[$result.Status] }

    [pscustomobject]@{
        PSTypeName     = 'RansomwareRecovery.Summary'
        EncryptedFound = @($found | Where-Object Type -EQ 'Encrypted').Count
        RansomNotes    = @($found | Where-Object Type -EQ 'RansomNote').Count
        Restored       = [int]$counts['Restored']
        WhatIf         = [int]$counts['WhatIf']
        AlreadyExists  = [int]$counts['AlreadyExists']
        NoSnapshot     = [int]$counts['NoSnapshot']
        Failed         = [int]$counts['Failed']
        LogFile        = if ($results.Count) { $logFile } else { $null }
        Duration       = (Get-Date) - $started
    }
}
