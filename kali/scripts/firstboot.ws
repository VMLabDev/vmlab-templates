// First-boot provision: gives every clone its own login password, so no lab
// made from this template opens with a published, known login. vmlab runs it
// once on each clone, before the clone is reported ready. The image still
// carries the build password; each clone replaces it here.
//
// An account takes the password of a `login {}` block the lab declares for it
// on the machine (`login "vmlab" { user = "vmlab" password = "..." }`). An
// account the lab declares no password for gets a random 20-character
// password, generated in the guest and written to /root/vmlab-password (mode
// 0600). Read it with:
//
//   vmlab exec <vm> -- cat /root/vmlab-password
//
// The accounts are vmlab and the image's own kali account. The template
// declares no logins, so every login seen here is the lab's.
// The vmlab guest agent runs as root and its authentication does not change,
// so `vmlab exec`, `vmlab shell` and provisions work whatever the password.

use vmlab

// Sets each account named in the arguments (pairs: account, password). An
// empty password means "generate". Accounts the image lacks are skipped. The
// generated password is written to the file only when an account took it.
fn set_script() -> string {
    "export PATH=/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH; set -e; umask 077; gen=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20); [ -n \"$gen\" ]; used=; while [ $# -ge 2 ]; do u=$1; p=$2; shift 2; if ! id \"$u\" >/dev/null 2>&1; then echo \"skipped $u (no such account)\"; continue; fi; src=lab; if [ -z \"$p\" ]; then p=$gen; used=1; src=generated; fi; printf '%s:%s\\n' \"$u\" \"$p\" | chpasswd; echo \"set $u ($src)\"; done; if [ -n \"$used\" ]; then printf '%s\\n' \"$gen\" > /root/vmlab-password; chmod 600 /root/vmlab-password; else rm -f /root/vmlab-password; fi"
}

// The password the lab declares for an account, or "" for none.
fn declared(vm: Vm, account: string) -> string {
    for login in vm.logins() {
        if login.user == account {
            let Some(p) = login.password else { continue }
            return p
        }
    }
    ""
}

fn set_passwords(lab: Lab, vm: Vm) -> Result[unit, string] {
    vm.wait_ready(900)?
    let r = vm.exec_timeout("/bin/sh", ["-c", set_script(), "sh", "vmlab", declared(vm, "vmlab"), "kali", declared(vm, "kali")], 120)?
    if r.exit_code != 0 {
        return Err(fmt("setting the login password exited {}: {}", r.exit_code, r.stderr.trim()))
    }
    lab.log("first-boot: login password: " + r.stdout.trim())
    if r.stdout.contains("(generated)") {
        lab.log("first-boot: read the generated password with: vmlab exec " + vm.name() + " -- cat /root/vmlab-password")
    }
    Ok(())
}

fn main(lab: Lab) {
    let vm = lab.this_vm().expect("first-boot: no target VM")
    match set_passwords(lab, vm) {
        Ok(u)  => u,
        Err(e) => {
            let failed: Result[unit, string] = Err(e)
            failed.expect("first-boot failed: " + e)
        },
    }
}
