BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\RansomwareRecovery\RansomwareRecovery.psd1') -Force

    # Live data and fake snapshots are plain folders under TestDrive; the snapshot lookup is mocked.
    function New-TestSnapshot ([string] $Name, [datetime] $Time, [hashtable] $Files) {
        $snapshotRoot = Join-Path $TestDrive $Name
        foreach ($relative in $Files.Keys) {
            $target = Join-Path $snapshotRoot $relative
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            Set-Content -Path $target -Value $Files[$relative] -NoNewline
        }
        [pscustomobject]@{
            PSTypeName   = 'RansomwareRecovery.Snapshot'
            Kind         = 'Local'
            Root         = 'test-volume'
            Id           = $Name
            SnapshotTime = $Time.ToUniversalTime()
            SnapshotRoot = $snapshotRoot
        }
    }

    function New-EncryptedFile ([string] $Relative) {
        $target = Join-Path $script:live $Relative
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Set-Content -Path $target -Value 'ENCRYPTED' -NoNewline
    }
}

Describe 'Restore-EncryptedFile' {
    BeforeEach {
        $script:live = Join-Path $TestDrive 'live'
        Get-ChildItem $TestDrive | Remove-Item -Recurse -Force
        New-Item -ItemType Directory -Path $script:live | Out-Null

        $now = Get-Date
        $script:snapshots = @(
            New-TestSnapshot 'snapAfter' $now.AddHours(1) @{ 'docs\report.docx' = 'after-encryption' }
            New-TestSnapshot 'snapNew' $now.AddDays(-1) @{ 'docs\report.docx' = 'clean-new' }
            New-TestSnapshot 'snapOld' $now.AddDays(-2) @{ 'docs\report.docx' = 'clean-old'; 'docs\old-only.txt' = 'old-only' }
        )

        Mock -ModuleName RansomwareRecovery Get-ShadowSnapshot { $script:snapshots }
        Mock -ModuleName RansomwareRecovery Resolve-VolumeLocation {
            [pscustomobject]@{
                Kind         = 'Local'
                Root         = 'test-volume'
                RelativePath = $Path.Substring($script:live.Length + 1)
            }
        }

        New-EncryptedFile 'docs\report.docx.locked'
        $script:report = Join-Path $script:live 'docs\report.docx'
    }

    It 'restores from the newest snapshot taken before the file was encrypted' {
        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked | Restore-EncryptedFile

        $result.Status | Should -Be 'Restored'
        $result.SourcePath | Should -BeLike '*snapNew*'
        Get-Content $script:report -Raw | Should -Be 'clean-new'
    }

    It 'honours -Before as the cutoff' {
        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked |
            Restore-EncryptedFile -Before (Get-Date).AddDays(-1.5)

        $result.Status | Should -Be 'Restored'
        Get-Content $script:report -Raw | Should -Be 'clean-old'
    }

    It 'falls back to an older snapshot when newer ones do not contain the file' {
        New-EncryptedFile 'docs\old-only.txt.locked'

        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked |
            Restore-EncryptedFile | Where-Object Path -Like '*old-only*'

        $result.SourcePath | Should -BeLike '*snapOld*'
    }

    It 'reports NoSnapshot when no snapshot has the file' {
        New-EncryptedFile 'docs\unknown.xlsx.locked'

        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked |
            Restore-EncryptedFile | Where-Object Path -Like '*unknown*'

        $result.Status | Should -Be 'NoSnapshot'
    }

    It 'does not overwrite an existing original without -Force' {
        Set-Content $script:report 'current' -NoNewline

        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked | Restore-EncryptedFile

        $result.Status | Should -Be 'AlreadyExists'
        Get-Content $script:report -Raw | Should -Be 'current'
    }

    It 'overwrites an existing original with -Force' {
        Set-Content $script:report 'current' -NoNewline

        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked | Restore-EncryptedFile -Force

        $result.Status | Should -Be 'Restored'
        Get-Content $script:report -Raw | Should -Be 'clean-new'
    }

    It 'changes nothing under -WhatIf but reports the snapshot it would use' {
        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked |
            Restore-EncryptedFile -QuarantinePath (Join-Path $TestDrive 'q') -WhatIf

        $result.Status | Should -Be 'WhatIf'
        $result.SourcePath | Should -BeLike '*snapNew*'
        $script:report | Should -Not -Exist
        "$script:report.locked" | Should -Exist
    }

    It 'moves the encrypted file and ransom notes to quarantine after restoring' {
        Set-Content (Join-Path $script:live 'docs\HOW_TO_RESTORE.txt') 'pay'
        $quarantine = Join-Path $TestDrive 'q'

        $results = Find-EncryptedFile $script:live -EncryptedExtension .locked -RansomNotePattern 'HOW_TO_*' |
            Restore-EncryptedFile -QuarantinePath $quarantine

        ($results | Where-Object Type -EQ 'Encrypted').Status | Should -Be 'Restored'
        ($results | Where-Object Type -EQ 'RansomNote').Status | Should -Be 'Quarantined'
        $results.RemovedTo | ForEach-Object { $_ | Should -Exist }
        "$script:report.locked" | Should -Not -Exist
    }

    It 'leaves the encrypted file in place when the restore fails' {
        New-EncryptedFile 'docs\unknown.xlsx.locked'

        Find-EncryptedFile $script:live -EncryptedExtension .locked |
            Restore-EncryptedFile -DeleteEncrypted | Out-Null

        Join-Path $script:live 'docs\unknown.xlsx.locked' | Should -Exist
        "$script:report.locked" | Should -Not -Exist
    }

    It 'skips ransom notes when no removal option is given' {
        Set-Content (Join-Path $script:live 'docs\HOW_TO_RESTORE.txt') 'pay'

        $note = Find-EncryptedFile $script:live -EncryptedExtension .locked -RansomNotePattern 'HOW_TO_*' |
            Restore-EncryptedFile | Where-Object Type -EQ 'RansomNote'

        $note.Status | Should -Be 'Skipped'
        $note.Path | Should -Exist
    }

    It 'looks up snapshots once per volume' {
        New-EncryptedFile 'docs\old-only.txt.locked'

        Find-EncryptedFile $script:live -EncryptedExtension .locked | Restore-EncryptedFile | Out-Null

        Should -Invoke -ModuleName RansomwareRecovery Get-ShadowSnapshot -Times 1 -Exactly
    }

    It 'reports Failed when snapshots cannot be read' {
        Mock -ModuleName RansomwareRecovery Get-ShadowSnapshot { throw 'access denied' }

        $result = Find-EncryptedFile $script:live -EncryptedExtension .locked | Restore-EncryptedFile

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Be 'access denied'
    }
}

