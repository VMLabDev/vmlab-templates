// Drive the MS-DOS 6.22 install. The bootable CD lands at A:\> with the CD at
// R: (Oak IDE driver + MSCDEX, banner "Driver BANANA"). We partition + format
// C:, copy the DOS files into C:\DOS, set a PATH, then halt so the build seals
// the bootable C: disk. DOS has no guest agent, so it's driven by the live
// screen.
//
// Real-mode keyboard input is occasionally dropped (and the scripted shift
// modifier is unreliable, so everything typed is lowercase — DOS is
// case-insensitive). Every input that must land is therefore verified against
// the screen (OCR) and retried if the expected result didn't appear; OCR-robust
// markers are used (e.g. "Format complete", not "Volume label" whose V misreads).

use vmlab

// Press Enter until `expect` appears (drives fdisk's default-selected menus).
fn enter_until(vm: Vm, expect: string, timeout: int) -> Result[unit, string] {
    for attempt in 0..8 {
        vm.send_keys("enter")?
        match vm.wait_for_text(expect, timeout) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(400),
        }
    }
    Err("fdisk: never reached screen matching: " + expect)
}

// Type `text`, then confirm `expect` appears, retrying the input if dropped.
fn type_until(vm: Vm, text: string, expect: string, timeout: int) -> Result[unit, string] {
    for attempt in 0..6 {
        vm.type_text(text)?
        match vm.wait_for_text(expect, timeout) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(500),
        }
    }
    Err("never saw expected output: " + expect)
}

// `md` is silent, so create C:\DOS and confirm it via `dir`, retrying.
fn ensure_dos_dir(vm: Vm) -> Result[unit, string] {
    for attempt in 0..5 {
        vm.type_text("md c:\\dos\n")?
        vmlab::sleep_ms(400)
        vm.type_text("dir c:\\\n")?
        match vm.wait_for_text("DOS", 8) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(400),
        }
    }
    Err("could not create C:\\DOS")
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // CD boots to A:\> — the MSCDEX banner ("Driver BANANA") prints just before.
    vm.wait_for_text("BANANA", 180)?
    vmlab::sleep_ms(2500)

    // Partition C: with fdisk (create primary, max size, active), then reboot.
    lab.log("partitioning C: with fdisk")
    type_until(vm, "fdisk\n", "Set active partition", 20)?   // fdisk main menu
    enter_until(vm, "Create Extended", 6)?                   // -> Create-partition submenu
    enter_until(vm, "maximum available", 6)?                 // -> Create Primary, max-size prompt
    enter_until(vm, "now restart", 6)?                       // accept [Y] -> "now restart"
    enter_until(vm, "BANANA", 60)?                           // press-any-key -> reboot -> A:\>
    vmlab::sleep_ms(2500)

    // Format C: with system files -> bootable.
    lab.log("formatting C: /s")
    type_until(vm, "format c: /s\n", "Proceed with Format", 20)?
    type_until(vm, "y\n", "Format complete", 120)?
    type_until(vm, "\n", "Serial Number", 30)?               // no volume label
    vmlab::sleep_ms(1500)

    // Create C:\DOS and copy the utilities there.
    lab.log("copying DOS files to C:\\DOS")
    ensure_dos_dir(vm)?
    type_until(vm, "copy r:\\*.* c:\\dos\n", "copied", 120)?
    vmlab::sleep_ms(1500)

    // PATH so the DOS utilities resolve (lowercase; DOS is case-insensitive).
    write_path(vm)?

    // DOS has no ACPI, so the build's graceful stop can't power it off. A clean
    // QMP quit exits QEMU *and flushes the disk* (a SIGKILL would drop unflushed
    // qcow2 writes and leave the image unbootable).
    lab.log("MS-DOS 6.22 installed to C:; powering off to seal")
    vmlab::sleep_ms(3000)
    vm.poweroff()?
    Ok(())
}

// Write a PATH into C:\AUTOEXEC.BAT and verify it stuck, retrying the echo.
fn write_path(vm: Vm) -> Result[unit, string] {
    for attempt in 0..5 {
        vm.type_text("echo path c:\\dos> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(400)
        vm.type_text("type c:\\autoexec.bat\n")?
        match vm.wait_for_text("path c", 8) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(400),
        }
    }
    Err("could not write C:\\AUTOEXEC.BAT")
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
            failed.expect("dos-6.22 build failed: " + e)
        },
    }
}
