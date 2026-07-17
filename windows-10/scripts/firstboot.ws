// First-boot provision for sysprep-generalized Windows templates (PRD §6.1).
//
// These templates are sysprep-generalized, so every clone replays the
// specialize/OOBE pass on first boot. The QEMU guest agent survives generalize
// and can answer guest-ping WHILE specialize is still running — too early to
// treat the VM as ready. sysprep-unattend.xml writes the marker
// C:\Windows\Temp\vmlab-firstboot.done from a specialize-pass command (as
// SYSTEM, no logon needed) once that first boot genuinely finishes. vmlab runs
// this script before reporting the VM ready: wait for the marker, delete it,
// reboot the clone once, and only then return. The VM operated on is the clone
// this provision gates — reached with lab.this_vm().
//
// The extra reboot matters: on Server 2025 the "Last Known Good" shell packages
// are reconciled during this first-boot specialize pass, and the first
// interactive logon that lands before that fully settles leaves per-user AppX
// state broken — explorer.exe then fail-fasts (0xc0000409 / BEX64). A single
// reboot after specialize completes lets the reconciliation finish on a clean
// boot, so the first logon builds a working profile. (github.com/wiltaylor/
// vmlab-templates#1.)
//
// The reboot alone is NOT enough (issue #1, second act, diagnosed 2026-07-17):
// the image's Windows Update run leaves 24H2's LKG shell packages
// (MicrosoftWindows.LKG.*) staged at the base version for no user, and Windows
// re-attempts their reconciliation during the machine's next PROFILE-CREATING
// logon — the during-logon AppX pass. explorer.exe starting mid-reconciliation
// fail-fasts and that profile's shell state stays broken on every later logon
// (seen live: a DC's first Administrator logon 4 min after the dcpromo reboot;
// a fresh profile created after the reconciliation settled was fine).
// settle_appx consumes that pending work as SYSTEM before anyone can log on.

use vmlab

fn wait_first_boot(lab: Lab, vm: Vm) -> Result[unit, string] {
    let marker = "C:\\Windows\\Temp\\vmlab-firstboot.done"
    // Specialize + OOBE can take a while; poll for up to ~25 minutes (well
    // under vmlab's 30-minute host ceiling, so this clearer error wins). The
    // agent may blip across a specialize reboot, so a failed exec is not fatal.
    for i in 0..300 {
        match vm.exec("cmd.exe", ["/c", "if exist " + marker + " (exit 0) else (exit 1)"]) {
            Ok(r) => {
                if r.exit_code == 0 {
                    lab.log("first-boot: specialize complete; clearing marker")
                    let del = vm.exec("cmd.exe", ["/c", "del /f /q " + marker])
                    return Ok(())
                }
            }
            Err(e) => lab.log("first-boot: agent busy (" + e + "); still waiting"),
        }
        vmlab::sleep_ms(5000)
    }
    Err("first-boot marker never appeared after ~25 minutes")
}

// Consume the pending staged-AppX reconciliation before anyone can log on.
// Targets main packages staged for no user and not provisioned (the stale LKG
// shell fallbacks after a Windows Update run). The LKG system apps refuse
// removal (0x80073CFA "part of Windows") — that is fine: the removal ATTEMPT
// itself settles the pending reconciliation, so the first real logon has
// nothing to race. Best-effort; never fails the first boot.
fn settle_appx(lab: Lab, vm: Vm) {
    lab.log("first-boot: settling staged AppX (LKG) before first logon")
    let ps = "$prov = (Get-AppxProvisionedPackage -Online).DisplayName; Get-AppxPackage -AllUsers | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and $prov -notcontains $_.Name -and -not ($_.PackageUserInformation | Where-Object InstallState -eq 'Installed') } | ForEach-Object { $r = 'removed'; try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop } catch { $r = 'settled' }; Write-Output ($r + ' ' + $_.PackageFullName) }"
    match vm.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps]) {
        Ok(r) => {
            let out = r.stdout.trim()
            if out != "" {
                lab.log("first-boot: appx: " + out)
            }
        }
        Err(e) => lab.log("first-boot: appx settle skipped (" + e + ")"),
    }
}

