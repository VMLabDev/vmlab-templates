// Build provision for the windows-11-arm64 template (PRD §6.1, §10.4).
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

    lab.log("Windows Setup running under TCG emulation; this can take hours...")
    vm.wait_ready(28800)?   // up to 8h: emulated aarch64 Windows is slow

    match vm.exec("cmd.exe", ["/c", "ver"]) {
        Ok(r)  => lab.log("installed: " + r.stdout.trim()),
        Err(e) => lab.log("version check failed (agent is up though): " + e),
    }

    sysprep(lab, vm)
}

// Generalize the image so clones get fresh SIDs (domain-joinable). The answer
// file rides the UNATTEND ISO; copy it onto the disk first since the ISO is
// not attached to lab clones.
fn sysprep(lab: Lab, vm: Vm) -> Result[unit, string] {
    let copy = vm.exec("cmd.exe", [
        "/c",
        "for %d in (D E F G) do if exist %d:\\sysprep-unattend.xml copy /y %d:\\sysprep-unattend.xml C:\\Windows\\Temp\\sysprep-unattend.xml",
    ])?
    if copy.exit_code != 0 {
        return Err("could not stage sysprep-unattend.xml: " + copy.stderr)
    }

    // sysprep /generalize aborts on Win10/11 client SKUs when an AppX package
    // is installed for a user but not provisioned for all users. Removing the
    // per-user and provisioned packages clears the mismatch (harmless on
    // Server, which carries few/no such packages).
    lab.log("removing AppX packages so sysprep /generalize won't abort...")
    let strip = vm.exec_timeout("powershell.exe", [
        "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command",
        "Get-AppxPackage -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; Get-AppxProvisionedPackage -Online | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }",
    ], 7200)
    match strip {
        Ok(r)  => lab.log("AppX strip done (exit " + fmt("{}", r.exit_code) + ")"),
        Err(e) => lab.log("AppX strip returned an error (continuing): " + e),
    }

    // Run sysprep with /quit (not /shutdown) so we can read its exit code and
    // surface the Panther log on failure, instead of blindly waiting out a
    // poweroff that never comes.
    lab.log("running sysprep /generalize (5-10 minutes)...")
    let sp = vm.exec_timeout("C:\\Windows\\System32\\Sysprep\\sysprep.exe", [
        "/generalize", "/oobe", "/quit", "/quiet",
        "/unattend:C:\\Windows\\Temp\\sysprep-unattend.xml",
    ], 7200)?
    if sp.exit_code != 0 {
        match vm.exec("powershell.exe", [
            "-NoProfile", "-Command",
            "Get-Content C:\\Windows\\System32\\Sysprep\\Panther\\setupact.log -Tail 80",
        ]) {
            Ok(r)  => return Err("sysprep /generalize failed (exit " + fmt("{}", sp.exit_code) + "); setupact.log tail:\n" + r.stdout),
            Err(_) => return Err("sysprep /generalize failed (exit " + fmt("{}", sp.exit_code) + ")"),
        }
    }

    lab.log("sysprep generalized OK; powering off to seal")
    let shut = vm.exec_timeout("cmd.exe", ["/c", "shutdown /s /t 0"], 60)
    vm.wait_shutdown(3600)?
    Ok(())
}

fn main(lab: Lab) {
    install(lab).expect("windows-11-arm64 build failed")
}
