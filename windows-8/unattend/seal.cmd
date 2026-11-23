@echo off
net accounts /maxpwage:unlimited
for %%d in (D E F G H) do if exist %%d:\install-nt.cmd (
    call %%d:\install-nt.cmd
    if errorlevel 1 exit /b 1
    goto sysprep
)
exit /b 1

:sysprep
copy /y "%~dp0sysprep-unattend.xml" "%WINDIR%\Temp\sysprep-unattend.xml" || exit /b 1
%WINDIR%\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /quiet /unattend:%WINDIR%\Temp\sysprep-unattend.xml
