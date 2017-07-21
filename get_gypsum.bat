@echo off
cd %TMP%

rem Download the Pike installer and Gypsum's archive
rem http://superuser.com/a/760010
echo Downloading Pike...
powershell -command "& { (New-Object Net.WebClient).DownloadFile('http://pike.lysator.liu.se/pub/pike/all/7.8.866/Pike-v7.8.866-win32.msi', 'pike.msi') }"
echo Installing Pike - look for a wizard somewhere and maybe a permissions prompt
start /wait pike.msi
mkdir c:\Gypsum
mkdir c:\Gypsum\plugins
cd c:\Gypsum
echo Installing Gypsum - should be quick
powershell -command "& { (New-Object Net.WebClient).DownloadFile('http://rosuav.github.io/Gypsum/plugins/update.pike', 'plugins\update.pike') }"

plugins\update.pike

rem Create a shortcut. In theory, WindowStyle=7 should give a minimized window.
rem TODO: Find the desktop directory even if it isn't obvious.
rem TODO: Put a shortcut also into the Start menu? Does that require elevation?
rem (Shouldn't - not for per-user start menu at least.) Where should it be put?
echo Creating shortcut
powershell "$s=(New-Object -COM WScript.Shell).CreateShortcut('%userprofile%\Desktop\Gypsum.lnk');$s.TargetPath='c:\Gypsum\gypsum.pike';$s.WorkingDirectory='c:\Gypsum';$s.WindowStyle=7;$s.Save()"
