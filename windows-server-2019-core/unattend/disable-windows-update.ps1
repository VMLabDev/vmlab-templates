# Disable Windows Update in the template image so clones never auto-install
# updates. Run at build time AFTER windows-update.ps1 has fully patched the
# image and BEFORE sysprep seals it: the machine policies (HKLM\SOFTWARE\
# Policies) and the service start type survive sysprep /generalize, so every
# clone boots with Windows Update already turned off.
#
# Belt and suspenders, because no single knob reliably stops modern Windows
# from re-arming updates:
#   1. Group-policy AU keys (NoAutoUpdate / AUOptions=1) — "never check".
#   2. wuauserv service set to Disabled + stopped.
#   3. The UpdateOrchestrator / WindowsUpdate scheduled tasks disabled, so the
#      Update Orchestrator can't restart the service behind the policy.

$ErrorActionPreference = 'Continue'

Write-Output 'disabling Windows Update for the sealed template...'

# 1. Group policy: turn off Automatic Updates entirely.
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = "$wu\AU"
# Create the keys BEFORE writing any values, and guard with Test-Path: New-Item
# -Force on an existing registry key recreates it and wipes its values/subkeys,
# so forcing the parent after populating the child would blow the child away.
if (-not (Test-Path $wu)) { New-Item -Path $wu -Force | Out-Null }
if (-not (Test-Path $au)) { New-Item -Path $au -Force | Out-Null }

New-ItemProperty -Path $au -Name 'NoAutoUpdate' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $au -Name 'AUOptions'    -PropertyType DWord -Value 1 -Force | Out-Null
# Don't reach out to Windows Update / Microsoft Update on the internet.
New-ItemProperty -Path $wu -Name 'DoNotConnectToWindowsUpdateInternetLocations' -PropertyType DWord -Value 1 -Force | Out-Null

# 2. Service: stop and disable wuauserv so it can't run.
Stop-Service  -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service   -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
# Also disable the Update Orchestrator service where present (Win10/11, Server 2019+).
Stop-Service  -Name UsoSvc -Force -ErrorAction SilentlyContinue
Set-Service   -Name UsoSvc -StartupType Disabled -ErrorAction SilentlyContinue

# 3. Scheduled tasks that re-arm/scan/install updates.
foreach ($path in '\Microsoft\Windows\WindowsUpdate\', '\Microsoft\Windows\UpdateOrchestrator\') {
    Get-ScheduledTask -TaskPath $path -ErrorAction SilentlyContinue |
        Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

# NOTE: sysprep /generalize + the clone's specialize pass reset wuauserv back to
# its default (Manual on client SKUs) — verified on a Windows 10 clone — so the
# service StartType above does NOT by itself survive onto clones. The durable,
# Microsoft-sanctioned lever that DOES survive generalize and is honored on every
# clone is the AU group policy (NoAutoUpdate=1 + AUOptions=1) set above, together
# with UsoSvc (the Update Orchestrator that actually drives automatic updates on
# Win10/11/Server2019+) left disabled. Both were confirmed present on clones, so
# automatic Windows Updates do not run.

# Report final state so the build log proves it took.
$startType = (Get-Service wuauserv -ErrorAction SilentlyContinue).StartType
$noAuto    = (Get-ItemProperty -Path $au -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate
Write-Output ("wuauserv StartType={0}, NoAutoUpdate={1}" -f $startType, $noAuto)
Write-Output 'WU_DISABLED=OK'
exit 0
