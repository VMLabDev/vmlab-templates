# Trust the virtio driver's publisher, so pnputil installs it without the
# prompt no one is here to answer. The certificate comes out of the driver's
# own catalog, so nothing is trusted that the driver did not already carry.
#
# A file rather than an inline -Command: the same logic as a one-liner inside
# an XML attribute needs three layers of quoting, and a PowerShell that
# mis-parses its arguments waits for input on stdin — which in a synchronous
# FirstLogonCommand hangs the whole build, silently, at a black screen.
$ErrorActionPreference = 'Continue'
foreach ($d in 'D','E','F','G','H') {
    $cat = "${d}:\drivers\vioserial\vioser.cat"
    if (-not (Test-Path $cat)) { continue }
    $cert = (Get-AuthenticodeSignature $cat).SignerCertificate
    if (-not $cert) { Write-Output "no signer on $cat"; continue }
    $cer = Join-Path $env:TEMP 'vioser.cer'
    # Export-Certificate is a PowerShell 3.0 cmdlet; Windows 7 and Server
    # 2008 R2 ship 2.0, where this line threw and left the publisher
    # untrusted — so pnputil put up "Windows can't verify the publisher
    # of this driver software" and the unattended build sat on it (Server
    # 2008 R2, 2026-09-05: an hour, until the dialog was clicked by hand).
    # The certificate exports itself on every version we build.
    [IO.File]::WriteAllBytes($cer, $cert.Export('Cert'))
    certutil -addstore -f Root $cer
    certutil -addstore -f TrustedPublisher $cer
    Write-Output "trusted $($cert.Subject)"
}
exit 0
