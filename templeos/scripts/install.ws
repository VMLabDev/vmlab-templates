// Drive the TempleOS auto-installer onto a blank RedSea disk, then power off to
// seal. Booting the CD runs `#include "Once"`, which asks a short series of
// yes/no questions and — once told it's running in a VM — auto-partitions,
// formats and copies the OS to the hard drive.
//
// There is no answer file and no guest agent, and TempleOS's bitmap font
// defeats OCR, so the prompts are driven over the live screen with image
// matching (VNC keystrokes). Only two moments have variable timing and need
// image anchors: the first prompt after boot, and the "Reboot Now" prompt after
// the copy finishes (~1-2 min). Every other prompt renders within a second of
// the prior keystroke and is answered after a short fixed pause. All the
// (y or n) prompts advance on a single keypress — no Enter.

use vmlab

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // Boot the CD -> "Install onto hard drive (y or n)?". Reference images are
    // matched at a slightly relaxed threshold: TempleOS's tiny bitmap-font
    // prompts are a small target for template matching.
    lab.log("waiting for the TempleOS install prompt...")
    vm.wait_for_image_opts("images/install-prompt.png", 300, 0.85, [])?
    lab.log("install prompt up; answering yes")
    vm.type_text("y")?

    // "Are you installing inside VMware, QEMU, VirtualBox ...? (y or n)?" — yes.
    // Answering yes lets OSInstall.HC automate partition/format/copy. This and
    // the "PRESS A KEY" prompt below each render within a second of the prior
    // keypress and wait indefinitely, so a short fixed pause is enough.
    vmlab::sleep_ms(4000)
    vm.type_text("y")?

    // "It's normal for this to freeze ... PRESS A KEY", then the auto-install
    // runs (partition + format + copy — a minute or several, disk-bound).
    vmlab::sleep_ms(4000)
    vm.send_keys("enter")?
    lab.log("auto-install running (partition + format + copy)...")

    // "Reboot Now (y or n)?" — the copy is done. No: we power off to seal
    // rather than reboot into the still-attached CD. This is the second and
    // last variable-timing wait.
    vm.wait_for_image_opts("images/reboot-prompt.png", 900, 0.85, [])?
    lab.log("install complete; declining the reboot")
    vm.type_text("n")?

    // "Take Tour (y or n)?" — renders right after, waits; blind no lands us at
    // the installed C:/> prompt.
    vmlab::sleep_ms(4000)
    vm.type_text("n")?
    vmlab::sleep_ms(3000)

    // --- Seal ----------------------------------------------------------------
    // TempleOS has no ACPI, so the build's graceful ACPI stop would time out and
    // SIGKILL — which drops unflushed qcow2 writes and can leave the RedSea image
    // unbootable. A clean QMP quit (poweroff) flushes the disk first, same as
    // FreeDOS.
    lab.log("TempleOS installed to C:; powering off to seal")
    vmlab::sleep_ms(2000)
    vm.poweroff()?
    Ok(())
}

fn main(lab: Lab) {
    install(lab).expect("templeos build failed")
}
