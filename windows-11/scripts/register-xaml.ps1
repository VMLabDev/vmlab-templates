# vmlab: first-logon shell gate (Active Setup StubPath; explorer.exe waits
# for this to exit). Installed by the template's first-boot script because
# vmlab runs sysprep as Local System, which on 24H2/Server 2025 skips AppX
# registration for the XAML CBS packages — see
# https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/sysprep-as-system-windows-11
#
# Two jobs, both required (verified live 2026-07-17 on Server 2025):
#  1. Register the three CBS packages for this user, retrying until the AppX
#     deployment service accepts them (it refuses work in the first minute
#     or two after boot; the cmdlet succeeding is the completion signal).
#  2. Hold the shell until the machine is ~5 minutes past boot. A first
#     logon that lands earlier permanently breaks the new profile's shell
#     even WITH the packages registered (explorer fail-fasts, or never
#     launches) — the sysprep-as-SYSTEM damage reaches beyond those three
#     packages, and post-boot servicing needs time to settle. Profiles
#     created after this gate get a working desktop; later logons of the
#     same user skip this stub entirely (Active Setup runs once per user).
$apps = @(
  'MicrosoftWindows.Client.CBS_cw5n1h2txyewy',
  'Microsoft.UI.Xaml.CBS_8wekyb3d8bbwe',
  'MicrosoftWindows.Client.Core_cw5n1h2txyewy'
) | Where-Object { Test-Path ('C:\Windows\SystemApps\' + $_ + '\appxmanifest.xml') }
foreach ($a in $apps) {
  for ($i = 0; $i -lt 36; $i++) {
    try {
      Add-AppxPackage -Register -Path ('C:\Windows\SystemApps\' + $a + '\appxmanifest.xml') -DisableDevelopmentMode -ErrorAction Stop
      break
    } catch {
      Start-Sleep -Seconds 5
    }
  }
}
$uptime = ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds
if ($uptime -lt 300) { Start-Sleep -Seconds ([int](300 - $uptime)) }
exit 0
