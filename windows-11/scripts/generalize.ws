// Provision for the `standard` variant of the windows-11 template (PRD §6.6).
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
            failed.expect("windows-11 standard variant failed: " + e)
        },
    }
}
