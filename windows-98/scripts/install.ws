// Install Windows 98 from its bootable CD, unattended through B:\MSBATCH.INF,
// and bake vmlab's legacy agent.
//
// The CD's El Torito boot floppy becomes A:, so the answer floppy (built from
// ./answer/ by fetch-deps.sh, key injected from .env) is B:. Setup's own "Start
// Windows 98 Setup from CD-ROM" path partitions and formats the blank disk, but
// takes no answer file, so it is used for that and quit: at the welcome screen
// of the third pass, F3 twice drops to a prompt with the CD driver loaded.
// B:\VMLAB.BAT then copies the patched \WIN98 folder (see fetch-deps.sh) from
// the VMLABSRC CD to C:\WIN98 and runs Setup there with B:\MSBATCH.INF.
//
// Every boot shows the CD's "Boot from Hard Disk / Boot from CD-ROM" menu,
// which falls to the hard disk after ten seconds. Nothing is pressed during
// the install's own reboots, so they boot the disk.
//
// MSBATCH.INF registers COMMAND.COM /F /C C:\VMLAB\BOOT.BAT under
// RunServices. At every boot until the agent exists it runs the VMLAB
// bootstrap ISO's install-9x.bat, which copies the legacy agent to C:\VMLAB
// and registers it under RunServices, so it answers on COM1 before anyone logs
// on. The build script waits for that answer; the builder then verifies the
// handshake and seals with a graceful shutdown.

use vmlab

// The screen's text, or nothing when OCR fails.
fn screen(vm: Vm) -> string {
    match vm.ocr() {
        Ok(t) => t,
        Err(_) => "",
    }
}

// Wait until `expect` is on screen.
fn wait_text(vm: Vm, expect: string, secs: int) -> Result[unit, string] {
    match vm.wait_for_text(expect, secs) {
        Ok(_) => Ok(()),
        Err(e) => Err("never saw \"" + expect + "\": " + e),
    }
}

// Press `chord` until `expect` appears; a real-mode TUI drops keys.
fn key_until(vm: Vm, chord: string, expect: string, secs: int) -> Result[unit, string] {
    for attempt in 0..6 {
        vm.send_keys(chord)?
        match vm.wait_for_text(expect, secs) {
            Ok(_) => return Ok(()),
            Err(_) => vmlab::sleep_ms(800),
        }
    }
    Err("never reached the screen showing \"" + expect + "\"")
}

// Answer the CD's boot menu with "Boot from CD-ROM". The menu waits ten
// seconds, then boots the hard disk, which cannot boot until Setup has
// formatted it (a blank disk hangs at a cursor; a partitioned one ends at
// "No bootable device"). So the menu is answered as soon as it shows, the
// boot floppy's own menu ("Enter a choice") proves the CD booted, and
// anything else is reset and tried again.
fn boot_cd(vm: Vm) -> Result[unit, string] {
    for attempt in 0..8 {
        let menu = false
        for poll in 0..400 {
            if screen(vm).contains("Enter your choice") {
                menu = true
                break
            }
        }
        if menu {
            vm.send_keys("2")?
            vm.send_keys("enter")?
            for poll in 0..60 {
                if screen(vm).contains("Enter a choice") {
                    return Ok(())
                }
            }
        }
        vm.send_keys("ctrl-alt-delete")?
        vmlab::sleep_ms(1000)
    }
    Err("the CD never booted from its boot menu")
}

// Type `text`, then confirm `expect` appears, retrying the input if dropped.
fn type_until(vm: Vm, text: string, expect: string, secs: int) -> Result[unit, string] {
    for attempt in 0..5 {
        vm.type_text(text)?
        match vm.wait_for_text(expect, secs) {
            Ok(_) => return Ok(()),
            Err(_) => vmlab::sleep_ms(800),
        }
    }
    Err("typed input never produced \"" + expect + "\"")
}

