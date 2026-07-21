// Build provision for the home-assistant (aarch64) template. HAOS is a sealed
// appliance with no vmlab guest agent, so we cannot wait_ready/exec against it.
// vmlab's builder always boots the VM and then does a graceful ACPI shutdown
// before sealing, so the only job here is to give HAOS enough time to reach a
// state where it honours the ACPI power button (systemd up) before that
// shutdown lands — otherwise the seal's graceful-stop would time out. Under
// TCG the first boot is slow, hence the generous timed wait. No agent calls.

use vmlab

fn main(lab: Lab) {
    lab.log("HAOS appliance: no guest agent — letting it boot once, then seal.")
    lab.log("waiting for the (TCG) first boot to come up before graceful shutdown...")
    vmlab::sleep_ms(420000)
    lab.log("done waiting; proceeding to seal")
}
