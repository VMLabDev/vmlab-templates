// Build provision for the macos-tahoe template. A fresh macOS runs no
// unattended hook, so the build drives OpenCore's picker and the Recovery
// Terminal over the screen, and recovery.sh (the MACSETUP ISO) does the work
// inside Recovery. The stages:
//
//   1. Boot the recovery image off the FAT boot disk, open Terminal, run
//      `recovery.sh install`: erase the disk, startosinstall downloads Tahoe
//      from Apple (~12 GB) and reboots into the installer. Wait for Setup
//      Assistant, the installed system's first screen (about an hour).
//   2. Reset into the recovery image again and run `recovery.sh finish`: the
//      vmlab agent and the vmlab/vmlab account, the keyboard type, and
//      OpenCore into the disk's own EFI system partition.
//   3. Reset into the installed system and wait for the agent's handshake;
//      check it and tidy up. vmlab then shuts it down and seals the disk.
//
// The guest has been seen to hang on the way down (a nested kernel panic
// that spins every vCPU; about 2 transitions in 5 on an AMD host with
// OSX-KVM's OpenCore, none so far with this template's), so the build never
// asks it to reboot itself: stages 2 and 3 start with a host reset after a
// sync, and the installer's own reboots are watched for a frozen screen and
// reset from the host when one stalls.

use vmlab

// OpenCore's text picker is read by image, not OCR: its 8x16 console font
// is exact pixel for pixel, and tesseract misreads it ("Dperating Systen").
// The reference crops in images/ come from this picker; entry N is drawn on
// text row N+1, 16 pixels a row.
fn on_screen(vm: Machine, image: string) -> bool {
    match vm.wait_for_image_opts(image, 1, 0.95, [0, 0, 720, 400]) {
        Ok(_) => true,
        Err(_) => false,
    }
}

// From power-on, stop OpenCore's 5 s countdown and hold its picker: any key
// cancels the countdown, so press one every 250 ms until the picker shows.
// A picker that already timed out (it prints "Timeout") booted its default,
// so start over.
fn reach_picker(lab: Lab, vm: Machine) -> Result[unit, string] {
    for attempt in 0..3 {
        for i in 0..400 {
            let k = vm.send_keys("down")
            vmlab::sleep_ms(250)
            if i % 4 == 3 && on_screen(vm, "images/picker-prompt.png") {
                if !on_screen(vm, "images/picker-timeout.png") {
                    return Ok(())
                }
                break
            }
        }
        lab.log(fmt("picker: missed OpenCore's countdown (attempt {}); resetting", attempt + 1))
        reset(lab, vm)?
    }
    Err("never caught the OpenCore picker")
}

// Boot the entry drawn as `image` (a crop of its label); Err when it is not
// listed.
fn choose_entry(lab: Lab, vm: Machine, image: string) -> Result[unit, string] {
    let m = vm.wait_for_image_opts(image, 5, 0.95, [0, 0, 720, 400])?
    let n = m.y / 16 - 1
    lab.log(fmt("picker: booting entry {} ({})", n, image))
    vm.send_keys(fmt("{}", n))?
    vmlab::sleep_ms(3000)
    if on_screen(vm, "images/picker-prompt.png") {
        let k = vm.send_keys("enter")
    }
    Ok(())
}

// Power-cycle from the host: a clean emulator quit (block caches flushed)
// and a fresh start. Never the guest's own reboot, which can hang.
fn reset(lab: Lab, vm: Machine) -> Result[unit, string] {
    vm.poweroff()?
    vmlab::sleep_ms(2000)
    vm.start()?
    Ok(())
}

// Boot the recovery image on the build's FAT boot disk (OpenCore lists it as
// "<volume label> (dmg)"), and wait for Recovery's first window.
fn boot_recovery(lab: Lab, vm: Machine) -> Result[unit, string] {
    reach_picker(lab, vm)?
    choose_entry(lab, vm, "images/entry-dmg.png")?
    vm.wait_for_text("Reinstall macOS|Disk Utility|Time Machine", 900)?
    lab.log("recovery: up")
    vmlab::sleep_ms(5000)
    Ok(())
}

