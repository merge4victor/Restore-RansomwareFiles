#############################################################################################
#
# Author: Fatih Mergen
# Script: Delete infected/encrypted files from Shared Drive
# FileName: Find-Delete.ps1
# Date: 18/02/2016
# Version: 1.0 Initial Version
#
#############################################################################################
#Timing Starts
$start =get-date

$ExperimentalIOBinary = 'C:\Temp\Restore-Infected-Files\longpath\bin\Microsoft.Experimental.IO.dll'
[System.Reflection.Assembly]::LoadFile($ExperimentalIOBinary) | Out-Null
#$Badfile = "Recovery+gjkin.*"

#$path = "\\fileserver01\Share\Department\Folder\"

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
            Write-Error $_ 
        }
    }
}

#finding encrypted files 


$files = Get-ChildItemLongPath "W:\" -Recurse | where-object {$_ -like "*.???.mp3" -or $_ -like "*.????.mp3"}
foreach ($file in $files){
        "Deleting file: " + $file
        [Microsoft.Experimental.IO.LongPathFile]::Delete($file)
}


#finding malicious decryption instruction files
$badfiles = Get-ChildItemLongPath "W:\" -Recurse | where-object {$_ -like "*gjkin.*"}
foreach ($badfile in $badfiles){
        "Deleting Bad file: " + $badfile
        [Microsoft.Experimental.IO.LongPathFile]::Delete($badfile)
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

write-host "Total Encrypted Files have been deleted: " $files.count
write-host "Total Dummy Files have been deleted: " $Badfiles.count


$end=Get-Date
$ExecTime = ($end-$start).totalminutes

#Send Email to Windows Team for Backup Report
$SmtpServer = "smtp.example.com"
$FromEmail = "restore-script@example.com"
$ToEmail = "windows-team@example.com"
$Subject = "Crypto Restore Logs"
$body = "Hi All,`n`n Folder $logname restoration has finished ($files.count Files) and it took $ExecTime minutes (Start: $start , Finish: $end).`n`nThere are failed restorations as logged in NotRestored Attachment file. Please check the attachment in this email.`n`nWintel Automation"
$Attachment1 = $Failedfile
$Attachment2 = $Restorefile

#Send the E-mail if the DNS Backup was Successfull

Send-MailMessage -SmtpServer $SmtpServer -from $FromEmail -To $Toemail -Subject $Subject -Body $body -Attachments $Attachment1,$Attachment2