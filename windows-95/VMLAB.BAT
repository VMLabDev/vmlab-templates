@echo off
rem vmlab: stage C: and start Setup from the patched install files.
echo vmlab: staging Setup
c:
md c:\vmlab
for %%d in (x y z) do if exist %%d:\vmlabsrc.txt copy %%d:\vmlabagt.exe c:\vmlab
rem The patched \WIN95 is on the VMLABSRC CD, whichever letter MSCDEX gave it
rem (X: is the install CD itself, without the marker).
for %%d in (x y z) do if exist %%d:\vmlabsrc.txt a:\xcopy %%d:\win95\*.* c:\win95\ >nul
cd \win95
setup b:\msbatch.inf /is /iq /id
