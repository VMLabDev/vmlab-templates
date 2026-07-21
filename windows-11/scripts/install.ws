// Build provision for the windows-11 template (PRD §6.1, §10.4).
// Two human moments to automate: the ISO's "Press any key to boot from CD
// or DVD" prompt right after power-on, and knowing when the unattended
// install is done — autounattend.xml installs the vmlab guest agent (VMLAB bootstrap ISO) as its
// last first-logon command, so "agent responding" means finished.
//
// The image is then generalized. Client SKUs make sysprep /generalize abort
// on a "package installed for a user but not provisioned" AppX mismatch, so
// we strip per-user + provisioned AppX first, then run sysprep with
// unattend/sysprep-unattend.xml so every clone gets a fresh SID and a random
// computer name. We power the VM off and seal the generalized disk.

use vmlab

fn boot_from_dvd(lab: Lab, vm: Vm) -> Result[unit, string] {
    for attempt in 0..4 {
        // Spam enter through the prompt's window.
        for i in 0..30 {
            let k = vm.send_keys("enter")   // bind unused Result
            vmlab::sleep_ms(1000)
        }
        // If we missed it, OVMF falls through to its shell; reset and retry.
        let screen = vm.ocr()?
        if screen.contains("Shell>") || screen.contains("UEFI Interactive Shell") {
            lab.log(fmt("missed the boot prompt (attempt {}), resetting", attempt))
            vm.restart()?
            vmlab::sleep_ms(3000)
        } else {
            return Ok(())
        }
    }
    Err("never got past the press-any-key prompt")
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?
    boot_from_dvd(lab, vm)?

    lab.log("Windows Setup running; unattended install takes 20-40 minutes...")
    vm.wait_ready(5400)?

    match vm.exec("cmd.exe", ["/c", "ver"]) {
        Ok(r)  => lab.log("installed: " + r.stdout.trim()),
        Err(e) => lab.log("version check failed (agent is up though): " + e),
    }

    // Operator toggle for fast test builds: patching is the bulk of the
    // 30-45 min build, so `VMLAB_SKIP_UPDATES=1 vmlab template build ...`
    // skips it while iterating on the install/sysprep flow. Published
    // builds must run fully patched (the default).
    if vmlab::env("VMLAB_SKIP_UPDATES") == "1" {
        lab.log("VMLAB_SKIP_UPDATES=1 — skipping Windows Update (test build only)")
    } else {
        apply_updates(lab, vm)?
    }
    disable_updates(lab, vm)?
    sysprep(lab, vm)
}

// Copy a script that rode the UNATTEND ISO onto the disk. The ISO drive letter
// shifts (D/E/F/G), so probe a few. Returns the guest path under Temp.
fn stage_script(vm: Vm, name: string) -> Result[string, string] {
    let dst = "C:\\Windows\\Temp\\" + name
    let copy = vm.exec("cmd.exe", [
        "/c",
        "for %d in (D E F G) do if exist %d:\\" + name + " copy /y %d:\\" + name + " " + dst,
    ])?
    if copy.exit_code != 0 {
        return Err("could not stage " + name + ": " + copy.stderr)
    }
    Ok(dst)
}

// Reboot from INSIDE Windows, not via a host restart. A host-side stop waits
// only ~60s (agent powerdown + ACPI) before hard-killing QEMU, which corrupts a
// long post-update "Working on updates" finalize and drops the next boot into
// WinRE. `shutdown /r` lets Windows finalize at its own pace; we then wait for
// the guest agent to drop (so we don't race ahead while it's still up) and come
// back. Falls back to a host restart only if the agent never goes away.
fn reboot_guest(lab: Lab, vm: Vm) -> Result[unit, string] {
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
        lab.log("guest agent still up after reboot request; forcing host restart")
        vm.restart()?
    }
    vm.wait_ready(7200)              // finalize+boot can be long for big cumulatives
}

// Patch the image fully before sealing: windows-update.ps1 does one search/
// download/install pass and prints a WU_RESULT sentinel; we reboot after each
// installing pass and re-run until it reports NONE (or we hit the pass cap).
// Updates only appear in waves and many need a reboot to settle, so a single
// pass is never enough. WU is flaky, so a FAILED pass is retried, not fatal.
// Run one Windows Update pass and classify the outcome. The WU agent (notably
// Server 2019/2022 on a big backlog) can hang a search/install for a very long
// time, so each pass is capped at 1h; an exec error/timeout is reported as
// "FAILED" so the caller reboots (which clears the stuck agent) and retries
// rather than aborting the whole build. Returns "NONE" / "INSTALLED" / "FAILED".
fn classify_wu(lab: Lab, out: string) -> string {
    lab.log(out.trim())
    if out.contains("WU_RESULT=NONE") {
        "NONE"
    } else if out.contains("WU_RESULT=INSTALLED") {
        "INSTALLED"
    } else {
        "FAILED"
    }
}