// Install the first-logon XAML registration hook (the ROOT cause of issue #1,
// diagnosed 2026-07-17 against Microsoft's own writeup): vmlab runs sysprep
// under the guest agent, i.e. as Local System, which on 24H2/Server 2025
// "skips AppX registration for certain XAML packages" — explorer.exe then
// fail-fasts (0xc0000409) on a clone's early first logon, permanently
// breaking that profile's shell. Microsoft's supported mitigation for
// deployed images is to register MicrosoftWindows.Client.CBS,
// Microsoft.UI.Xaml.CBS and MicrosoftWindows.Client.Core in the user session
// BEFORE the shell starts:
// https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/sysprep-as-system-windows-11
// Active Setup is exactly that hook: its StubPath runs synchronously at each
// user's first logon, before explorer launches. No-op on pre-24H2 guests
// (the CBS packages don't exist there). Best-effort.
fn install_xaml_hook(lab: Lab, vm: Vm) {
    lab.log("first-boot: installing first-logon XAML registration hook (sysprep-as-SYSTEM workaround)")
    // register-xaml.ps1, base64 to dodge three layers of quoting. Decoded
    // it registers the three CBS packages for the logging-on user (retrying
    // until the deployment service accepts) and then holds the shell until
    // ~5 min of uptime — a first logon earlier than that permanently breaks
    // the new profile's shell even with the packages registered. Regenerate:
    //   base64 -w0 register-xaml.ps1   (source kept in the repo next to this)
    let b64 = "IyB2bWxhYjogZmlyc3QtbG9nb24gc2hlbGwgZ2F0ZSAoQWN0aXZlIFNldHVwIFN0dWJQYXRoOyBleHBsb3Jlci5leGUgd2FpdHMKIyBmb3IgdGhpcyB0byBleGl0KS4gSW5zdGFsbGVkIGJ5IHRoZSB0ZW1wbGF0ZSdzIGZpcnN0LWJvb3Qgc2NyaXB0IGJlY2F1c2UKIyB2bWxhYiBydW5zIHN5c3ByZXAgYXMgTG9jYWwgU3lzdGVtLCB3aGljaCBvbiAyNEgyL1NlcnZlciAyMDI1IHNraXBzIEFwcFgKIyByZWdpc3RyYXRpb24gZm9yIHRoZSBYQU1MIENCUyBwYWNrYWdlcyDigJQgc2VlCiMgaHR0cHM6Ly9sZWFybi5taWNyb3NvZnQuY29tL2VuLXVzL3Ryb3VibGVzaG9vdC93aW5kb3dzLWNsaWVudC9zZXR1cC11cGdyYWRlLWFuZC1kcml2ZXJzL3N5c3ByZXAtYXMtc3lzdGVtLXdpbmRvd3MtMTEKIwojIFR3byBqb2JzLCBib3RoIHJlcXVpcmVkICh2ZXJpZmllZCBsaXZlIDIwMjYtMDctMTcgb24gU2VydmVyIDIwMjUpOgojICAxLiBSZWdpc3RlciB0aGUgdGhyZWUgQ0JTIHBhY2thZ2VzIGZvciB0aGlzIHVzZXIsIHJldHJ5aW5nIHVudGlsIHRoZSBBcHBYCiMgICAgIGRlcGxveW1lbnQgc2VydmljZSBhY2NlcHRzIHRoZW0gKGl0IHJlZnVzZXMgd29yayBpbiB0aGUgZmlyc3QgbWludXRlCiMgICAgIG9yIHR3byBhZnRlciBib290OyB0aGUgY21kbGV0IHN1Y2NlZWRpbmcgaXMgdGhlIGNvbXBsZXRpb24gc2lnbmFsKS4KIyAgMi4gSG9sZCB0aGUgc2hlbGwgdW50aWwgdGhlIG1hY2hpbmUgaXMgfjUgbWludXRlcyBwYXN0IGJvb3QuIEEgZmlyc3QKIyAgICAgbG9nb24gdGhhdCBsYW5kcyBlYXJsaWVyIHBlcm1hbmVudGx5IGJyZWFrcyB0aGUgbmV3IHByb2ZpbGUncyBzaGVsbAojICAgICBldmVuIFdJVEggdGhlIHBhY2thZ2VzIHJlZ2lzdGVyZWQgKGV4cGxvcmVyIGZhaWwtZmFzdHMsIG9yIG5ldmVyCiMgICAgIGxhdW5jaGVzKSDigJQgdGhlIHN5c3ByZXAtYXMtU1lTVEVNIGRhbWFnZSByZWFjaGVzIGJleW9uZCB0aG9zZSB0aHJlZQojICAgICBwYWNrYWdlcywgYW5kIHBvc3QtYm9vdCBzZXJ2aWNpbmcgbmVlZHMgdGltZSB0byBzZXR0bGUuIFByb2ZpbGVzCiMgICAgIGNyZWF0ZWQgYWZ0ZXIgdGhpcyBnYXRlIGdldCBhIHdvcmtpbmcgZGVza3RvcDsgbGF0ZXIgbG9nb25zIG9mIHRoZQojICAgICBzYW1lIHVzZXIgc2tpcCB0aGlzIHN0dWIgZW50aXJlbHkgKEFjdGl2ZSBTZXR1cCBydW5zIG9uY2UgcGVyIHVzZXIpLgokYXBwcyA9IEAoCiAgJ01pY3Jvc29mdFdpbmRvd3MuQ2xpZW50LkNCU19jdzVuMWgydHh5ZXd5JywKICAnTWljcm9zb2Z0LlVJLlhhbWwuQ0JTXzh3ZWt5YjNkOGJid2UnLAogICdNaWNyb3NvZnRXaW5kb3dzLkNsaWVudC5Db3JlX2N3NW4xaDJ0eHlld3knCikgfCBXaGVyZS1PYmplY3QgeyBUZXN0LVBhdGggKCdDOlxXaW5kb3dzXFN5c3RlbUFwcHNcJyArICRfICsgJ1xhcHB4bWFuaWZlc3QueG1sJykgfQpmb3JlYWNoICgkYSBpbiAkYXBwcykgewogIGZvciAoJGkgPSAwOyAkaSAtbHQgMzY7ICRpKyspIHsKICAgIHRyeSB7CiAgICAgIEFkZC1BcHB4UGFja2FnZSAtUmVnaXN0ZXIgLVBhdGggKCdDOlxXaW5kb3dzXFN5c3RlbUFwcHNcJyArICRhICsgJ1xhcHB4bWFuaWZlc3QueG1sJykgLURpc2FibGVEZXZlbG9wbWVudE1vZGUgLUVycm9yQWN0aW9uIFN0b3AKICAgICAgYnJlYWsKICAgIH0gY2F0Y2ggewogICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CiAgICB9CiAgfQp9CiR1cHRpbWUgPSAoKEdldC1EYXRlKSAtIChHZXQtQ2ltSW5zdGFuY2UgV2luMzJfT3BlcmF0aW5nU3lzdGVtKS5MYXN0Qm9vdFVwVGltZSkuVG90YWxTZWNvbmRzCmlmICgkdXB0aW1lIC1sdCAzMDApIHsgU3RhcnQtU2xlZXAgLVNlY29uZHMgKFtpbnRdKDMwMCAtICR1cHRpbWUpKSB9CmV4aXQgMAo="
    let ps = "$apps = @('MicrosoftWindows.Client.CBS_cw5n1h2txyewy','Microsoft.UI.Xaml.CBS_8wekyb3d8bbwe','MicrosoftWindows.Client.Core_cw5n1h2txyewy') | Where-Object { Test-Path ('C:\\Windows\\SystemApps\\' + $_ + '\\appxmanifest.xml') }; if (-not $apps) { Write-Output 'no XAML CBS packages; hook not needed'; exit 0 }; New-Item -ItemType Directory -Path 'C:\\ProgramData\\vmlab' -Force | Out-Null; [IO.File]::WriteAllBytes('C:\\ProgramData\\vmlab\\register-xaml.ps1', [Convert]::FromBase64String('" + b64 + "')); $k = 'HKLM:\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components\\{b3f2f2c4-vmlab-xaml-0001}'; New-Item -Path $k -Force | Out-Null; Set-ItemProperty -Path $k -Name '(Default)' -Value 'vmlab: register XAML AppX before first shell start'; Set-ItemProperty -Path $k -Name 'StubPath' -Value 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\\ProgramData\\vmlab\\register-xaml.ps1'; Set-ItemProperty -Path $k -Name 'Version' -Value '1'; Write-Output ('hook installed for: ' + ($apps -join ', '))"
    match vm.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps]) {
        Ok(r) => {
            let out = r.stdout.trim()
            if out != "" {
                lab.log("first-boot: xaml: " + out)
            }
        }
        Err(e) => lab.log("first-boot: xaml hook skipped (" + e + ")"),
    }
}

