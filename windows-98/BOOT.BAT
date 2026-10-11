@echo off
rem vmlab: install the legacy agent from the VMLAB bootstrap ISO, whichever
rem drive letter it landed on. Runs before logon from RunServices at every
rem boot, and does nothing once the agent is installed.
if exist c:\vmlab\vmlabagt.exe goto end
for %%d in (d e f g h i j k) do if exist %%d:\install-9x.bat call %%d:\install-9x.bat
:end