fn wu_err(lab: Lab, e: string) -> string {
    lab.log("windows update pass hung/errored: " + e)
    "FAILED"
}

fn run_wu_pass(lab: Lab, vm: Vm, script: string) -> string {
    match vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
    ], 3600) {
        Ok(r)  => classify_wu(lab, r.stdout),
        Err(e) => wu_err(lab, e),
    }
}

fn apply_updates(lab: Lab, vm: Vm) -> Result[unit, string] {
    let script = stage_script(vm, "windows-update.ps1")?
    let fails = 0
    for pass in 0..20 {
        lab.log(fmt("windows update pass {} (search/download/install, may take a while)...", pass))
        let status = run_wu_pass(lab, vm, script)
        if status == "NONE" {
            lab.log(fmt("windows update complete after {} pass(es); image fully patched", pass))
            return Ok(())
        } else if status == "INSTALLED" {
            fails = 0
            lab.log("updates installed; rebooting in-guest to finalize before the next pass")
            reboot_guest(lab, vm)?
        } else {
            // Failed or hung pass — retry across reboots before giving up.
            fails = fails + 1
            if fails >= 5 {
                return Err("windows update kept failing/hanging after 5 attempts")
            }
            lab.log(fmt("windows update pass failed/hung (attempt {}); rebooting and retrying", fails))
            reboot_guest(lab, vm)?
        }
    }
    lab.log("windows update hit the pass cap; proceeding with what was installed")
    Ok(())
}

// Bake "Windows Update off" into the image (policy + service + scheduled tasks)
// so every clone of the sealed template stays put and never auto-updates. Runs
// after patching, before sysprep — the HKLM policy keys and service start type
// survive generalize.
fn disable_updates(lab: Lab, vm: Vm) -> Result[unit, string] {
    let script = stage_script(vm, "disable-windows-update.ps1")?
    lab.log("disabling Windows Update in the image (clones won't auto-update)...")
    let r = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
    ], 600)?
    lab.log(r.stdout.trim())
    if !r.stdout.contains("WU_DISABLED=OK") {
        return Err("disable-windows-update.ps1 did not confirm success: " + r.stdout.trim() + " " + r.stderr.trim())
    }
    Ok(())
}

// Generalize the image so clones get fresh SIDs + random names (domain-joinable).
// The answer file and the generalize script ride the UNATTEND ISO; copy them onto
// the disk first since the ISO is not attached to lab clones.
//
// generalize.ps1 does the real work: sysprep /generalize aborts on modern Windows
// codebases when an AppX package is "installed for a user but not provisioned"
// (0x80073cf2), and those consumer packages register asynchronously after first
// logon, so the script runs sysprep in a loop, removing exactly the package each
// failed pass names until sysprep writes its success tag. It judges success by
// that tag, never by sysprep.exe's (unreliable) exit code — and its OWN exit code
// IS reliable, so we gate the build on it.
fn sysprep(lab: Lab, vm: Vm) -> Result[unit, string] {
    let copy = vm.exec("cmd.exe", [
        "/c",
        "for %d in (D E F G) do if exist %d:\\generalize.ps1 ( copy /y %d:\\sysprep-unattend.xml C:\\Windows\\Temp\\ & copy /y %d:\\generalize.ps1 C:\\Windows\\Temp\\ )",
    ])?
    if copy.exit_code != 0 {
        return Err("could not stage sysprep files: " + copy.stderr)
    }

    lab.log("generalizing (sysprep /generalize with AppX-blocker retry, 5-15 min)...")
    let gen = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", "C:\\Windows\\Temp\\generalize.ps1",
    ], 2400)?
    lab.log("generalize.ps1: " + gen.stdout.trim())
    if gen.exit_code != 0 {
        return Err("sysprep generalize failed (exit " + fmt("{}", gen.exit_code) + "): " + gen.stdout.trim() + " " + gen.stderr.trim())
    }

    lab.log("sysprep generalized OK (success tag present); powering off to seal")
    let shut = vm.exec_timeout("cmd.exe", ["/c", "shutdown /s /t 0"], 60)
    vm.wait_shutdown(900)?
    Ok(())
}

fn main(lab: Lab) {
    install(lab).expect("windows-11 build failed")
}
