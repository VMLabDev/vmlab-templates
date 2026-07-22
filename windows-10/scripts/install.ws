// Build provision for the windows-10 template (PRD §6.1, §10.4).
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
// Run a guest exec, retrying transient agent hiccups. Right after Windows
// first logon the agent answers its handshake (so wait_ready returns) before
// its exec channel is fully ready, so the first few execs can fail with
// "agent did not open the channel in time" even though the guest is fine.
// A short retry absorbs that window instead of failing a multi-hour build.
fn exec_ok(lab: Lab, vm: Vm, cmd: string, args: [string]) -> Result[ExecResult, string] {
    let last = "exec never ran"
    for i in 0..12 {                 // up to ~1 min of transient-blip tolerance
        match vm.exec(cmd, args) {
            Ok(r)  => return Ok(r),
            Err(e) => {
                last = e
                lab.log(fmt("exec transient failure (try {}); retrying: {}", i, e))
                vmlab::sleep_ms(5000)
            },
        }
    }
    Err("exec failed after retries: " + last)
}

fn stage_script(lab: Lab, vm: Vm, name: string) -> Result[string, string] {
    let dst = "C:\\Windows\\Temp\\" + name
    let copy = exec_ok(lab, vm, "cmd.exe", [
        "/c",
        "for %d in (D E F G) do if exist %d:\\" + name + " copy /y %d:\\" + name + " " + dst,
    ])?
    if copy.exit_code != 0 {
        return Err("could not stage " + name + ": " + copy.stderr)
    }
    Ok(dst)
}

// The guest's boot stamp — the proof a reboot actually happened. A
// `shutdown /r` request can be silently swallowed (observed live on Server
// 2022: exit 0 semantics but the desktop still up an hour later while
// servicing was busy), so reboot_guest compares this before/after instead
// of trusting the request.
fn boot_stamp(vm: Vm) -> Result[string, string] {
    let r = vm.exec("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-Command",
        "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')",
    ])?
    if r.exit_code != 0 {
        return Err("boot-stamp query failed: " + r.stderr)
    }
    Ok(r.stdout.trim())
}

// Reboot from INSIDE Windows, not via a host restart. A host-side stop waits
// only ~60s (agent powerdown + ACPI) before hard-killing QEMU, which corrupts a
// long post-update "Working on updates" finalize and drops the next boot into
// WinRE. `shutdown /r` lets Windows finalize at its own pace. The drop-watch is
// the live `agent_answering()` probe, and a changed boot stamp is the only
// accepted proof: Windows sometimes swallows the shutdown request outright
// while servicing is busy, so an unchanged stamp re-requests it. Only when
// three rounds (up to ~20 min of still-up waiting each) never produce a real
// reboot does the host restart run as the true last resort.
fn reboot_guest(lab: Lab, vm: Vm) -> Result[unit, string] {
    let before = boot_stamp(vm)?
    for round in 0..3 {
        // The shutdown can tear the agent down before the exec reply
        // arrives, so an exec error usually means the reboot is underway.
        match vm.exec("cmd.exe", ["/c", "shutdown /r /t 0 /f"]) {
            Ok(r) => lab.log(fmt("in-guest reboot requested (shutdown exit {})", r.exit_code)),
            Err(e) => lab.log("shutdown exec did not return cleanly (reboot likely underway): " + e),
        }
        // Post-update "Working on updates" runs BEFORE services stop, so the
        // agent can keep answering for a long while; the probe is live, so
        // waiting is free and we move on the moment the guest goes down.
        for i in 0..240 {            // up to 20 min per round
            vmlab::sleep_ms(5000)
            if !vm.agent_answering() {
                break
            }
        }
        vm.wait_ready(7200)?         // finalize+boot can be long for big cumulatives
        match boot_stamp(vm) {
            Ok(after) => {
                if after != before {
                    return Ok(())
                }
                lab.log("boot stamp unchanged — the guest never rebooted; requesting again")
            },
            // A failed check usually means the guest is mid-transition
            // after all — loop around rather than failing the build.
            Err(e) => lab.log("boot-stamp check failed (guest mid-transition?); retrying: " + e),
        }
    }
    lab.log("in-guest reboot never took after 3 rounds; forcing host restart")
    vm.restart()?
    vm.wait_ready(7200)
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
    // Settle first: Windows can chain automatic reboots while finishing
    // updates, and readiness can catch the brief agent-up window between
    // them — a pass issued right then races the next auto-reboot and reads
    // as a failure. A short wait plus a fresh readiness check rides that out.
    vmlab::sleep_ms(30000)
    match vm.wait_ready(600) {
        Ok(u)  => lab.log("guest settled; starting the update pass"),
        Err(e) => lab.log("guest not ready before the update pass: " + e),
    }
    match vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
    ], 3600) {
        Ok(r)  => classify_wu(lab, r.stdout),
        Err(e) => wu_err(lab, e),
    }
}

fn apply_updates(lab: Lab, vm: Vm) -> Result[unit, string] {
    let script = stage_script(lab, vm, "windows-update.ps1")?
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
    let script = stage_script(lab, vm, "disable-windows-update.ps1")?
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
    install(lab).expect("windows-10 build failed")
}