// Utilities > Terminal from the menu bar (1280x800). The shortcut
// shift-cmd-T does not reach Recovery's menu reliably. Terminal is known by
// its title bar ("Terminal — -bash — 120x30"): OCR misses the lone prompt.
fn open_terminal(lab: Lab, vm: Machine) -> Result[unit, string] {
    for attempt in 0..3 {
        vm.mouse_move(243, 14)?
        vm.mouse_click("left")?
        vmlab::sleep_ms(1500)
        vm.mouse_move(248, 96)?
        vm.mouse_click("left")?
        match vm.wait_for_text("bash", 60) {
            Ok(_) => {
                lab.log("recovery: Terminal open")
                vmlab::sleep_ms(2000)
                return Ok(())
            },
            Err(e) => lab.log(fmt("recovery: no Terminal yet (attempt {}): {}", attempt + 1, e)),
        }
        let k = vm.send_keys("esc")
        vmlab::sleep_ms(2000)
    }
    Err("could not open Terminal in Recovery")
}

// Whether the screen still shows `.watch/ref.png`, the frame the last call
// saved; saves the current frame for the next call when it moved on. A
// near-1 threshold, because a live screen may change only by a progress bar
// or one line of text.
fn screen_unchanged(lab: Lab, vm: Machine, have_ref: bool) -> bool {
    let same = if have_ref {
        match vm.wait_for_image_opts(".watch/ref.png", 1, 0.99999, []) {
            Ok(_) => true,
            Err(e) => {
                if e.contains("reference image") {
                    lab.log("watch: " + e)
                }
                false
            },
        }
    } else {
        false
    }
    if !same {
        let s = vm.screenshot(".watch/ref.png")
    }
    same
}

// Stage 1's long wait: startosinstall in Recovery, its reboot, the installer
// boots, until Setup Assistant shows. A screen frozen for 10 minutes is a
// hung guest (recovery.sh prints a heartbeat while it downloads, and the
// installer's progress moves): it is reset from the host and OpenCore is
// pointed at the installer again. Returns how many resets that took.
fn wait_installed(lab: Lab, vm: Machine) -> Result[int, string] {
    let resets = 0
    let still = 0
    let have_ref = false
    for tick in 0..480 {                       // 30 s ticks: 4 hours
        vmlab::sleep_ms(30000)
        let text = match vm.ocr() {
            Ok(t) => t,
            Err(e) => "",
        }
        if text.contains("INSTALL FAILED") {
            return Err("recovery.sh install failed: " + text)
        }
        if text.contains("could not be installed") || text.contains("An error occurred") {
            let s = vm.screenshot(".watch/install-error.png")
            return Err("the macOS installer reported an error: " + text)
        }
        if text.contains("Country or Region") || text.contains("VoiceOver") {
            lab.log(fmt("install: Setup Assistant is up after ~{} min", (tick + 1) / 2))
            return Ok(resets)
        }
        if tick % 10 == 0 {
            lab.log(fmt("install: ~{} min in", tick / 2))
        }
        if screen_unchanged(lab, vm, have_ref) {
            still = still + 1
        } else {
            still = 0
        }
        have_ref = true
        if still >= 20 {
            resets = resets + 1
            let s = vm.screenshot(fmt(".watch/hang-{}.png", resets))
            lab.log(fmt("HANG: screen frozen for 10 min during the install; host reset #{}", resets))
            if resets > 5 {
                return Err("the guest kept hanging during the install")
            }
            resume_install(lab, vm)?
            still = 0
            have_ref = false
        }
    }
    Err("Setup Assistant never appeared within 4 hours")
}

// After a reset mid-install, OpenCore's default entry is what the installer
// last chose (its BootNext, or the volume it blessed), so the picker is left
// to time out into it. With no such choice the default is the firmware's
// option for the FAT boot disk, which is OpenCore itself: it prints
// "Timeout" and stops there. Then pick entry 3, the first entry on the
// target disk (1 and 2 are the boot disk's).
fn resume_install(lab: Lab, vm: Machine) -> Result[unit, string] {
    reset(lab, vm)?
    vmlab::sleep_ms(45000)
    if on_screen(vm, "images/picker-timeout.png") {
        lab.log("picker: no installer default; booting entry 3")
        reset(lab, vm)?
        reach_picker(lab, vm)?
        vm.send_keys("3")?
    }
    Ok(())
}

// Stage 3: the installed system boots from its own ESP's OpenCore. The agent
// answers at the login window; a boot that never gets there is reset once.
fn wait_agent(lab: Lab, vm: Machine) -> Result[int, string] {
    match vm.wait_ready(1200) {
        Ok(_) => return Ok(0),
        Err(e) => {
            let s = vm.screenshot(".watch/no-agent.png")
            lab.log("HANG: no agent 20 min into the first boot (" + e + "); host reset")
        },
    }
    reset(lab, vm)?
    vm.wait_ready(1200)?
    Ok(1)
}

