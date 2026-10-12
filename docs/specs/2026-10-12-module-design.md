# RansomwareRecovery module — design

Date: 2026-10-12
Status: Approved

## Goal

Turn the 2016 incident scripts (find files encrypted by ransomware, pull the clean
version from a shadow copy, put it back in place) into a reusable, parameterised
PowerShell 7 module that is safe to dry-run and safe to publish.

## Scope

- Windows only, PowerShell 7.2+.
- Snapshot sources:
  - Local volumes: `Win32_ShadowCopy` (requires elevation), files read through
    `\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopyN\...`.
  - SMB shares (UNC paths or mapped drives): `@GMT-` tokens obtained with
    `FSCTL_SRV_ENUMERATE_SNAPSHOTS` (the same call `volrest.exe` makes), files read
    through `\\server\share\@GMT-yyyy.MM.dd-HH.mm.ss\...`.
- No third-party binaries: `volrest.exe` and `Microsoft.Experimental.IO` are dropped;
  .NET handles long paths natively.
- No built-in email. Results are objects plus a CSV log.

## Commands

| Command | Purpose |
| --- | --- |
| `Find-EncryptedFile` | Walk a tree and classify files as `Encrypted` (name ends with a given suffix and the remaining name still has an extension) or `RansomNote` (wildcard match). Emits original path for encrypted files. |
| `Get-ShadowSnapshot` | List snapshots for the volume or share that holds a path, newest first. |
| `Restore-EncryptedFile` | Pipeline target for `Find-EncryptedFile`. Restores each original from the newest snapshot taken before the cutoff that contains it. Optional quarantine or deletion of encrypted files and ransom notes. |
| `Invoke-RansomwareRecovery` | Find + restore in one call, writes a timestamped CSV log, returns a summary. |

## Restore rules

1. Cutoff = `-Before` if supplied, otherwise the encrypted file's `LastWriteTimeUtc`.
   Snapshots at or after the cutoff are ignored.
2. Snapshots are tried newest first; the first one containing the original path wins.
3. An existing file at the original path is never overwritten without `-Force`
   (status `AlreadyExists`).
4. Removal of the encrypted file only happens after a successful restore.
   `-QuarantinePath` moves it (preserving `server\share\...` or `C\...` structure);
   `-DeleteEncrypted` deletes it. The two are mutually exclusive. Ransom notes are
   removed the same way when either is given, otherwise reported as `Skipped`.
5. Every change goes through `ShouldProcess`, so `-WhatIf` and `-Confirm` work.
   Under `-WhatIf` the chosen snapshot is still reported (status `WhatIf`).
6. Snapshot lookups are cached per volume/share for the duration of one pipeline.

Result statuses: `Restored`, `AlreadyExists`, `NoSnapshot`, `Failed`, `WhatIf`,
`Skipped`, `Quarantined`, `Deleted`.

Known limitation: restored files take the ACL of their parent folder.

## Repository layout

```
src/RansomwareRecovery/   module (Public/, Private/, SmbSnapshot.cs)
tests/                    Pester 5+ unit tests; Integration.Tests.ps1 (tagged)
legacy/                   original 2016 scripts, scrubbed of company/personal data
docs/                     this spec
.github/workflows/ci.yml  PSScriptAnalyzer + unit tests + integration tests on windows-latest
```

## Testing

- Unit tests mock `Resolve-VolumeLocation` and `Get-ShadowSnapshot` and use folders
  under `TestDrive:` as fake snapshots, so real copy/move logic is exercised.
- Integration tests (tag `Integration`, gated on `RR_INTEGRATION=1` and elevation)
  create a real `ClientAccessible` shadow copy and an SMB share on the CI runner and
  restore through both paths.
