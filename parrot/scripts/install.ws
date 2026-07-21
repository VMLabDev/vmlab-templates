// Build provision for the parrot template. Whether Parrot's QEMU image
// bundles the guest agent varies by release, so: wait for the agent, and
// if it never answers do a blind text-console login (parrot/parrot on
// tty2) to install it. Either way we add the vmlab user and enable SSH
// before the image is sealed.

use vmlab

fn console_fallback(lab: Lab, vm: Vm) -> Result[unit, string] {
    lab.log("guest agent never answered; trying a blind console install via tty2")
    vm.send_keys("ctrl-alt-f2")?
    vmlab::sleep_ms(5000)
    vm.type_text("parrot\n")?
    vmlab::sleep_ms(5000)
    vm.type_text("parrot\n")?
    vmlab::sleep_ms(8000)
    vm.type_text("sudo sh -c 'mkdir -p /media/vmlab && mount -o ro LABEL=VMLAB /media/vmlab && /media/vmlab/install.sh && umount /media/vmlab'\n")?
    vmlab::sleep_ms(3000)
    // sudo may prompt for the password depending on image policy.
    vm.type_text("parrot\n")?
    vm.wait_ready(900)
}

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("waiting for the guest agent...")
    match vm.wait_ready(600) {
        Ok(_)  => lab.log("guest agent is up"),
        Err(e) => console_fallback(lab, vm)?,
    }

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
