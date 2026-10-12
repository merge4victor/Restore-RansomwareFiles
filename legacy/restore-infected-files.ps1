#############################################################################################
#
# Author: Fatih Mergen
# Script: Restore Files from Shadow Copy and Delete infected/encrypted files
# FileName: Restore-Infected-Files.ps1
# Date: 18/02/2016
# Version: 1.0
#
#############################################################################################

$ErrorActionPreference = "Continue"
# Explicitly import module to make sure Microsoft.Experimental.IO assembly is loaded
$ExperimentalIOBinary = 'C:\Temp\Restore-Infected-Files\longpath\bin\Microsoft.Experimental.IO.dll'
[System.Reflection.Assembly]::LoadFile($ExperimentalIOBinary) | Out-Null

# Define function that allows recursive directory listing:
function Get-ChildItemLongPath {
    [CmdletBinding()]
    param(
        $Path = (Resolve-Path .),
        [switch] $Recurse
    )

    try {
        [Microsoft.Experimental.IO.LongPathDirectory]::EnumerateFileSystemEntries($Path) | ForEach-Object {
            $_
            if ($Recurse) {
                Get-ChildItemLongPath -Path $_ -Recurse
            }
        }
    }
    catch { 
        # Put error handling here. As the function is currently designed, any file paths passed will throw
        # an error b/c EnumerateFileSystemEntries() is meant to take folder paths
        if ($_.Exception.Message -notmatch "The directory name is invalid") {
            Write-Error $_ 
        }
    }
}

# Map Folder as Network Directory since this script doesnt work remote unc path due to PS Version 
$directory = "\\fileserver01\Share"

#$credential = Get-Credential "DOMAIN\admin-user"
#New-PSDrive -Name W -PSProvider FileSystem -Root $directory -Credential (get-credential)
net use W: $directory | out-null
start-sleep 1

#Log File Creation
$date = get-date -Format dd-MM-yyyy-hh-mm
$LogName = "test"
$LogFullName = $LogName+"_"+$Date
$Restorefile = "C:\Temp\Restore-Infected-Files\Restore_$LogFullName.txt"
$Failedfile = "C:\Temp\Restore-Infected-Files\NotRestored_$LogFullName.txt"
$FailedToDeletefile = "C:\Temp\Restore-Infected-Files\FailedtoDelete_$LogFullName.txt"
#clear-Content $outfile

$files = ""
$Files = @()

$Files = Get-ChildItemLongPath "W:\" -Recurse | where-object {($_ -like "*.???.mp3") -or ($_ -like "*.????.mp3")}

# Following Scripts are for Restoration
foreach ($file in $Files){
write-host $file
$FileInfoObject = Get-ChildItem -Literalpath $file 
#$FileInfoObject = [Microsoft.Experimental.IO.LongPathFile]::Equals($file)
$Filename = $fileInfoObject.Name
   $fail = $false

    $folder = $FileInfoObject.DirectoryName
    #write-host "folder:" $folder

    $fileBN = $FileInfoObject.basename
    #write-host "filebn:" $filebn

    $SCFilePath = join-path $folder $fileBN
    #write-host "SCFilePath:" $SCFilePath
    
    #Volrest toolkit is a must here to get clean shadow copy
    $OriginalFile = C:\Temp\Restore-Infected-Files\volrest.exe "$SCFilePath" /B
    #write-host "cleanFile:" $cleanFile

   try{
        # $x = Get-ChildItem $cleanFile
        Copy-Item -Path $OriginalFile -Destination $folder
        
    }
    catch{
        $Fail = $true
         }

    if ($fail -eq $false){
    write-output $($file)|out-file $Restorefile -force -append
    try{
        #Remove Encrypted Files
        $YakiFile = $directory+"\"+($FileInfoObject.FullName).trim("W:\")
        Remove-Item $YakiFile -Force
        #[Microsoft.Experimental.IO.LongPathFile]::Delete($YakiFile)
        }
        catch{
        #write-verbose "Failed to Delete File $YakiFile"
        write-output $($file)|out-file $FailedToDeletefile -force -append
        }
        }
    
    if ($fail -eq $true){
    write-output $($file) | out-file $Failedfile -force -append
    }

    #Write Log in Result File
    
}

#Delete Mapped Drive
net use /delete W: