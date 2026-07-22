// Build provision for the parrot template. Parrot's prebuilt QEMU image has no
// cloud-init or unattended-install hook, so fetch-deps.sh offline-injects a
// virt-customize firstboot command that runs the VMLAB bootstrap ISO's
// install.sh — vmlab-agent is therefore up and verified before this provision
// runs. Here we just wait for the agent, add the vmlab user and enable SSH
// before the image is sealed.

use vmlab

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("waiting for the vmlab-agent (installed by the firstboot bootstrap)...")
    vm.wait_ready(900)?
    lab.log("guest agent is up")

    let r = vm.exec_timeout("/bin/sh", [
        "-c",
        "id vmlab >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo vmlab; echo vmlab:vmlab | chpasswd; systemctl enable --now ssh",
    ], 300)?
    if r.exit_code != 0 {
        return Err("user/ssh setup failed: " + r.stderr)
    }
    lab.log("vmlab user created, SSH enabled")
    Ok(())
}

fn main(lab: Lab) {
    provision(lab).expect("parrot build failed")
}
