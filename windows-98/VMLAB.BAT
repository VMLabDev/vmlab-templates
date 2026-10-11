@echo off
rem vmlab: stage C: and start Setup from the patched install files.
echo vmlab: staging Setup
c:
md c:\vmlab
copy b:\boot.bat c:\vmlab
md c:\win98
rem The patched \WIN98 is on the VMLABSRC CD, whichever letter MSCDEX gave it
rem (D: is the install CD itself, without the marker).
for %%d in (d e f g h i j) do if exist %%d:\vmlabsrc.txt copy %%d:\win98\*.* c:\win98 >nul
cd \win98
setup b:\msbatch.inf /is /iq /im /ie /iv /nm
