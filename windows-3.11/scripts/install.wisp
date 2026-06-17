// Install Windows for Workgroups 3.11 onto the dos-6.22 base disk.
//
// The build seeds C: from the bootable MS-DOS 6.22 template, whose C:\DOS
// already holds the Oak IDE CD driver (cd1.sys) + MSCDEX (copied there from the
// DOS install CD). The WIN311 media CD carries a *pre-installed* WfW 3.11 tree
// (its SYSTEM.INI patched to the generic VGA driver by fetch-deps.sh). We:
//   1. mount the CD at R: by writing a CD-aware config.sys/autoexec + rebooting,
//   2. xcopy the WINDOWS/WIN32APP trees onto C:,
//   3. write the final boot config (HIMEM for enhanced mode; autoexec launches
//      Windows), reboot, and verify Program Manager appears,
//   4. exit Windows back to DOS and poweroff so the qcow2 is flushed (a SIGKILL
//      would drop unflushed writes and leave the image unbootable).
//
// DOS has no guest agent, so everything is driven over the live screen (VNC
// input + OCR). Real-mode keyboard input is occasionally dropped, so every
// input that must land is verified against the screen and retried. Everything
// typed is lowercase — DOS is case-insensitive and the scripted shift modifier
// is unreliable; the MSCDEX /D:banana label matches config.sys's, both lower.

use vmlab

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

// Warm-reboot (Ctrl+Alt+Del keeps QEMU alive, so disk writes in the block cache
// survive) and wait for `expect` to confirm the reboot reached the target state.
fn reboot_until(vm: Vm, expect: string, timeout: int) -> Result[unit, string] {
    for attempt in 0..3 {
        vm.send_keys("ctrl-alt-del")?
        vmlab::sleep_ms(2500)
        match vm.wait_for_text(expect, timeout) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(500),
        }
    }
    Err("reboot never reached screen: " + expect)
}

// Write the CD-driver boot config and verify both files stuck, retrying.
fn write_cd_files(vm: Vm) -> Result[unit, string] {
    for attempt in 0..5 {
        vm.type_text("echo device=c:\\dos\\cd1.sys /d:banana> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo lastdrive=z>> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo c:\\dos\\mscdex.exe /d:banana /l:r> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo path c:\\dos>> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        // Verify with OCR-robust words (no digits — OCR misreads "cd1" as "cdl").
        vm.type_text("type c:\\config.sys\n")?
        match vm.wait_for_text("lastdrive", 8) {
            Ok(_) => {
                vm.type_text("type c:\\autoexec.bat\n")?
                match vm.wait_for_text("mscdex", 8) {
                    Ok(_)  => return Ok(()),
                    Err(_) => vmlab::sleep_ms(400),
                }
            }
            Err(_) => vmlab::sleep_ms(400),
        }
    }
    Err("could not write CD-driver config.sys/autoexec.bat")
}

// Write the final boot config: HIMEM for Windows enhanced mode, and an autoexec
// that sets PATH/TEMP, starts the disk cache, and launches Windows.
fn write_final_files(vm: Vm) -> Result[unit, string] {
    for attempt in 0..5 {
        vm.type_text("echo device=c:\\dos\\himem.sys> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo files=30>> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo buffers=20>> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo lastdrive=z>> c:\\config.sys\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo path c:\\dos;c:\\windows> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo set temp=c:\\windows\\temp>> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo c:\\windows\\smartdrv.exe>> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        vm.type_text("echo win>> c:\\autoexec.bat\n")?
        vmlab::sleep_ms(300)
        vm.type_text("type c:\\config.sys\n")?
        match vm.wait_for_text("himem", 8) {
            Ok(_) => {
                vm.type_text("type c:\\autoexec.bat\n")?
                match vm.wait_for_text("smartdrv", 8) {
                    Ok(_)  => return Ok(()),
                    Err(_) => vmlab::sleep_ms(400),
                }
            }
            Err(_) => vmlab::sleep_ms(400),
        }
    }
    Err("could not write final config.sys/autoexec.bat")
}

// Pre-create the target dir (so xcopy doesn't ask file-or-directory), then copy
// `src` -> `dst` recursively (incl. empty dirs). DOS 6.22 xcopy overwrites
// silently, so the retry is safe after a partial copy.
fn copy_dir(vm: Vm, src: string, dst: string) -> Result[unit, string] {
    for attempt in 0..3 {
        vm.type_text("md " + dst + "\n")?
        vmlab::sleep_ms(400)
        vm.type_text("xcopy " + src + " " + dst + " /s /e\n")?
        match vm.wait_for_text("copied", 300) {
            Ok(_)  => return Ok(()),
            Err(_) => vmlab::sleep_ms(1000),
        }
    }
    Err("xcopy failed for " + src)
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // The dos-6.22 seed boots to C:\> (its autoexec just sets PATH). Give it
    // time, then confirm the prompt is responsive.
    lab.log("waiting for the MS-DOS base to boot")
    vmlab::sleep_ms(9000)
    type_until(vm, "ver\n", "MS-DOS", 60)?

    // Mount the WIN311 media CD at R: (cd1.sys prints a BANANA banner at boot).
    lab.log("configuring CD-ROM access (cd1.sys + MSCDEX) and rebooting")
    write_cd_files(vm)?
    reboot_until(vm, "BANANA", 120)?
    vmlab::sleep_ms(3000)
    type_until(vm, "ver\n", "MS-DOS", 60)?

    // Copy the pre-installed Windows tree from the CD onto C:.
    lab.log("copying the Windows for Workgroups 3.11 tree to C: (~34 MB)")
    copy_dir(vm, "r:\\windows", "c:\\windows")?
    copy_dir(vm, "r:\\win32app", "c:\\win32app")?
    type_until(vm, "copy r:\\windows.bat c:\\\n", "copied", 30)?

    // Final boot config, then reboot straight into Windows.
    lab.log("writing the Windows boot configuration")
    vm.type_text("md c:\\windows\\temp\n")?
    vmlab::sleep_ms(500)
    write_final_files(vm)?

    lab.log("rebooting into Windows to verify Program Manager")
    reboot_until(vm, "Program Manager", 240)?
    vmlab::sleep_ms(2000)
    let shot = vm.screenshot("")?
    lab.log("Windows 3.11 desktop reached; screenshot: " + shot)

    // Exit Windows back to DOS so the disk seals with a clean poweroff.
    lab.log("exiting Windows to DOS to seal the disk")
    vm.send_keys("alt-f4")?           // Program Manager -> "Exit Windows" dialog
    vmlab::sleep_ms(1500)
    vm.send_keys("enter")?            // confirm OK
    vmlab::sleep_ms(4000)
    type_until(vm, "ver\n", "MS-DOS", 60)?

    lab.log("Windows for Workgroups 3.11 installed to C:; powering off to seal")
    vmlab::sleep_ms(2000)
    vm.poweroff()?
    Ok(())
}

fn main(lab: Lab) {
    install(lab).expect("windows-3.11 build failed")
}
