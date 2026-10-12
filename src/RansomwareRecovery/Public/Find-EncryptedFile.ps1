function Find-EncryptedFile {
    <#
    .SYNOPSIS
        Finds files that ransomware has encrypted and renamed, plus any ransom notes.

    .DESCRIPTION
        Recursively walks one or more directories (long paths supported) and reports:

        - Encrypted files: the name ends with one of -EncryptedExtension and what is left
          still has an extension. 'report.docx.locked' is reported with an original path of
          'report.docx'; 'song.mp3' is not reported for suffix '.mp3'.
        - Ransom notes: the name matches one of the -RansomNotePattern wildcards.

        Reparse points (junctions, symlinks) and inaccessible folders are skipped.

    .PARAMETER Path
        Directories to scan. Accepts local paths, UNC paths and PowerShell drives.

    .PARAMETER EncryptedExtension
        Suffixes the ransomware appended, e.g. '.locked', '.encrypted'. A leading dot is
        added if missing.

    .PARAMETER RansomNotePattern
        Wildcard patterns for ransom note file names, e.g. 'HOW_TO_RESTORE_FILES.*'.

    .EXAMPLE
        Find-EncryptedFile -Path '\\fileserver\share' -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_*'
    #>
    [CmdletBinding()]
    [OutputType('RansomwareRecovery.FoundFile')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $EncryptedExtension,

        [string[]] $RansomNotePattern = @()
    )

    begin {
        $suffixes = foreach ($extension in $EncryptedExtension) {
            if ($extension.StartsWith('.')) { $extension } else { ".$extension" }
        }

        $options = [System.IO.EnumerationOptions]@{
            RecurseSubdirectories = $true
            IgnoreInaccessible    = $true
            AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint
        }
    }

    process {
        foreach ($item in $Path) {
            $root = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($item)
            if (-not [System.IO.Directory]::Exists($root)) {
                Write-Error -Message "Directory not found: $root" -Category ObjectNotFound -TargetObject $item
                continue
            }

            foreach ($file in [System.IO.DirectoryInfo]::new($root).EnumerateFiles('*', $options)) {
                $match = Get-FileClassification -Name $file.Name -EncryptedExtension $suffixes -RansomNotePattern $RansomNotePattern
                if (-not $match) { continue }

                [pscustomobject]@{
                    PSTypeName       = 'RansomwareRecovery.FoundFile'
                    Type             = $match.Type
                    Path             = $file.FullName
                    OriginalPath     = if ($match.OriginalName) { [System.IO.Path]::Combine($file.DirectoryName, $match.OriginalName) } else { $null }
                    LastWriteTimeUtc = $file.LastWriteTimeUtc
                    Length           = $file.Length
                }
            }
        }
    }
}
