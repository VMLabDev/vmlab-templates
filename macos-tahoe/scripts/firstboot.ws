// First-boot provision for macos-tahoe clones: give the clone its own
// identity before it turns ready. macOS has no sysprep; what a clone shares
// with the template and must not keep is its name. Every clone gets its VM's
// name as ComputerName, LocalHostName (Bonjour) and HostName.
//
// SSH is off in the template, which carries no host keys. If sshd is enabled
// here anyway (a clone of a clone, or a lab that turned it on before the
// first boot ran), the host keys are regenerated so no two clones share them.

use vmlab

fn sh(vm: Machine, cmd: string) -> Result[string, string] {
    let r = vm.exec_timeout("/bin/sh", ["-c", cmd], 120)?
    if r.exit_code != 0 {
        return Err(fmt("`{}` exited {}: {}{}", cmd, r.exit_code, r.stdout, r.stderr))
    }
    Ok(r.stdout.trim())
}

fn identity(lab: Lab, vm: Machine) -> Result[unit, string] {
    vm.wait_ready(900)?
    // A VM name is a DNS label, which every one of the three names accepts.
    let name = vm.name()
    let set = sh(vm, "scutil --set ComputerName '" + name + "' && scutil --set LocalHostName '" + name + "' && scutil --set HostName '" + name + "'")?
    lab.log("first-boot: hostname " + name)

    let ssh = sh(vm, "if launchctl print system/com.openssh.sshd >/dev/null 2>&1; then rm -f /etc/ssh/ssh_host_* && ssh-keygen -A >/dev/null && launchctl kickstart -k system/com.openssh.sshd && echo regenerated; else echo off; fi")?
    if ssh == "regenerated" {
        lab.log("first-boot: sshd is on; regenerated its host keys")
    }
    Ok(())
}

fn main(lab: Lab) {
    let vm = lab.this_vm().expect("first-boot: no target VM")
    identity(lab, vm).expect("macos-tahoe first boot failed")
}
