// Build provision for the ubuntu-arm64 template. The genericcloud image
// boots straight into cloud-init, which installs the vmlab guest agent (VMLAB bootstrap ISO) —
// so "the agent answers" doubles as "cloud-init got far enough". We then
// block on `cloud-init status --wait` so the image is only sealed after
// first-boot configuration fully finished. The build shuts the VM down
// gracefully after the provision returns.

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
    // `expect` drops the Err payload, so a bare expect prints the
    // failure and nothing about its cause (windows-11, 2026-09-04: a
    // whole failed build whose reason was never recorded). The cause
    // rides the message instead.
    match provision(lab) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("ubuntu-arm64 build failed: " + e)
        },
    }
}
