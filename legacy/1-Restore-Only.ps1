#############################################################################################
#
# Author: Fatih Mergen
# Script: Restore Files from Shadow Copy and Delete infected/encrypted files
# FileName: Restore-Only.ps1
# Date: 18/02/2016
# Version: 1.0
#
#############################################################################################
#Timing Starts
$start =get-date

#Error Action
$ErrorActionPreference = "Continue"

#Moving Log files under OldLogs folder
$Path = "C:\temp\Restore-Infected-Files"
$OldLogPath  = "C:\temp\Restore-Infected-Files\OldLogs"
Get-ChildItem -Path $Path\*.txt -Recurse | Move-Item -Destination $OldLogPath -Force

#Log File Creation
$date = get-date -Format dd-MM-yyyy-hh-mm
$LogName = "Groups"
$LogFullName = $LogName+"_"+$Date
$Restoredfile = New-Item -type file -force "C:\Temp\Restore-Infected-Files\Restored_$LogFullName.txt"
$Failedfile = New-Item -type file -force "C:\Temp\Restore-Infected-Files\NotRestored_$LogFullName.txt"
$FailedToDeletefile = New-Item -type file -force "C:\Temp\Restore-Infected-Files\FailedtoDelete_$LogFullName.txt"
$Nsuccess = 0
$Nfailure = 0
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
            #Write-Error $_ 
            Write-Error "Access Denied"
        }
    }
}

# Map Folder as Network Directory "W: Drive "since this script doesnt work remote unc path due to PS Version 
$directory = "Infected"

#$credential = Get-Credential
#New-PSDrive -Name W -PSProvider FileSystem -Root $directory -Credential (get-credential)
#net use W: $directory | out-null
#start-sleep 1


#clear-Content $outfile
$files = ""
$Files = @()

$Files = Get-ChildItemLongPath "W:\" -Recurse | where-object {($_ -eq "*.??.encrypted") -or ($_ -eq "*.???.encrypted") -or ($_ -eq "*.????.encrypted")}
write-host "Total Files :" $files.Count
write-host "`n`n"

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
        Copy-Item -LiteralPath $OriginalFile -Destination $folder
      }
    catch{
        #Write Log in Result File
        write-output $($file) | out-file $Failedfile -force -append
        $Nfailure++
        $Fail = $true
         }

    if ($fail -eq $false){
    #Write Log in Result File
    write-output $($file) | out-file $Restoredfile -force -append
    $Nsuccess++
<#
#Removing Files is splitted into another PowerShell File due to business requirement. Find-delete.ps1 script is finding and deleting garbage files.
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
#>
        }
    
    
    
}

#Delete Mapped Drive
#net use /delete W:

$end=Get-Date
$ExecTime = [math]::Round(($end-$start).TotalMinutes,2)

$Total = ""
$Total = $files.Count

#Send Email to Windows Team for Backup Report
$SmtpServer = "smtp.example.com"
$FromEmail = "restore-script@example.com"
$ToEmail = "windows-team@example.com"
$Subject = "Crypto Restore Logs"
$body = "Hi All,`n`n Folder $logname restoration has finished ($Nsuccess files restored,$Nfailure failed to restore) and it took $ExecTime minutes (Start: $start , Finish: $end).`n`nThere are failed restorations as logged in NotRestored Attachment file. Please check the attachment in this email.`n`nWintel Automation"
$Attachment1 = $Restoredfile
$Attachment2 = $Failedfile

#Send the E-mail

Send-MailMessage -SmtpServer $SmtpServer -from $FromEmail -To $Toemail -Subject $Subject -Body $body -Attachments $Attachment1,$Attachment2