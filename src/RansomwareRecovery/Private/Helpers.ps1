function Get-FileClassification {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string[]] $EncryptedExtension,

        [string[]] $RansomNotePattern = @()
    )

    foreach ($suffix in $EncryptedExtension) {
        if ($Name.Length -gt $suffix.Length -and $Name.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
            $originalName = $Name.Substring(0, $Name.Length - $suffix.Length)
            # Requiring a remaining extension stops 'song.mp3' matching suffix '.mp3'.
            if ([System.IO.Path]::GetExtension($originalName)) {
                return [pscustomobject]@{ Type = 'Encrypted'; OriginalName = $originalName }
            }
        }
    }

    foreach ($pattern in $RansomNotePattern) {
        if ($Name -like $pattern) {
            return [pscustomobject]@{ Type = 'RansomNote'; OriginalName = $null }
        }
    }
}

function ConvertFrom-GmtToken {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [string] $Token
    )

    [datetime]::ParseExact(
        $Token,
        "'@GMT-'yyyy.MM.dd-HH.mm.ss",
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    )
}

function Get-SmbSnapshotToken {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $ShareRoot
    )

    [RansomwareRecovery.SmbSnapshot]::GetTokens($ShareRoot)
}

function Join-SnapshotPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Snapshot,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $RelativePath
    )

    '{0}\{1}' -f $Snapshot.SnapshotRoot.TrimEnd('\'), $RelativePath.TrimStart('\')
}

function Move-ToQuarantine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $QuarantineRoot
    )

    # \\server\share\a.txt -> <root>\server\share\a.txt ; C:\a.txt -> <root>\C\a.txt
    $relative = $Path -replace '^\\\\\?\\UNC\\', '' -replace '^\\\\\?\\', '' -replace '^\\\\', '' -replace ':', ''
    $destination = [System.IO.Path]::Combine($QuarantineRoot, $relative)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
    [System.IO.File]::Move($Path, $destination, $true)
    $destination
}