Describe 'Invoke-RansomwareRecovery' {
    BeforeEach {
        $script:live = Join-Path $TestDrive 'live'
        Get-ChildItem $TestDrive | Remove-Item -Recurse -Force
        New-Item -ItemType Directory -Path $script:live | Out-Null
        $script:snapshots = @(New-TestSnapshot 'snap' (Get-Date).AddDays(-1) @{ 'report.docx' = 'clean' })

        Mock -ModuleName RansomwareRecovery Get-ShadowSnapshot { $script:snapshots }
        Mock -ModuleName RansomwareRecovery Resolve-VolumeLocation {
            [pscustomobject]@{ Kind = 'Local'; Root = 'test-volume'; RelativePath = $Path.Substring($script:live.Length + 1) }
        }

        New-EncryptedFile 'report.docx.locked'
        New-EncryptedFile 'missing.txt.locked'
        $script:logs = Join-Path $TestDrive 'logs'
    }

    It 'restores, writes a CSV log and returns a summary' {
        $summary = Invoke-RansomwareRecovery -Path $script:live -EncryptedExtension .locked -LogPath $script:logs

        $summary.EncryptedFound | Should -Be 2
        $summary.Restored | Should -Be 1
        $summary.NoSnapshot | Should -Be 1
        $summary.LogFile | Should -Exist
        (Import-Csv $summary.LogFile).Count | Should -Be 2
    }

    It 'still writes the log under -WhatIf' {
        $summary = Invoke-RansomwareRecovery -Path $script:live -EncryptedExtension .locked -LogPath $script:logs -WhatIf

        $summary.WhatIf | Should -Be 1
        $summary.Restored | Should -Be 0
        $summary.LogFile | Should -Exist
        Join-Path $script:live 'report.docx' | Should -Not -Exist
    }

    It 'refuses a quarantine folder inside the scanned folder' {
        { Invoke-RansomwareRecovery -Path $script:live -EncryptedExtension .locked -QuarantinePath (Join-Path $script:live 'q') -LogPath $script:logs } |
            Should -Throw '*must not be inside*'
    }
}
