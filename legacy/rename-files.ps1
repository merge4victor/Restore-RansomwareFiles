$files = Get-Content "C:\temp\Restore-Infected-Files\NotRestored_Data_25-02-2016-05-07.txt"

<#gci 'c:\test\' -Recurse | % { Rename-Item $_.FullName $($_.Name -replace
	'[^\w\.]','') }
#>

foreach ($file in $files)
    { 
        $RealFile = gci -LiteralPath $file
        Rename-Item $_.FullName $($RealFile.Name -replace '[^\w\.]','') 
    }

    #rename single File
   
    $file = "W:\Department\Folder\Report.pdf.mp3"
    $RealFile = gci -LiteralPath $file
    Rename-Item $RealFile.FullName $($RealFile.Name -replace '[^\w\.]','') 
    