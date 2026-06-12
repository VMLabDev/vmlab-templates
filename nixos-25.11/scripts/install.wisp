// Build provision for the nixos-25.11 template. The minimal installer ISO
// boots (GRUB default entry) into an auto-logged-in `nixos` shell on tty1.
// We wait for that prompt via OCR, type a single command that mounts the
// NIXSETUP media ISO and hands off to install.sh, then wait for the
// installer to power the VM off.

use vmlab

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    // Nudge GRUB past its menu timeout if it is on screen.
    match vm.wait_for_text("(?i)nixos", 180) {
        Ok(_) => {
            vm.send_keys("enter")?
            lab.log("selected the installer GRUB entry")
        }
        Err(e) => lab.log("no GRUB menu seen, continuing: " + e),
    }

    // The live environment auto-logs-in as nixos on tty1.
    match vm.wait_for_text("(?i)nixos@nixos", 600) {
        Ok(_)  => lab.log("installer shell is up"),
        Err(e) => {
            // OCR can mangle the prompt; give the boot a fixed grace period
            // and try typing anyway — a failed mount just times the build out.
            lab.log("never OCR'd the shell prompt, typing blind after a grace period: " + e)
            vmlab::sleep_ms(60000)
        }
    }

    vm.type_text("sudo sh -c 'mkdir -p /m && mount -o ro /dev/disk/by-label/NIXSETUP /m && sh /m/install.sh'\n")?
    lab.log("install.sh started (partition + nixos-install, takes a while)...")

    match vm.wait_shutdown(5400) {
        Ok(_)  => lab.log("installer powered the VM off; ready to seal"),
        Err(e) => {
            // Snapshot the console so the failure is diagnosable from logs.
            match vm.ocr() {
                Ok(text) => lab.log("install never finished; screen reads:\n" + text),
                Err(o)   => lab.log("install never finished and OCR failed: " + o),
            }
            return Err(e)
        }
    }
    Ok(())
}

fn main(lab: Lab) {
    provision(lab).expect("nixos-25.11 build failed")
}
