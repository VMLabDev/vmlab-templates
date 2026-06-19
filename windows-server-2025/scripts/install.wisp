// Build provision for the windows-server-2025 template (PRD §6.1, §10.4).
// Two human moments to automate: the ISO's "Press any key to boot from CD
// or DVD" prompt right after power-on, and knowing when the unattended
// install is done — autounattend.xml installs the QEMU guest agent as its
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

    sysprep(lab, vm)
}

// Generalize the image so clones get fresh SIDs + random names (domain-joinable).
// The answer file and the generalize script ride the UNATTEND ISO; copy them onto
// the disk first since the ISO is not attached to lab clones.
//
// generalize.ps1 does the real work: sysprep /generalize aborts on the 26100
// codebase when an AppX package is "installed for a user but not provisioned"
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
    install(lab).expect("windows-server-2025 build failed")
}
