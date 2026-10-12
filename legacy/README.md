# Legacy scripts (2016)

These are the original scripts written during a CryptoLocker incident in February 2016,
kept for history. Server names, email addresses and file paths from that environment
have been replaced with placeholders. **Use the module in [`src/`](../src/) instead.**

| Script | Purpose |
| --- | --- |
| `restore-infected-files.ps1` | First version: map the share as `W:`, restore each `*.???.mp3` file with `volrest.exe`, then delete the encrypted copy. |
| `Restore-Only.ps1`, `1-Restore-Only.ps1` | Restore only, with logging and an email report. |
| `find-delete.ps1`, `find-delete-V2.ps1`, `2-find-delete-V2.ps1` | Delete encrypted files and ransom notes after restoration was confirmed. |
| `rename-files.ps1` | Strip special characters from names that could not be restored. |

They expected to run from `C:\Temp\Restore-Infected-Files\` with:

- `volrest.exe` from the Windows Server 2003 Resource Kit, to list previous versions,
- `Microsoft.Experimental.IO.dll` from the BCL team, to get around the 260-character path limit,
- the affected share mapped as `W:`.

Neither binary is included here: `volrest.exe` cannot be redistributed, and
PowerShell 7 handles long paths natively.

## Known bugs

These are left unfixed on purpose; they are why the module was rewritten.

- `1-Restore-Only.ps1` and `2-find-delete-V2.ps1` filter with `-eq "*.???.encrypted"`.
  `-eq` does not do wildcards, so they match nothing.
- `2-find-delete-V2.ps1` logs to `$Deletedfile`, but the variable is `$Deleted`.
- `volrest /B` can return several versions; all of them are copied and the last one wins.
- `.trim("W:\")` removes the characters `W`, `:` and `\` from both ends of the path, not
  the prefix.
- `"$files.count"` inside a string prints the array, not the count.
- `rename-files.ps1` uses `$_` inside a `foreach` statement, where it is empty.
- Log names use `hh` (12-hour clock), so morning and evening runs collide.
