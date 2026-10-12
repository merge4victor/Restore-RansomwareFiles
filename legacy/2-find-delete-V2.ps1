#############################################################################################
#
# Author: Fatih Mergen
# Script: Delete infected/encrypted files from Shared Drive
# FileName: Find-Delete.ps1
# Date: 18/02/2016
# Version: 1.0 Initial Version
#          2.0 Timing and Email function Added
#
#############################################################################################

#Timing Starts
$start =get-date
get-date

#Error Action
$ErrorActionPreference = "Continue"

#Moving Log files under OldLog to make main folder more clear
$Path = "C:\temp\Restore-Infected-Files"
$OldLogPath  = "C:\temp\Restore-Infected-Files\OldLogs"
Get-ChildItem -Path $Path\*.txt -Recurse | Move-Item -Destination $OldLogPath -Force

#Logging
$date = get-date -Format dd-MM-yyyy-hh-mm
$LogName = "Groups"
$LogFullName = $LogName+"_"+$Date
$Deleted = New-Item -type file -force "C:\Temp\Restore-Infected-Files\Deleted_$LogFullName.txt"
$FailedtoDelete = New-Item -type file -force "C:\Temp\Restore-Infected-Files\Failed_Delete_$LogFullName.txt"

$ExperimentalIOBinary = 'C:\Temp\Restore-Infected-Files\longpath\bin\Microsoft.Experimental.IO.dll'
[System.Reflection.Assembly]::LoadFile($ExperimentalIOBinary) | Out-Null
#$Badfile = "Recovery+gjkin.*"

#New-PSDrive -Name W -PSProvider FileSystem -Root $path 
#net use W: $path | out-null
start-sleep 1

#Find files function
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

#finding encrypted files 
$files = Get-ChildItemLongPath "W:\" -Recurse | where-object {($_ -eq "*.??.mp3") -or ($_ -eq "*.???.mp3") -or ($_ -eq "*.????.mp3") -or ($_ -eq "HOW_TO_RESTORE_FILES.*")}
foreach ($file in $files){
try{
        "Deleting file: " + $file
        [Microsoft.Experimental.IO.LongPathFile]::Delete($file)
        write-output $($file) | out-file $Deletedfile -force -append
        }
catch{
        write-output $($file) | out-file $FailedtoDelete -Append
        }
}

<#
#param($path)

function DeleteAllFilesRecursive($path){
    "Getting folders in folder: " + $path
    $subfolders = [Microsoft.Experimental.IO.LongPathDirectory]::EnumerateDirectories($path)
    foreach ($subfolder in $subfolders)
    {
        "Recursing folder: " + $subfolder
        DeleteAllFilesRecursive($subfolder)
        "Deleting folder: " + $subfolder
        [Microsoft.Experimental.IO.LongPathDirectory]::Delete($subfolder)
    }
 
    $files = [Microsoft.Experimental.IO.LongPathDirectory]::EnumerateFiles($path)
    foreach ($file in $files)
    {
        "Deleting file: " + $file
        [Microsoft.Experimental.IO.LongPathFile]::Delete($file,"*.mp3")
    }
}
 
DeleteAllFilesRecursive $folder
"Deleting folder: " + $folder
[Microsoft.Experimental.IO.LongPathDirectory]::Delete($folder)

#>


#Delete Mapped Drive
#net use /delete W:  | Out-Null
#Remove-PSDrive W -Force

#Count Lines in Txt file
<#$lines = 0
Get-Content C:\temp\Restore-Infected-Files\Groups_Folder_Cleanup.txt |%{ $lines++ }
$lines
#>

write-host "Total Files have been deleted: " $files.count
Write-Host "`n" Get-Date
Write-Host "`n"
Write-Host "Email has been sent to windows-team@example.com"

$Total = ""
$Total = ($files.Count)
$end=Get-Date
$ExecTime = [math]::Round(($end-$start).TotalMinutes,2)
#Send Email to Windows Team for Backup Report
$SmtpServer = "smtp.example.com"
$FromEmail = "restore-script@example.com"
$ToEmail = "windows-team@example.com"
$Subject = "Deleted Files"
$body = "Hi All,`n`n Folder File Deletion has just finished and $total Files has been deleted from File Server. It took $ExecTime minutes (Start: $start , Finish: $end).`n`nWintel Automation"
$attachment1 = $Deletedfile
$attachment2 = $FailedtoDelete

#Send the E-mail
Send-MailMessage -SmtpServer $SmtpServer -from $FromEmail -To $Toemail -Subject $Subject -Body $body -Attachments $attachment1,$attachment2