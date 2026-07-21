// Build provision for the alpine-3.23 template. cloud-init (present in
// the "cloudinit" image variant) installs the vmlab guest agent (VMLAB bootstrap ISO) on first
// boot; once it answers we block on `cloud-init status --wait` so the
// image is only sealed after first-boot configuration fully finished.
// The build shuts the VM down gracefully after the provision returns.

use vmlab

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("waiting for the guest agent (cloud-init installs it on first boot)...")
    vm.wait_ready(1500)?
    lab.log("guest agent is up")

    let r = vm.exec_timeout("cloud-init", ["status", "--wait"], 1800)?
    lab.log("cloud-init finished: " + r.stdout)
    Ok(())
}

fn main(lab: Lab) {
    provision(lab).expect("alpine-3.23 build failed")
}
