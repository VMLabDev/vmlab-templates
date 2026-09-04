// Build provision for the windows-server-2012-r2 template (PRD §6.1, §10.4). The whole
// install is guest-driven: autounattend.xml lays down Windows, installs the
// vmlab agent from the bootstrap ISO, and runs `sysprep /generalize /oobe
// /shutdown` on first logon, which powers the VM off. This side types past the
// BIOS "boot from CD" prompt and waits for that poweroff; vmlab then seals the
// generalized disk and proves the agent on a verification boot.

use vmlab

fn boot_from_cd(lab: Lab, vm: Vm) -> Result[unit, string] {
    // SeaBIOS shows "Press any key to boot from CD or DVD" for a few seconds.
    // Spam enter through it. We stop well before Setup's first reboot, so the
    // reboots that follow fall through to the (now bootable) hard disk.
    for i in 0..45 {
        let k = vm.send_keys("enter")   // bind unused Result
        vmlab::sleep_ms(1000)
    }
    Ok(())
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?
    boot_from_cd(lab, vm)?

    lab.log("installing Windows Server 2012 R2 + sysprep; the answer file powers off when done (20-50 min)...")
    // The guest powers itself off after install -> agent install -> first-logon
    // sysprep. Budget three hours: these run two-up on one host, and a Windows 7
    // x64 install that took 93 minutes overran the old 90-minute wait (2026-09-03).
    vm.wait_shutdown(10800)?
    lab.log("VM powered off; sealing the generalized image")
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
            failed.expect("windows-server-2012-r2 build failed: " + e)
        },
    }
}
