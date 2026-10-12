# Changelog

## 1.0.0 - 2026-10-12

Rewritten as the `RansomwareRecovery` PowerShell 7 module.

- `Find-EncryptedFile`, `Get-ShadowSnapshot`, `Restore-EncryptedFile`, `Invoke-RansomwareRecovery`.
- Reads local Volume Shadow Copies and SMB previous versions natively; `volrest.exe` and
  `Microsoft.Experimental.IO` are no longer needed.
- Picks the newest snapshot taken before the file was encrypted.
- `-WhatIf` / `-Confirm`, optional quarantine or deletion, CSV log.
- Pester tests and GitHub Actions CI.

## 2016

Original incident scripts, now in `legacy/`.
