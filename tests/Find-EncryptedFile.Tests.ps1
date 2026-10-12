BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\RansomwareRecovery\RansomwareRecovery.psd1') -Force
}

Describe 'Find-EncryptedFile' {
    BeforeAll {
        $root = Join-Path $TestDrive 'share'
        New-Item -ItemType Directory -Path "$root\a\b" -Force | Out-Null
        'x' | Set-Content "$root\a\report.docx.locked"
        'x' | Set-Content "$root\a\b\photo.jpg.LOCKED"
        'x' | Set-Content "$root\a\song.mp3"
        'x' | Set-Content "$root\a\track.wav.mp3"
        'x' | Set-Content "$root\a\HOW_TO_RESTORE_FILES.txt"
        'x' | Set-Content "$root\a\clean.txt"
        'x' | Set-Content "$root\a\.locked"
    }

    It 'finds encrypted files case-insensitively and derives the original path' {
        $found = Find-EncryptedFile -Path $root -EncryptedExtension '.locked' | Sort-Object Path

        $found.Path | Should -Be @("$root\a\b\photo.jpg.LOCKED", "$root\a\report.docx.locked")
        $found.OriginalPath | Should -Be @("$root\a\b\photo.jpg", "$root\a\report.docx")
        $found.Type | Should -Be @('Encrypted', 'Encrypted')
    }

    It 'only matches a suffix when the remaining name still has an extension' {
        $found = Find-EncryptedFile -Path $root -EncryptedExtension '.mp3'

        $found.Path | Should -Be "$root\a\track.wav.mp3"
    }

    It 'accepts an extension without a leading dot' {
        (Find-EncryptedFile -Path $root -EncryptedExtension 'locked').Count | Should -Be 2
    }

    It 'reports ransom notes without an original path' {
        $note = Find-EncryptedFile -Path $root -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_*' |
            Where-Object Type -EQ 'RansomNote'

        $note.Path | Should -Be "$root\a\HOW_TO_RESTORE_FILES.txt"
        $note.OriginalPath | Should -BeNullOrEmpty
    }

    It 'resolves PowerShell drive paths' {
        (Find-EncryptedFile -Path 'TestDrive:\share' -EncryptedExtension '.locked').Count | Should -Be 2
    }

    It 'writes a non-terminating error for a missing folder' {
        $found = Find-EncryptedFile -Path "$TestDrive\missing" -EncryptedExtension '.locked' -ErrorVariable err -ErrorAction SilentlyContinue

        $found | Should -BeNullOrEmpty
        $err | Should -Not -BeNullOrEmpty
    }
}
