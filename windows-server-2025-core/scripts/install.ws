// Build provision for the windows-server-2025-core template (PRD §6.1, §10.4).
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
fn exec_ok(lab: Lab, vm: Vm, cmd: string, args: List[string]) -> Result[ExecResult, string] {
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
// Wait for the agent to answer, on the live probe. Readiness is sticky — it
// stays true across a reboot the guest has not performed yet — so it cannot
// tell "back up" from "on its way down", which is the only question worth
// asking between a reboot request and the next thing that talks to the guest.
fn wait_agent(lab: Lab, vm: Vm, rounds: int) -> bool {
    for i in 0..rounds {
        if vm.agent_answering() {
            return true
        }
        vmlab::sleep_ms(5000)
    }
    lab.log("agent never answered while waiting for the guest to come back")
    false
}

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
    // The guest can already be mid-restart when we arrive — a failed update
    // pass often leaves it that way — so wait for the agent before taking the
    // reference stamp. An unreadable stamp is not worth failing a multi-hour
    // build over: with no reference, a guest seen to drop and come back has
    // demonstrably rebooted, which is all this proves anyway. (Windows 11,
    // 2026-09-02: `let before = boot_stamp(vm)?` aborted the whole build.)
    let ok = wait_agent(lab, vm, 720)          // up to 1h
    let before = match boot_stamp(vm) {
        Ok(s) => s,
        Err(e) => {
            lab.log("no reference boot stamp (" + e + "); a drop and return will do instead")
            ""
        },
    }
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
        let dropped = false
        for i in 0..240 {            // up to 20 min per round
            vmlab::sleep_ms(5000)
            if !vm.agent_answering() {
                dropped = true
                break
            }
        }
        // Then wait for it to come BACK, on the same live probe. Readiness is
        // sticky — a guest that has been ready once reports ready again at
        // once, across a reboot it has not performed yet — so waiting on it
        // here returns immediately and hands the boot-stamp check below a
        // guest whose agent is still down. That reads as "the reboot never
        // happened", and all three rounds burn in seconds (Server 2019,
        // 2026-09-02: three rounds and the host-restart fallback inside four
        // minutes, while the guest was rebooting perfectly well).
        if dropped {
            for i in 0..1440 {       // up to 2h; a big cumulative finalizes slowly
                vmlab::sleep_ms(5000)
                if vm.agent_answering() {
                    break
                }
            }
        }
        vm.wait_ready(7200)?         // the agent answers again; let ready settle
        match boot_stamp(vm) {
            Ok(after) => {
                if after != before {
                    return Ok(())
                }
                if before == "" && dropped {
                    lab.log("no reference stamp, but the guest dropped and came back — rebooted")
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
// time, so each pass is capped at 2h; an exec error/timeout is reported as
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
    // The live probe, not readiness: a pass issued while the guest is still
    // going down answers WU_E_SERVICE_STOP (0x8024001E) and reads as a failed
    // pass (Windows 11, 2026-09-02).
    if wait_agent(lab, vm, 360) {
        lab.log("guest settled; starting the update pass")
    } else {
        lab.log("guest never came back before the update pass; trying it anyway")
    }
    match vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script,
    ], 7200) {
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
// that tag, never by sysprep.exe's (unreliable) exit code.
//
// CRITICAL (issue #1, root cause found 2026-07-17): sysprep must NOT run as
// Local System. The agent execs as SYSTEM, and on 24H2/Server 2025 a
// SYSTEM-context sysprep skips AppX registration for the XAML CBS packages —
// every clone's early first logon then permanently breaks that profile's
// shell (explorer 0xc0000409 fail-fast or a shell that never launches):
// https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/sysprep-as-system-windows-11
// So generalize.ps1 runs through a one-shot scheduled task as Administrator
// (batch logon = a real user context), and the build polls the task + the
// log it writes.
fn sysprep(lab: Lab, vm: Vm) -> Result[unit, string] {
    let copy = vm.exec("cmd.exe", [
        "/c",
        "for %d in (D E F G) do if exist %d:\\generalize.ps1 ( copy /y %d:\\sysprep-unattend.xml C:\\Windows\\Temp\\ & copy /y %d:\\generalize.ps1 C:\\Windows\\Temp\\ )",
    ])?
    if copy.exit_code != 0 {
        return Err("could not stage sysprep files: " + copy.stderr)
    }

    lab.log("generalizing (sysprep /generalize as Administrator via task, 5-15 min)...")
    let del = vm.exec("cmd.exe", ["/c", "del /f /q C:\\Windows\\Temp\\generalize.log C:\\Windows\\Temp\\generalize.rc 2>nul & exit 0"])
    // A wrapper batch file: %errorlevel% on its own LINE expands at run time
    // (inline `cmd /c ... & echo %errorlevel%` would expand at parse time).
    let wrap = vm.exec("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-Command",
        "Set-Content -Path 'C:\\Windows\\Temp\\generalize.cmd' -Value @('@echo off', 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\generalize.ps1 > C:\\Windows\\Temp\\generalize.log 2>&1', 'echo %errorlevel% > C:\\Windows\\Temp\\generalize.rc')",
    ])?
    if wrap.exit_code != 0 {
        return Err("could not write the generalize wrapper: " + wrap.stderr)
    }
    let create = vm.exec("cmd.exe", [
        "/c",
        "schtasks /Create /F /TN vmlab-generalize /RU Administrator /RP vmlab123! /RL HIGHEST /SC ONCE /ST 23:59 /TR C:\\Windows\\Temp\\generalize.cmd",
    ])?
    if create.exit_code != 0 {
        return Err("could not create the generalize task: " + create.stdout + " " + create.stderr)
    }
    let run = vm.exec("cmd.exe", ["/c", "schtasks /Run /TN vmlab-generalize"])?
    if run.exit_code != 0 {
        return Err("could not start the generalize task: " + run.stdout + " " + run.stderr)
    }

    // Poll for the task's exit-code file (written when generalize.ps1 ends);
    // sysprep + AppX retries usually take 5-15 minutes.
    let rc = ""
    for i in 0..240 {
        vmlab::sleep_ms(10000)
        match vm.exec("cmd.exe", ["/c", "type C:\\Windows\\Temp\\generalize.rc"]) {
            Ok(r) => {
                if r.exit_code == 0 && r.stdout.trim() != "" {
                    rc = r.stdout.trim()
                    break
                }
            }
            Err(e) => lab.log("generalize poll blip (" + e + ")"),
        }
    }
    let out = vm.exec("cmd.exe", ["/c", "type C:\\Windows\\Temp\\generalize.log"])?
    lab.log("generalize.ps1: " + out.stdout.trim())
    if rc == "" {
        return Err("generalize task never finished (~40 min)")
    }
    if rc != "0" {
        return Err("sysprep generalize failed (exit " + rc + ")")
    }

    lab.log("sysprep generalized OK (success tag present); powering off to seal")
    let shut = vm.exec_timeout("cmd.exe", ["/c", "shutdown /s /t 0"], 60)
    vm.wait_shutdown(900)?
    Ok(())
}

fn main(lab: Lab) {
    // `expect` drops the Err payload, so a bare expect prints the
    // failure and nothing about its cause (windows-11, 2026-09-04: a
    // whole failed build whose reason was never recorded). The cause
    // rides the message instead.
    match install(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("windows-server-2025-core build failed: " + e)
        },
    }
}
