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

fn main(lab: Lab) {
    let vm = lab.this_vm().expect("first-boot: no target VM")
    wait_first_boot(lab, vm).expect("windows first-boot failed")
    settle_appx(lab, vm)
    reboot_guest(lab, vm).expect("first-boot reboot failed")
}
