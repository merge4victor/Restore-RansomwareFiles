@{
    RootModule           = 'RansomwareRecovery.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '2580693f-713f-40cb-bd22-1456c1eeeb77'
    Author               = 'Fatih Mergen'
    Copyright            = '(c) 2016-2026 Fatih Mergen. MIT License.'
    Description          = 'Finds files encrypted by ransomware and restores the clean originals from Volume Shadow Copies or SMB previous versions.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Find-EncryptedFile'
        'Get-ShadowSnapshot'
        'Invoke-RansomwareRecovery'
        'Restore-EncryptedFile'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Ransomware', 'Cryptolocker', 'ShadowCopy', 'VSS', 'PreviousVersions', 'Recovery', 'IncidentResponse', 'Windows')
            LicenseUri = 'https://github.com/merge4victor/Restore-RansomwareFiles/blob/main/LICENSE'
            ProjectUri = 'https://github.com/merge4victor/Restore-RansomwareFiles'
        }
    }
}
