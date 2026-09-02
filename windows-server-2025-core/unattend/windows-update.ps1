# Install all available Windows Updates, one search/download/install pass.
#
# Run at template-build time (BEFORE sysprep) so the sealed image — and every
# clone of it — ships fully patched. We use the Windows Update COM API
# (Microsoft.Update.Session) directly rather than the PSWindowsUpdate module so
# nothing has to be installed first, and we run as the guest agent's LocalSystem
# account (no interactive logon required).
#
# This is ONE pass on purpose: updates that need a reboot, or that only become
# applicable after an earlier wave installs, won't all appear in a single
# search. The caller (install.ws) reboots and re-runs us until we report
# WU_RESULT=NONE. The last line of stdout is always a sentinel the caller parses:
#
#   WU_RESULT=NONE        no applicable updates remain   -> caller stops looping
#   WU_RESULT=INSTALLED   updates installed this pass     -> caller reboots + re-runs
#   WU_RESULT=FAILED      search/download/install errored -> caller retries/​warns
#
# The reboot is left to the caller so the guest-agent reconnect is observed and
# pending-rename operations settle before the next search.

$ErrorActionPreference = 'Stop'

try {
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()

    Write-Output 'searching for applicable updates...'
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0")

    if ($result.Updates.Count -eq 0) {
        Write-Output 'no applicable updates found'
        Write-Output 'WU_RESULT=NONE'
        exit 0
    }

    $wanted = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $result.Updates) {
        # Skip updates that demand interactive EULA/UI we can't satisfy headless.
        if ($u.InstallationBehavior.CanRequestUserInput) {
            Write-Output ("  skip (needs user input): {0}" -f $u.Title)
            continue
        }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        $wanted.Add($u) | Out-Null
        Write-Output ("  queued: {0}" -f $u.Title)
    }

    if ($wanted.Count -eq 0) {
        Write-Output 'only user-input updates remain; nothing to install headless'
        Write-Output 'WU_RESULT=NONE'
        exit 0
    }

    Write-Output ("downloading {0} update(s)..." -f $wanted.Count)
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $wanted
    $dl = $downloader.Download()
    Write-Output ("download result code: {0}" -f $dl.ResultCode)

    # Install only what actually downloaded.
    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $wanted) { if ($u.IsDownloaded) { $ready.Add($u) | Out-Null } }
    if ($ready.Count -eq 0) {
        Write-Output 'nothing downloaded successfully'
        Write-Output 'WU_RESULT=FAILED'
        exit 1
    }

    Write-Output ("installing {0} update(s)..." -f $ready.Count)
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $ready
    $ir = $installer.Install()
    Write-Output ("install result code: {0}, reboot required: {1}" -f $ir.ResultCode, $ir.RebootRequired)

    Write-Output 'WU_RESULT=INSTALLED'
    exit 0
}
catch {
    Write-Output ("windows update error: " + $_.Exception.Message)
    Write-Output 'WU_RESULT=FAILED'
    exit 1
}
