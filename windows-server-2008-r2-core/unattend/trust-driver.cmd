@echo off
rem Trust the virtio driver's publisher, so pnputil installs it without the
rem prompt no one is here to answer. fetch-deps.sh takes the certificate out
rem of the driver's own catalog, so nothing is trusted that the driver did not
rem already carry.
rem
rem A batch file with a certificate staged on the host, where the sibling
rem templates run trust-driver.ps1: Server Core on 2008 R2 installs without
rem PowerShell (it is an optional feature there), so the script never ran,
rem the publisher stayed untrusted, and pnputil put up "Would you like to
rem install this device software?" (2026-11-23: the build sat on it).
for %%d in (D E F G H) do if exist %%d:\drivers\vioserial\vioser.cer (
    certutil -addstore -f Root %%d:\drivers\vioserial\vioser.cer
    certutil -addstore -f TrustedPublisher %%d:\drivers\vioserial\vioser.cer
)
exit /b 0
