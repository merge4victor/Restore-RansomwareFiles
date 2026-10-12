BeforeDiscovery {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $canRun = $env:RR_INTEGRATION -eq '1' -and $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Describe 'Recovery from a real shadow copy' -Tag Integration -Skip:(-not $canRun) {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '..\src\RansomwareRecovery\RansomwareRecovery.psd1') -Force

        $root = 'C:\RRIntegration'
        $data = Join-Path $root 'data'
        $quarantine = Join-Path $root 'quarantine'
        $shareName = 'RRIntegration'
        $share = "\\localhost\$shareName"

        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path "$data\finance" -Force | Out-Null
        Set-Content "$data\finance\budget.xlsx" 'clean budget' -NoNewline
        Set-Content "$data\finance\report.docx" 'clean report' -NoNewline

        $created = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{ Volume = 'C:\'; Context = 'ClientAccessible' }
        $created.ReturnValue | Should -Be 0
        $shadowId = $created.ShadowID
        Start-Sleep -Seconds 2

        foreach ($name in 'budget.xlsx', 'report.docx') {
            Set-Content "$data\finance\$name" 'ENCRYPTED' -NoNewline
            Rename-Item "$data\finance\$name" "$name.locked"
        }
        Set-Content "$data\finance\HOW_TO_DECRYPT.txt" 'pay up'

        New-SmbShare -Name $shareName -Path $data -FullAccess "$env:USERDOMAIN\$env:USERNAME" | Out-Null
    }

    AfterAll {
        Remove-SmbShare -Name $shareName -Force -ErrorAction SilentlyContinue
        Get-CimInstance Win32_ShadowCopy | Where-Object ID -EQ $shadowId | Remove-CimInstance
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'lists the shadow copy for the local volume' {
        Get-ShadowSnapshot -Path $data | Where-Object Id -EQ $shadowId | Should -Not -BeNullOrEmpty
    }

    It 'lists @GMT snapshots through the SMB share' {
        $snapshots = @(Get-ShadowSnapshot -Path $share)

        $snapshots.Count | Should -BeGreaterThan 0
        $snapshots[0].SnapshotRoot | Should -BeLike "$share\@GMT-*"
    }

    It 'restores over SMB' {
        $result = Find-EncryptedFile -Path $share -EncryptedExtension .locked |
            Where-Object Path -Like '*budget*' |
            Restore-EncryptedFile

        $result.Status | Should -Be 'Restored'
        Get-Content "$data\finance\budget.xlsx" -Raw | Should -Be 'clean budget'
    }

    It 'restores locally and quarantines what is left' {
        $summary = Invoke-RansomwareRecovery -Path $data -EncryptedExtension .locked -RansomNotePattern 'HOW_TO_*' `
            -QuarantinePath $quarantine -LogPath $root

        $summary.Restored | Should -Be 1
        $summary.AlreadyExists | Should -Be 1
        Get-Content "$data\finance\report.docx" -Raw | Should -Be 'clean report'
        "$data\finance\report.docx.locked" | Should -Not -Exist
        "$data\finance\HOW_TO_DECRYPT.txt" | Should -Not -Exist
        "$quarantine\C\RRIntegration\data\finance\report.docx.locked" | Should -Exist
        $summary.LogFile | Should -Exist
    }
}
