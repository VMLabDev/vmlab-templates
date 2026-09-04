// Drive the FreeDOS 1.3 LiveCD install onto a blank C: with the Full package set
// (applications + games), then power off to seal the bootable disk. FreeDOS has
// no answer file and no guest agent, so the FDI installer is driven entirely over
// the live screen (VNC + OCR), like dos-6.22.
//
// Two quirks shape this script:
//
//  * Keyboard input after the LiveCD's SYSLINUX/MEMDISK boot is intermittently
//    dead for a whole boot. We gate every boot behind an input self-test and
//    hard-reboot (stop_force + start) until the keyboard responds. Never press a
//    key during the SYSLINUX menu — let it auto-boot to the Live Environment.
//
//  * Every *destructive* FDI dialog (partition, reboot, format, "install now?")
//    defaults to the safe "No - Return to DOS" option, with "Yes" directly above
//    it, so those need Up+Enter. The non-destructive ones (language, proceed,
//    keyboard, package set) default to what we want, so Enter accepts.
//
// FDISK requires a reboot for the new partition table to take effect, so the
// install runs in two phases (partition+reboot, then format+packages) — setup is
// relaunched from the live prompt after the reboot.

use vmlab

// Let the SYSLINUX menu auto-boot into the Live Environment (a keypress here can
// wedge keyboard input), then wait for the live prompt banner.
fn boot_to_live(vm: Vm, lab: Lab) -> Result[unit, string] {
    vm.wait_for_text("SETUP", 300)?
    vmlab::sleep_ms(6000)
    Ok(())
}

// Ok if the keyboard registers (echo a marker and see it), Err if it looks dead.
fn try_live_input(vm: Vm, lab: Lab) -> Result[unit, string] {
    for t in 0..3 {
        vm.type_text("echo zztop\n")?
        match vm.wait_for_text("zztop", 8) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(1000),
        }
    }
    Err("input appears dead")
}

// Boot to the live prompt with a working keyboard, hard-rebooting past boots that
// don't reach the prompt or come up with dead input.
fn boot_until_input(vm: Vm, lab: Lab) -> Result[unit, string] {
    for attempt in 0..8 {
        match boot_to_live(vm, lab) {
            Ok(_) => {
                vmlab::sleep_ms(3000)
                match try_live_input(vm, lab) {
                    Ok(_)  => { lab.log("live prompt ready, keyboard responding"); return Ok(()) },
                    Err(_) => lab.log("keyboard dead this boot; hard-rebooting"),
                }
            }
            Err(_) => lab.log("boot did not reach live prompt; hard-rebooting"),
        }
        vm.stop_force()?
        vmlab::sleep_ms(3000)
        vm.start()?
    }
    Err("no working keyboard input after several reboots")
}

// Type setup.bat at the live prompt until the FDI language screen appears.
fn launch_setup(vm: Vm, lab: Lab) -> Result[unit, string] {
    for attempt in 0..6 {
        vm.type_text("setup.bat\n")?
        match vm.wait_for_text("preferred language", 30) {
            Ok(_)  => return Ok(()),
            Err(_) => { lab.log("setup.bat did not start, retrying"); vmlab::sleep_ms(2000) }
        }
    }
    Err("setup.bat never launched")
}

// Press Enter until `expect` appears (retries dropped keystrokes).
fn enter_until(vm: Vm, expect: string, timeout: int) -> Result[unit, string] {
    for attempt in 0..8 {
        vm.send_keys("enter")?
        match vm.wait_for_text(expect, timeout) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(500),
        }
    }
    Err("never reached screen matching: " + expect)
}

// Select "Yes" on a destructive dialog: it sits one line above the highlighted
// default "No", so move up then confirm.
fn choose_yes(vm: Vm) -> Result[unit, string] {
    vm.send_keys("up")?
    vmlab::sleep_ms(1200)
    vm.send_keys("enter")?
    Ok(())
}

// Wait (up to ~25 min) for the install to finish, logging progress as it copies
// packages. The completion screen is a dialog that waits for input.
fn wait_install_done(vm: Vm, lab: Lab) -> Result[unit, string] {
    for i in 0..50 {
        match vm.wait_for_text("now complete|reboot now|been installed", 30) {
            Ok(_)  => return Ok(()),
            Err(_) => match vm.ocr() {
                Ok(t)  => lab.log("installing: " + t),
                Err(_) => {},
            },
        }
    }
    Err("install never reported completion")
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // --- Phase 1: language -> proceed -> partition -> reboot -----------------
    lab.log("booting LiveCD (phase 1)")
    boot_until_input(vm, lab)?
    launch_setup(vm, lab)?
    enter_until(vm, "proceed", 30)?                 // English -> welcome/proceed
    enter_until(vm, "partition your drive", 30)?    // proceed Yes -> partition
    lab.log("partitioning C:")
    choose_yes(vm)?                                  // Yes - partition drive C:
    vm.wait_for_text("must reboot", 30)?
    lab.log("rebooting for new partition table")
    choose_yes(vm)?                                  // Yes - reboot now

    // --- Phase 2: format -> keyboard -> Full packages -> install -------------
    lab.log("booting LiveCD (phase 2)")
    boot_until_input(vm, lab)?
    launch_setup(vm, lab)?
    enter_until(vm, "proceed", 30)?                 // English -> proceed
    vm.send_keys("enter")?                           // proceed Yes -> format dialog
    vm.wait_for_text("format your drive", 30)?
    lab.log("formatting C:")
    choose_yes(vm)?                                  // Yes - erase and format C:
    vm.wait_for_text("keyboard layout", 90)?
    vm.send_keys("enter")?                           // UK English (default)
    vm.wait_for_text("packages do you want", 30)?
    lab.log("selecting Full installation (applications + games)")
    vm.send_keys("enter")?                           // default = Full incl. apps + games
    vm.wait_for_text("ready to install", 30)?
    lab.log("installing packages")
    choose_yes(vm)?                                  // Yes - install now
    wait_install_done(vm, lab)?

    // --- Seal ----------------------------------------------------------------
    // Don't reboot into the installer. FreeDOS has no ACPI, so a clean QMP quit
    // is what flushes the disk (a SIGKILL would drop unflushed qcow2 writes and
    // leave the image unbootable).
    lab.log("FreeDOS 1.3 installed to C:; powering off to seal")
    vmlab::sleep_ms(4000)
    vm.poweroff()?
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
            failed.expect("freedos-1.3 build failed: " + e)
        },
    }
}
