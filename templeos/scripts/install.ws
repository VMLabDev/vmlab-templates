// Drive the TempleOS auto-installer onto a blank RedSea disk, type the vmlab
// agent in, make the boot loader boot unattended, then power off to seal.
// Booting the CD runs `#include "Once"`, which asks a short series of yes/no
// questions and — once told it's running in a VM — auto-partitions, formats and
// copies the OS to the hard drive.
//
// There is no answer file and TempleOS's bitmap font defeats OCR, so the
// installer's prompts are driven over the live screen with image matching.
// Only two moments have variable timing and need image anchors: the first
// prompt after boot, and the "Reboot Now" prompt after the copy finishes (~1-2
// min). Every other prompt renders within a second of the prior keystroke and
// is answered after a short fixed pause. All the (y or n) prompts advance on a
// single keypress — no Enter.
//
// TempleOS reads no ISO 9660 and has no network, so the agent cannot come in on
// the bootstrap ISO: it is typed at the shell (vmlab::templeos_agent_script).
// Once it answers on COM1, the rest of the build runs through `exec`.

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

    // "Reboot Now (y or n)?" — the copy is done. No: a reboot would land on the
    // still-attached CD again (install media boots first). This is the second
    // and last variable-timing wait.
    vm.wait_for_image_opts("images/reboot-prompt.png", 900, 0.85, [])?
    lab.log("install complete; declining the reboot")
    vm.type_text("n")?

    // "Take Tour (y or n)?" — renders right after, waits; blind no lands us at
    // the C:/> prompt, still in the CD's live session.
    vmlab::sleep_ms(4000)
    vm.type_text("n")?
    vmlab::sleep_ms(3000)

    // --- Agent ---------------------------------------------------------------
    // The session is still the CD boot, where `~` is T:/Home on the CD: what the
    // agent typescript writes to `~/` would never reach the installed disk.
    // HomeSet points `~` at the installed C:/Home for this session, so
    // ~/VmlabAgt.HC and the registration in ~/MakeHome.HC.Z land on C:. The
    // registration says `#include "~/VmlabAgt"`, which a clone booting from C:
    // resolves to that same file.
    lab.log("pointing ~ at the installed C:/Home")
    vm.type_text_paced("HomeSet(\"C:/Home\");\n", 40)?
    vmlab::sleep_ms(1500)

    // The HolyC agent, typed at the shell (~12k keystrokes, ~8 minutes). It
    // compiles, registers itself in ~/MakeHome.HC.Z and starts on COM1 at once,
    // which is the handshake the build verifies.
    lab.log("typing the vmlab agent (about 8 minutes)...")
    vm.type_text_paced(vmlab::templeos_agent_script()?, 40)?
    lab.log("agent typed; waiting for its handshake on COM1")
    wait_agent(vm, 300)?

    // A clone boots its MBR into the TempleOS Boot Loader menu (0. Old Boot
    // Record / 1. Drive C / 2. Drive D), which waits for a key forever: the
    // stage-2 loader's BMHD2_GETCHAR is a bare INT 16h. Patch that key read
    // (XOR AH,AH; INT 16h) into MOV AL,'1' and reinstall the loader with
    // BootMHDIns, so it picks Drive C on its own and a clone boots straight to
    // the agent. BootMHDIns is already compiled into this session by the
    // installer, which also saved the OldMBR entry 0 stands for.
    lab.log("making the boot loader pick Drive C unattended")
    // (Braces are doubled: a wscript string reads `{…}` as interpolation.)
    let patch = vm.exec("U8 *p=BMHD2_START;I64 i,n=0;for(i=0;i<BMHD2_END-BMHD2_START-3;i++)if(p[i]==0x32&&p[i+1]==0xE4&&p[i+2]==0xCD&&p[i+3]==0x16){{p[i]=0xB0;p[i+1]=0x31;p[i+2]=0x90;p[i+3]=0x90;n++;}}\"patched %d\\n\",n;if(n==1&&FileFind(\"C:/0000Boot/OldMBR.BIN.C\")&&BootMHDIns('C'))\"bootloader ok\\n\";", [])?
    lab.log(patch.stdout)
    if !patch.stdout.contains("bootloader ok") {
        return Err("patching the TempleOS boot loader failed: " + patch.stdout)
    }

    // Prove the agent landed on the installed disk rather than the CD session.
    let home = vm.exec("I64 sz;U8 *m=FileRead(\"C:/Home/MakeHome.HC.Z\",&sz);if(m&&StrFind(\"VmlabAgt\",m)&&FileFind(\"C:/Home/VmlabAgt.HC\"))\"agent on C\\n\";", [])?
    if !home.stdout.contains("agent on C") {
        return Err("the agent is not registered on C: " + home.stdout)
    }
    lab.log("agent installed on C: and registered in ~/MakeHome.HC.Z")

    // --- Seal ----------------------------------------------------------------
    // TempleOS has no ACPI, so the build's graceful ACPI stop would time out and
    // SIGKILL — which drops unflushed qcow2 writes and can leave the RedSea image
    // unbootable. A clean QMP quit (poweroff) flushes the disk first.
    lab.log("TempleOS installed to C:; powering off to seal")
    vmlab::sleep_ms(2000)
    vm.poweroff()?
    Ok(())
}

// Poll for the agent's handshake on COM1, up to `secs` seconds.
fn wait_agent(vm: Machine, secs: int) -> Result[unit, string] {
    for i in 0..secs {
        if vm.agent_answering() {
            return Ok(())
        }
        vmlab::sleep_ms(1000)
    }
    Err("the TempleOS agent never answered on COM1")
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
            failed.expect("templeos build failed: " + e)
        },
    }
}
