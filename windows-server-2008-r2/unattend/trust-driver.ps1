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
    Export-Certificate -Cert $cert -FilePath $cer | Out-Null
    certutil -addstore -f Root $cer
    certutil -addstore -f TrustedPublisher $cer
    Write-Output "trusted $($cert.Subject)"
}
exit 0
