// Drives the throwaway install lab fetch-deps.sh brings up: the live SteamOS
// recovery image has no agent, so everything goes through the console. Waits
// for the recovery desktop, opens Konsole, runs installer/payload/install.sh
// from the STEAMINST ISO, and stops the VM once it reports success.

use vmlab

// OCR cannot read the desktop's white-on-wallpaper icon labels, so there is
// no reliable "desktop is up" text. Konsole's welcome text on its dark
// background is readable: ask KRunner for Konsole until it shows. The prompt
// itself is not a usable marker (OCR reads deck@steamdeck as
// "deckesteandeck"), so several phrases of the welcome text count.
fn open_konsole(lab: Lab, vm: Vm) -> Result[unit, string] {
    for i in 0..30 {
        vm.send_keys("alt-f2")?
        vmlab::sleep_ms(3000)
        vm.type_text("konsole\n")?
        match vm.wait_for_text("repair_device|recovery image|Reinstallation tools", 20) {
            Ok(m)  => return Ok(()),
            Err(e) => {
                if i == 0 { lab.log("no Konsole yet; the desktop is still starting") }
            }
        }
    }
    Err("Konsole never opened on the recovery desktop")
}

fn install(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("installer")?

    lab.log("waiting for the recovery image's desktop...")
    vmlab::sleep_ms(45000)
    open_konsole(lab, vm)?

    lab.log("running the installer (repair_device.sh onto the target disk)...")
    vm.type_text("sudo mkdir -p /run/steaminst && sudo mount -o ro /dev/disk/by-label/STEAMINST /run/steaminst && sudo bash /run/steaminst/install.sh\n")?

    // Loose on purpose: OCR drops or swaps single letters.
    let m = vm.wait_for_text("install.{{0,2}}d.ne|install.{{0,2}}fa.led|Imaging err", 3600)?
    if m.text.contains("fa") || m.text.contains("err") {
        vm.screenshot("install-failed.png")?
        return Err("the SteamOS install failed; fetch-deps.sh keeps the screen as disk/install-failed.png")
    }
    lab.log("installed; stopping the install VM")
    vm.stop()?
    Ok(())
}

fn main(lab: Lab) {
    match install(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("steamos install failed: " + e)
        },
    }
}
