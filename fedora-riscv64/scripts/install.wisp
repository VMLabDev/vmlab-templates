// Build provision for the fedora-42 (riscv64) template. Fedora/EL block
// guest-exec in the agent by default; cloud-init's runcmd clears the filter
// and restarts the agent. So the agent may answer pings while exec is still
// blocked — poll exec until it goes through, then block on `cloud-init
// status --wait` so the image is only sealed after first-boot configuration
// fully finished. The build shuts the VM down gracefully afterwards.

use vmlab

fn wait_exec_usable(lab: Lab, vm: Vm) -> Result[unit, string] {
    for i in 0..90 {
        match vm.exec("/bin/true", []) {
            Ok(r)  => return Ok(()),
            Err(e) => {
                if i == 0 { lab.log("exec not usable yet: " + e) }
                vmlab::sleep_ms(10000)
            }
        }
    }
    Err("guest-exec never became available (RPC filter still active?)")
}

fn provision(lab: Lab) -> Result[unit, string] {
    let vm = lab.vm("build")?

    lab.log("waiting for the guest agent...")
    vm.wait_ready(1500)?
    lab.log("agent answers pings; waiting for guest-exec to be unblocked...")
    wait_exec_usable(lab, vm)?
    lab.log("guest-exec works")

    wait_cloud_init_done(lab, vm)
}

// The cloud-init CLI is not reliably runnable through the agent on
// Fedora/EL, so wait for /run/cloud-init/result.json (written when the
// final stage completes) and inspect its error list instead.
fn wait_cloud_init_done(lab: Lab, vm: Vm) -> Result[unit, string] {
    for i in 0..120 {
        let r = vm.exec("/bin/sh", ["-c", "test -f /run/cloud-init/result.json"])?
        if r.exit_code == 0 { break }
        vmlab::sleep_ms(10000)
    }

    let chk = vm.exec("/usr/bin/python3", [
        "-c",
        "import json,sys; e=json.load(open('/run/cloud-init/result.json'))['v1']['errors']; print(e); sys.exit(1 if e else 0)",
    ])?
    if chk.exit_code != 0 {
        match vm.exec("/bin/sh", ["-c", "grep -iE 'error|fail|traceback' /var/log/cloud-init.log | tail -n 20"]) {
            Ok(d)  => lab.log("cloud-init log tail:\n" + d.stdout),
            Err(e) => lab.log("could not read cloud-init.log: " + e),
        }
        return Err("cloud-init reported errors: " + chk.stdout)
    }
    lab.log("cloud-init finished without errors")
    Ok(())
}

fn main(lab: Lab) {
    provision(lab).expect("fedora-42 riscv64 build failed")
}