// Clear the Setup wizard pages MSBATCH.INF does not suppress, until the agent
// answers. Each page is matched by its title and answered with its default.
fn finish_setup(lab: Lab, vm: Vm, secs: int) -> Result[unit, string] {
    let rounds = secs / 15
    for round in 0..rounds {
        if vm.agent_answering() {
            return Ok(())
        }
        let s = screen(vm)
        if s.contains("Product Key you entered is invalid") {
            return Err("Setup rejected WINDOWS_98_OEM_KEY for this media; set an OEM-range key in .env")
        }
        // The key page ("Windows Product Key" on SE, "Product Key" on FE)
        // comes prefilled from MSBATCH.INF; Next submits it.
        let next_page = s.contains("Windows Components") || s.contains("User Information") || s.contains("Product Key") || s.contains("Start Wizard")
        if next_page {
            lab.log("Setup wizard page: Next")
            vm.send_keys("enter")?
        } else if s.contains("Date/Time") || s.contains("Date & Time") || s.contains("Time zone") {
            // MSBATCH.INF's TimeZone does not stop it; Close is the default.
            lab.log("Setup dialog: closing Date/Time Properties")
            vm.send_keys("enter")?
        } else if s.contains("License Agreement") {
            lab.log("Setup wizard page: accepting the license")
            vm.send_keys("alt-a")?
            vmlab::sleep_ms(500)
            vm.send_keys("enter")?
        } else if s.contains("You must install") {
            // The Add Printer Wizard; OCR misses its white-on-blue title.
            lab.log("Setup page: no printer")
            vm.send_keys("esc")?
        } else if s.contains("forgot to enter your user name") {
            vm.send_keys("enter")?
        } else if s.contains("Set Windows Password") {
            // Confirming the new user's (empty) password.
            vm.send_keys("enter")?
        } else if s.contains("Enter Network Password") || s.contains("Enter Windows Password") {
            // The logon dialog is the desktop's, not the agent's: the agent
            // runs under RunServices before it. A user name with an empty
            // password logs on, and is not asked for again.
            lab.log("logon dialog: logging on as vmlab with an empty password")
            vm.type_text("vmlab")?
            vm.send_keys("enter")?
        }
        vmlab::sleep_ms(15000)
    }
    Err("the agent never answered on COM1 after Setup")
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // First pass of Setup from the CD: configure the blank disk, reboot.
    lab.log("partitioning: Setup from the CD configures the blank disk")
    boot_cd(vm)?
    wait_text(vm, "Welcome to Setup", 1800)?
    key_until(vm, "enter", "unallocated", 15)?
    key_until(vm, "enter", "large disk", 15)?
    vm.send_keys("down")?
    key_until(vm, "enter", "restart your computer", 30)?
    vm.send_keys("enter")?

    // Second pass formats the new partition, then quits before ScanDisk.
    lab.log("formatting: Setup's second pass formats C:")
    boot_cd(vm)?
    wait_text(vm, "routine check", 2400)?
    key_until(vm, "esc", "restart your system", 15)?
    vm.send_keys("enter")?

    // Third pass: quit at the welcome screen to the D:\WIN98> prompt.
    lab.log("returning to the prompt with the CD driver loaded")
    boot_cd(vm)?
    wait_text(vm, "Welcome to Setup", 1800)?
    key_until(vm, "f3", "To quit Setup, press F3", 15)?
    vm.send_keys("f3")?
    // OCR misreads the prompt's own text (WIN98> comes back as WINSB>), so
    // `ver` proves the prompt is there: its output says "Version", which the
    // typed command does not (COMMAND.COM expands no %variables% at the
    // prompt, so an echoed sentinel would match its own command line).
    type_until(vm, "cls\nver\n", "Version", 10)?

    // One short command: B:\\VMLAB.BAT stages C:\\VMLAB, copies the patched
    // install folder from the VMLABSRC CD (see fetch-deps.sh) to C: and starts
    // Setup there. Real-mode DOS drops keystrokes, so typing that whole
    // sequence was what failed; the batch's own echo proves it started (OCR
    // reads "vmlab" as "umlab", so the check matches the rest of the line).
    // The CD stays in: its boot floppy is A:, which COMMAND.COM reloads from.
    lab.log("running B:\\VMLAB.BAT: stage C:, copy the patched tree, start Setup")
    type_until(vm, "b:\\vmlab\n", "staging Setup", 30)?

    // File copy, reboots, hardware detection: up to two hours on a loaded host.
    finish_setup(lab, vm, 14400)?
    lab.log("legacy agent answering on COM1")

    // The build verifies the agent's handshake on its own and then seals with
    // a graceful shutdown, which goes through this agent and flushes the disk
    // cache. Shutting down here would race that verification.
    lab.log("Windows 98 installed; the build verifies the agent and seals")
    Ok(())
}

fn main(lab: Lab) {
    match install(lab) {
        Ok(u) => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("windows-98 build failed: " + e)
        },
    }
}
