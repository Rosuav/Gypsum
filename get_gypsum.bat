cd %TMP%

rem Download the Pike installer and Gypsum's archive
rem http://superuser.com/a/760010
powershell -command "& { (New-Object Net.WebClient).DownloadFile('http://pike.lysator.liu.se/pub/pike/all/7.8.866/Pike-v7.8.866-win32.msi', 'pike.msi') }"
start pike.msi
powershell -command "& { (New-Object Net.WebClient).DownloadFile('https://github.com/Rosuav/Gypsum/archive/master.zip', 'gypsum.zip') }"

rem Unzip Gypsum into a convenient directory
rem http://stackoverflow.com/a/26843122/1236787
powershell -command "& { Add-Type -A 'System.IO.Compression.FileSystem'; [IO.Compression.ZipFile]::ExtractToDirectory('gypsum.zip', 'c:\'); }"
ren c:\gypsum-master Gypsum

rem Create a shortcut. In theory, WindowStyle=7 should give a minimized window.
rem TODO: Find the desktop directory even if it isn't obvious.
powershell "$s=(New-Object -COM WScript.Shell).CreateShortcut('%userprofile%\Desktop\Gypsum.lnk');$s.TargetPath='c:\Gypsum\gypsum.pike';$s.WorkingDirectory='c:\Gypsum';$s.WindowStyle=7;$s.Save()"
