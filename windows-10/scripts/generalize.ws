// Provision for the `standard` variant of the windows-10 template (PRD §6.6).
// The base is installed, patched and NOT generalized; scripts/install.ws left
// generalize.ps1 and sysprep-unattend.xml in C:\ProgramData\vmlab\sysprep.
// This runs on a linked overlay of that base, generalizes it so every clone
// gets a fresh SID and a random computer name, and powers off to seal the
// variant. A variant that does its own work first (a driver package, say)
// lists its provisions before this one.
//
// generalize.ps1 does the real work: sysprep /generalize aborts on modern Windows
// codebases when an AppX package is "installed for a user but not provisioned"
// (0x80073cf2), and those consumer packages register asynchronously after first
// logon, so the script runs sysprep in a loop, removing exactly the package each
// failed pass names until sysprep writes its success tag. It judges success by
// that tag, never by sysprep.exe's (unreliable) exit code — and its OWN exit code
// IS reliable, so we gate the build on it.

use vmlab

// Run a guest exec, retrying transient agent hiccups: the agent answers its
// handshake (so the build's readiness check passes) a little before its exec
// channel is fully ready, so the first exec after boot can fail with "agent
// did not open the channel in time" even though the guest is fine.
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

// sysprep refuses to run while reserved storage is in use (0x800F0975, "Audit
// mode cannot be turned on if reserved storage is in use"). A servicing
// operation left unfinished in the base, typically an update pass that hung
// and was retried, holds it across boots, and every variant then fails its
// generalize. Turning reserved storage off releases it; when Windows refuses
// because a scenario still holds it, clearing the reserve manager's
// ActiveScenario and rebooting lets the second attempt through.
fn reserved_storage_off(vm: Vm) -> Result[string, string] {
    let ps = "$k = 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ReserveManager'; if ((Get-WindowsReservedStorageState).ReservedStorageState -eq 'Disabled') {{ 'RS=OFF'; exit 0 }}; try {{ Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null; 'RS=OFF' }} catch {{ New-ItemProperty -Path $k -Name ActiveScenario -Value 0 -PropertyType DWord -Force | Out-Null; 'RS=INUSE ' + $_.Exception.Message }}"
    let r = vm.exec_timeout("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], 300)?
    Ok(r.stdout.trim())
}

fn reboot_and_wait(lab: Lab, vm: Vm) -> Result[unit, string] {
    match vm.exec("cmd.exe", ["/c", "shutdown /r /t 0 /f"]) {
        Ok(r) => lab.log(fmt("in-guest reboot requested (shutdown exit {})", r.exit_code)),
        Err(e) => lab.log("shutdown exec did not return cleanly (reboot likely underway): " + e),
    }
    // The live probe, never readiness: readiness is sticky across a reboot.
    let dropped = false
    for i in 0..240 {                // up to 20 min for the guest to go down
        vmlab::sleep_ms(5000)
        if !vm.agent_answering() {
            dropped = true
            break
        }
    }
    if !dropped {
        return Err("the guest never went down after the reboot request")
    }
    for i in 0..720 {                // up to 1h for it to come back
        vmlab::sleep_ms(5000)
        if vm.agent_answering() {
            return vm.wait_ready(1800)
        }
    }
    Err("the guest did not come back within an hour of its reboot")
}

fn release_reserved_storage(lab: Lab, vm: Vm) -> Result[unit, string] {
    let first = reserved_storage_off(vm)?
    if first.starts_with("RS=OFF") {
        return Ok(())
    }
    lab.log("reserved storage is in use (" + first + "); cleared its active scenario, rebooting")
    reboot_and_wait(lab, vm)?
    let second = reserved_storage_off(vm)?
    if second.starts_with("RS=OFF") {
        lab.log("reserved storage released after the reboot")
        return Ok(())
    }
    Err("reserved storage is still in use after a reboot, so sysprep cannot run: " + second)
}

fn generalize(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?
    vm.wait_ready(1800)?

    let check = exec_ok(lab, vm, "cmd.exe", [
        "/c",
        "if exist C:\\ProgramData\\vmlab\\sysprep\\generalize.ps1 if exist C:\\ProgramData\\vmlab\\sysprep\\sysprep-unattend.xml echo STAGED",
    ])?
    if !check.stdout.contains("STAGED") {
        return Err("the base has no staged sysprep files in C:\\ProgramData\\vmlab\\sysprep; rebuild the base")
    }

    release_reserved_storage(lab, vm)?

    lab.log("generalizing (sysprep /generalize with AppX-blocker retry, 5-15 min)...")
    let gen = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", "C:\\ProgramData\\vmlab\\sysprep\\generalize.ps1",
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
    // `expect` drops the Err payload, so the cause rides the message instead.
    match generalize(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("windows-10 standard variant failed: " + e)
        },
    }
}
