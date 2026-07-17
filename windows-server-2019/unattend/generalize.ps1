# Generalize this Windows image with sysprep, retrying past AppX
# "installed for a user but not provisioned" blockers.
#
# Why this is not just `sysprep /generalize`:
#   * On modern Windows codebases, sysprep /generalize aborts with
#     0x80073cf2 if any AppX package is installed for a user but not provisioned
#     for all users. Consumer packages (WindowsFeedbackHub, WindowsTerminal, ...)
#     register for the Administrator profile ASYNCHRONOUSLY after first logon, so
#     a one-shot pre-strip races them and misses whichever hasn't finished yet.
#   * sysprep.exe detaches and returns an unreliable exit code (0 even when it
#     aborts), so success must be judged by the Sysprep_succeeded.tag it writes
#     only on a clean generalize.
#   * We must NOT blanket-deprovision: a provisioned-but-not-installed package is
#     fine, but deprovisioning a package we then fail to remove per-user (e.g.
#     DesktopAppInstaller / winget, which is un-removable, 0x80070032) CREATES the
#     very mismatch we're trying to avoid.
#
# So: run sysprep, and each time it aborts on an AppX blocker, remove exactly the
# package it named (per-user, all users — no deprovisioning) and retry. The
# blocker is named only once it is fully registered, so the loop converges.

$ErrorActionPreference = 'Continue'
$sp       = 'C:\Windows\System32\Sysprep'
# Absolute, NOT $env:TEMP: install.ws stages the file into C:\Windows\Temp,
# but this script now runs as Administrator (sysprep must not run as Local
# System), whose $env:TEMP is the profile-local temp dir.
$unattend = 'C:\Windows\Temp\sysprep-unattend.xml'
$tag      = Join-Path $sp 'Sysprep_succeeded.tag'
$log      = Join-Path $sp 'Panther\setupact.log'

# Settle main packages staged for no user and not provisioned — after the
# Windows Update run, 24H2's "Last Known Good" shell fallbacks
# (MicrosoftWindows.LKG.*) sit staged at the base version, and their pending
# reconciliation otherwise fires during a clone's first profile-creating logon
# and fail-fasts explorer.exe (vmlab-templates#1, second act). System apps
# refuse removal — the attempt alone consumes the pending work, so log the
# outcome either way and never fail the build over it. Staged packages never
# block sysprep, so this cannot be gated on the sysprep tag; the inventory in
# the build log is the detection.
$prov = (Get-AppxProvisionedPackage -Online).DisplayName
Get-AppxPackage -AllUsers | Where-Object {
    -not $_.IsFramework -and -not $_.IsResourcePackage -and
    $prov -notcontains $_.Name -and
    -not ($_.PackageUserInformation | Where-Object InstallState -eq 'Installed')
} | ForEach-Object {
    $r = 'removed'
    try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
    catch { $r = 'settled (system app, left staged)' }
    Write-Output ("pre-sysprep appx: {0}: {1}" -f $r, $_.PackageFullName)
}

# Client SKUs (Windows 10/11) carry many more consumer AppX packages than Server,
# so allow plenty of passes; each failed pass is a fast validate-only abort.
$prev = ''
for ($i = 0; $i -lt 25; $i++) {
    Remove-Item $tag -ErrorAction SilentlyContinue
    Start-Process "$sp\sysprep.exe" -Wait -ArgumentList @(
        '/generalize', '/oobe', '/quit', '/quiet', "/unattend:$unattend"
    )
    if (Test-Path $tag) { Write-Output "sysprep generalized on pass $i"; exit 0 }

    $blocker = Get-Content $log |
        Select-String 'Package (\S+) was installed for a user' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } |
        Select-Object -Unique -Last 1
    if (-not $blocker) {
        Write-Output 'sysprep failed for a non-AppX reason; last errors:'
        Get-Content $log | Select-String 'Error' | Select-Object -Last 10 |
            ForEach-Object { $_.Line }
        exit 1
    }
    $name = ($blocker -split '_')[0]
    # If the same package blocks twice running, our removal isn't sticking (an
    # un-removable package we must not have deprovisioned) — bail rather than spin.
    if ($name -eq $prev) {
        Write-Output "AppX blocker $name still present after removal; aborting"
        exit 1
    }
    $prev = $name
    Write-Output ("pass {0}: removing AppX blocker {1}" -f $i, $name)
    Get-AppxPackage -AllUsers $name | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
}

Write-Output 'sysprep still failing after removing AppX blockers; last errors:'
Get-Content $log | Select-String 'Error' | Select-Object -Last 10 |
    ForEach-Object { $_.Line }
exit 1
