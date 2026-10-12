BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\RansomwareRecovery\RansomwareRecovery.psd1') -Force
}

Describe 'ConvertFrom-GmtToken' {
    It 'parses an @GMT token as UTC' {
        InModuleScope RansomwareRecovery {
            $time = ConvertFrom-GmtToken -Token '@GMT-2016.02.18-13.05.09'

            $time.Kind | Should -Be 'Utc'
            $time | Should -Be ([datetime]::new(2016, 2, 18, 13, 5, 9, [DateTimeKind]::Utc))
        }
    }
}

Describe 'Resolve-VolumeLocation' {
    BeforeAll {
        Mock -ModuleName RansomwareRecovery Get-LocalVolume {
            [pscustomobject]@{ Name = 'C:\'; DeviceID = '\\?\Volume{c}\' }
            [pscustomobject]@{ Name = 'C:\Mount\Data\'; DeviceID = '\\?\Volume{data}\' }
        }
        Mock -ModuleName RansomwareRecovery Get-NetworkDriveRoot { $null }
        Mock -ModuleName RansomwareRecovery Get-NetworkDriveRoot { '\\fileserver\share' } -ParameterFilter { $DriveLetter -eq 'W:' }
    }

    It 'splits a UNC path into share root and relative path' {
        InModuleScope RansomwareRecovery {
            $location = Resolve-VolumeLocation -Path '\\fileserver\share\dir\file.docx'

            $location.Kind | Should -Be 'Smb'
            $location.Root | Should -Be '\\fileserver\share'
            $location.RelativePath | Should -Be 'dir\file.docx'
        }
    }

    It 'strips the \\?\UNC\ long-path prefix' {
        InModuleScope RansomwareRecovery {
            $location = Resolve-VolumeLocation -Path '\\?\UNC\fileserver\share\file.docx'

            $location.Root | Should -Be '\\fileserver\share'
            $location.RelativePath | Should -Be 'file.docx'
        }
    }

    It 'translates a mapped network drive to its share' {
        InModuleScope RansomwareRecovery {
            $location = Resolve-VolumeLocation -Path 'W:\dir\file.docx'

            $location.Kind | Should -Be 'Smb'
            $location.Root | Should -Be '\\fileserver\share'
            $location.RelativePath | Should -Be 'dir\file.docx'
        }
    }

    It 'picks the most specific local mount point' {
        InModuleScope RansomwareRecovery {
            $location = Resolve-VolumeLocation -Path 'C:\Mount\Data\dir\file.docx'

            $location.Kind | Should -Be 'Local'
            $location.Root | Should -Be '\\?\Volume{data}\'
            $location.RelativePath | Should -Be 'dir\file.docx'
        }
    }

    It 'handles a \\?\ prefixed local path' {
        InModuleScope RansomwareRecovery {
            $location = Resolve-VolumeLocation -Path '\\?\C:\Users\file.docx'

            $location.Root | Should -Be '\\?\Volume{c}\'
            $location.RelativePath | Should -Be 'Users\file.docx'
        }
    }
}

Describe 'Move-ToQuarantine' {
    It 'keeps the drive and folder structure under the quarantine root' {
        InModuleScope RansomwareRecovery {
            $source = Join-Path $TestDrive 'live\dir\file.docx.locked'
            New-Item -ItemType File -Path $source -Force | Out-Null
            $quarantine = Join-Path $TestDrive 'quarantine'

            $destination = Move-ToQuarantine -Path $source -QuarantineRoot $quarantine

            $destination | Should -Be (Join-Path $quarantine ($source -replace ':', ''))
            $destination | Should -Exist
            $source | Should -Not -Exist
        }
    }
}