// Reboot from inside Windows once specialize has finished, then wait for the
// clone to come back ready. Same approach as the build provision's reboot: a
// host stop hard-kills QEMU after ~60s, so `shutdown /r` lets Windows settle;
// we wait for the agent to drop (so we don't race a still-up guest) and return
// only when it answers again. Falls back to a host restart if the agent never
// goes away.
fn reboot_guest(lab: Lab, vm: Vm) -> Result[unit, string] {
    lab.log("first-boot: rebooting once to settle shell reconciliation")
    let r = vm.exec("cmd.exe", ["/c", "shutdown /r /t 0 /f"])
    let dropped = false
    for i in 0..60 {                 // up to ~5 min for the agent to disappear
        vmlab::sleep_ms(5000)
        if !vm.is_ready() {
            dropped = true
            break
        }
    }
    if !dropped {
        lab.log("first-boot: agent still up after reboot request; forcing host restart")
        vm.restart()?
    }
    vm.wait_ready(1800)
}

// Hold `ready` until the guest is ~5 minutes past its final boot. On
// 24H2/Server 2025 images sysprepped as Local System, a PROFILE-CREATING
// logon in the first minutes after boot permanently breaks that profile's
// shell (explorer fail-fasts or never launches) — even with the XAML
// packages registered and the shell start gated (all variants verified live
// 2026-07-17). Warm-machine first logons are reliably fine, so make "ready"
// imply "warm". The XAML hook above still covers users who race the console
// before ready.
fn hold_until_warm(lab: Lab, vm: Vm) {
    lab.log("first-boot: holding ready until the guest settles (early first logons break the 24H2 shell)")
    let ps = "[int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds"
    for i in 0..40 {
        match vm.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps]) {
            Ok(r) => {
                let up = r.stdout.trim()
                if r.exit_code == 0 && up != "" {
                    if up.parse_int().unwrap_or(0) >= 300 {
                        lab.log("first-boot: guest settled (uptime " + up + "s)")
                        return
                    }
                }
            }
            Err(e) => lab.log("first-boot: uptime probe failed (" + e + "); still waiting"),
        }
        vmlab::sleep_ms(15000)
    }
    lab.log("first-boot: warm-up wait capped; continuing")
}

// Images generalized in a USER context (generalize.ps1 writes
// HKLM\SOFTWARE\vmlab SysprepContext=user) don't have the sysprep-as-SYSTEM
// damage: their clones survive even an immediate first logon (verified live
// 2026-07-17), so the retrofit hook and the 5-minute warm-up hold are
// skipped. Images sealed the old way (no marker) keep both.
fn image_fixed(vm: Vm) -> bool {
    let ps = "(Get-ItemProperty -Path 'HKLM:\\SOFTWARE\\vmlab' -Name 'SysprepContext' -ErrorAction SilentlyContinue).SysprepContext"
    match vm.exec("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps]) {
        Ok(r) => r.exit_code == 0 && r.stdout.trim() == "user",
        Err(e) => false,
    }
}

fn main(lab: Lab) {
    let vm = lab.this_vm().expect("first-boot: no target VM")
    wait_first_boot(lab, vm).expect("windows first-boot failed")
    let fixed = image_fixed(vm)
    settle_appx(lab, vm)
    if !fixed {
        install_xaml_hook(lab, vm)
    }
    reboot_guest(lab, vm).expect("first-boot reboot failed")
    if !fixed {
        hold_until_warm(lab, vm)
    }
}
