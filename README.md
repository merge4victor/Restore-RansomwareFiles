# Restore-RansomwareFiles

[![CI](https://github.com/merge4victor/Restore-RansomwareFiles/actions/workflows/ci.yml/badge.svg)](https://github.com/merge4victor/Restore-RansomwareFiles/actions/workflows/ci.yml)

A PowerShell module that recovers from crypto-ransomware (CryptoLocker and friends) on
Windows file servers. It finds the files the ransomware encrypted and renamed, pulls the
clean original out of a Volume Shadow Copy or SMB "Previous Versions" snapshot, and puts
it back where it was.

It started as a set of scripts written during a real CryptoLocker incident on a
corporate file server in 2016. Those scripts are kept in [`legacy/`](legacy/) for
reference.

## How it works

Most ransomware writes an encrypted copy next to each file under a new name
(`report.docx` becomes `report.docx.locked`) and deletes the original. If the volume
had shadow copies from before the attack, the original is still inside them.

1. **Find**: walk the folder tree and pick out names that end with the ransomware's
   suffix *and* still have a real extension underneath, plus any ransom notes.
2. **Locate snapshots**: for local volumes, read `Win32_ShadowCopy`; for UNC paths and
   mapped drives, ask the file server for its `@GMT-` snapshot tokens.
3. **Restore**: for each file, try snapshots newest first, ignoring any taken after the
   file was encrypted, and copy the first clean original back into place.
4. **Clean up (optional)**: move the encrypted file and ransom notes to a quarantine
   folder, or delete them, only after the restore succeeded.

No third-party binaries are needed, and paths longer than 260 characters work.

## Requirements

- Windows with PowerShell 7.2 or later.
- For local volumes: an elevated session (reading shadow copies needs admin rights).
- For network shares: Previous Versions available on the file server, and read access
  to the share.

## Installation

```powershell
git clone https://github.com/merge4victor/Restore-RansomwareFiles.git
Import-Module .\Restore-RansomwareFiles\src\RansomwareRecovery\RansomwareRecovery.psd1
```

## Before you start

- **Contain the infection first.** Disconnect the infected client and make sure nothing
  is still encrypting files, otherwise you will be restoring into a moving target.
- **Check that snapshots survived.** Many strains run `vssadmin delete shadows`.
  ```powershell
  Get-ShadowSnapshot -Path '\\fileserver\share'
  ```
- **Identify the suffix and ransom note names** by looking at a few affected folders.
- **Pick a cutoff time.** By default a snapshot is only used if it is older than the
  encrypted file. If the strain preserves timestamps, pass `-Before` with the time the
  infection started.

## Usage

Dry run first. Nothing is changed, but the CSV log shows exactly which snapshot every
file would come from:

```powershell
Invoke-RansomwareRecovery -Path '\\fileserver\share' `
    -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_RESTORE_FILES.*' `
    -LogPath 'D:\RecoveryLogs' -WhatIf
```

Then run it for real, moving the encrypted files and notes to quarantine:

```powershell
Invoke-RansomwareRecovery -Path '\\fileserver\share' `
    -EncryptedExtension '.locked' -RansomNotePattern 'HOW_TO_RESTORE_FILES.*' `
    -QuarantinePath 'D:\Quarantine' -LogPath 'D:\RecoveryLogs'
```

Example summary:

```
EncryptedFound : 18342
RansomNotes    : 1204
Restored       : 18190
WhatIf         : 0
AlreadyExists  : 12
NoSnapshot     : 140
Failed         : 0
LogFile        : D:\RecoveryLogs\RansomwareRecovery_20261012-143015.csv
Duration       : 00:41:07
```

Re-running is safe: files that are already back are reported as `AlreadyExists` and left
alone.

The building blocks can also be used on their own:

```powershell
Find-EncryptedFile -Path 'E:\Shares\Finance' -EncryptedExtension '.encrypted', '.locked' |
    Restore-EncryptedFile -Before '2026-10-11 09:00' |
    Export-Csv finance.csv -NoTypeInformation
```

## Commands

| Command | What it does |
| --- | --- |
| `Find-EncryptedFile` | Finds encrypted files (and their original names) and ransom notes. |
| `Get-ShadowSnapshot` | Lists the snapshots available for a local volume or SMB share. |
| `Restore-EncryptedFile` | Restores originals from snapshots. Supports `-WhatIf`, `-Confirm`, `-Before`, `-Force`, `-QuarantinePath`, `-DeleteEncrypted`. |
| `Invoke-RansomwareRecovery` | Find + restore + CSV log + summary in one call. |

Use `Get-Help <command> -Full` for every parameter.

### Result statuses

| Status | Meaning |
| --- | --- |
| `Restored` | Clean original copied back. |
| `AlreadyExists` | A file is already at the original path; not touched (use `-Force` to overwrite). |
| `NoSnapshot` | No snapshot taken before the cutoff contains the original. |
| `Failed` | Snapshot lookup or copy failed; see `Message`. |
| `WhatIf` | Dry run; `SourcePath` shows the snapshot copy that would be used. |
| `Quarantined` / `Deleted` | Ransom note removed. |
| `Skipped` | Ransom note left in place, or the operation was declined at a `-Confirm` prompt. |

## Notes and limitations

- Restored files take the permissions of the folder they are restored into.
- Ransomware that encrypts files in place without renaming them is not detected,
  because there is no suffix to match.
- Snapshot lookups are cached per volume or share for one run, so very large trees cost
  one lookup, not one per file.
- Email reporting from the original scripts was dropped. To mail the log, pipe the
  summary into whatever your environment uses, e.g. Microsoft Graph `Send-MgUserMail`.

## Development

```powershell
./build.ps1               # PSScriptAnalyzer + unit tests
./build.ps1 -Integration  # also creates a real shadow copy and SMB share (admin, disposable machine)
```

CI runs both on `windows-latest`.

## License

[MIT](LICENSE) © Fatih Mergen