fn sh(lab: Lab, vm: Machine, cmd: string) -> Result[string, string] {
    let r = vm.exec_timeout("/bin/sh", ["-c", cmd], 300)?
    if r.exit_code != 0 {
        return Err(fmt("`{}` exited {}: {}{}", cmd, r.exit_code, r.stdout, r.stderr))
    }
    Ok(r.stdout.trim())
}

fn build(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("stage 1: Recovery, then startosinstall (downloads ~12 GB from Apple; about an hour)")
    boot_recovery(lab, vm)?
    open_terminal(lab, vm)?
    vm.type_text("sh /Volumes/MACSETUP/recovery.sh install\n")?
    let hangs = wait_installed(lab, vm)?

    lab.log("stage 2: Recovery again: agent, account, keyboard, OpenCore into the ESP")
    reset(lab, vm)?
    boot_recovery(lab, vm)?
    open_terminal(lab, vm)?
    vm.type_text("sh /Volumes/MACSETUP/recovery.sh finish\n")?
    // OCR reads Terminal's font loosely ("VHLAB", "vnlab"), so the markers
    // are words and the pattern forgiving.
    let done = vm.wait_for_text("V.LAB FINISH (D.NE|FAIL)", 600)?
    if done.text.contains("FAIL") {
        let text = vm.ocr()?
        return Err("recovery.sh finish failed: " + text)
    }
    lab.log("stage 2: done")

    lab.log("stage 3: first boot of the installed system, from its own ESP")
    reset(lab, vm)?
    let boot_hangs = wait_agent(lab, vm)?
    lab.log("installed: " + sh(lab, vm, "sw_vers | tr '\\n' ' '")?)
    let ver = sh(lab, vm, "sw_vers -productVersion")?
    if !ver.starts_with("26.") {
        return Err("expected macOS Tahoe (26.x), the guest runs " + ver)
    }
    // firstboot.sh (the VMLAB ISO's) creates the account a few seconds into
    // the first boot; it removes its own plist when it is done.
    for i in 0..60 {
        match vm.exec("/bin/sh", ["-c", "id vmlab >/dev/null 2>&1 && ! test -e /Library/LaunchDaemons/dev.vmlab.firstboot.plist"]) {
            Ok(r) => { if r.exit_code == 0 { break } },
            Err(e) => {},
        }
        vmlab::sleep_ms(2000)
    }
    lab.log("account: " + sh(lab, vm, "id vmlab")?)
    lab.log("firstboot: " + sh(lab, vm, "cat /var/log/vmlab-firstboot.log 2>/dev/null | tail -n 3 | tr '\\n' ' '")?)
    lab.log("keyboard: " + sh(lab, vm, "defaults read /Library/Preferences/com.apple.keyboardtype keyboardtype | tr -d '\\n '")?)
    lab.log("opencore: " + sh(lab, vm, "nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | cut -f2 || echo unknown")?)

    // Seal: a generic name (each clone's first boot sets its own), no SSH
    // host keys (sshd is off; a clone that turns it on generates its own),
    // and everything on disk before vmlab's shutdown.
    let tidy = sh(lab, vm, "scutil --set ComputerName macos-tahoe && scutil --set LocalHostName macos-tahoe && scutil --set HostName macos-tahoe && rm -f /etc/ssh/ssh_host_* && sync")?
    // The ~12 GB the installer downloaded is deleted but still on the disk,
    // and the sealed image would carry it. Zero the free space (keeping 4 GB
    // so the system never runs out); the flatten drops zeroed clusters.
    let zero = vm.exec_timeout("/bin/sh", ["-c", "free=$(df -m /System/Volumes/Data | awk 'NR==2 {{print $4}}'); dd if=/dev/zero of=/private/var/tmp/vmlab-zero bs=1m count=$((free - 4096)) 2>&1 | tail -n 1; rm -f /private/var/tmp/vmlab-zero; sync"], 3600)?
    lab.log("zeroed free space: " + zero.stdout.trim())
    lab.log(fmt("build: {} host reset(s) for a stalled install, {} for a stalled first boot", hangs, boot_hangs))
    Ok(())
}

fn main(lab: Lab) {
    match build(lab) {
        Ok(u) => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("macos-tahoe build failed: " + e)
        },
    }
}
