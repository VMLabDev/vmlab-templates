// Build provision for the windows-server-2012 template (PRD §6.1, §10.4). Legacy Windows
// has no qemu guest agent, so this is agent-free: autounattend.xml installs
// Windows and runs `sysprep /generalize /oobe /shutdown` on first logon, which
// powers the VM off. We type past the BIOS "boot from CD" prompt and then wait
// for that poweroff — vmlab seals the generalized disk.

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

    lab.log("installing Windows 7 + sysprep; the answer file powers off when done (20-50 min)...")
    // The guest powers itself off after install -> first-logon sysprep.
    vm.wait_shutdown(2700)?
    lab.log("VM powered off; sealing the generalized image")
    Ok(())
}

fn main(lab: Lab) {
    install(lab).expect("windows-server-2012 build failed")
}
