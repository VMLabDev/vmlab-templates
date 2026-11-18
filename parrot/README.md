# parrot

Parrot OS Security edition 7.4 from the official prebuilt QEMU qcow2.

- Credentials: `parrot` (image default account, password per clone) plus `vmlab` with a password per clone (see [Login password](#login-password))
  (added by the provision, in sudo group). SSH enabled.
- vmlab-agent: Parrot's QEMU image has no cloud-init or unattended-install
  hook, so `fetch-deps.sh` offline-injects a `virt-customize` firstboot
  command that mounts the VMLAB bootstrap ISO (attached during the build)
  and runs its `install.sh`. The agent is up and verified before the
  provision runs, and the install is baked into the sealed image so clones
  come up "ready". **Requires `virt-customize` (libguestfs) on the build
  host.**
- Parrot distributes the image compressed with xz — run `./fetch-deps.sh` once to
  download, sha256-verify, extract `disk/parrot.qcow2` and inject the agent
  bootstrap (all gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `signed-hashes.txt` under <https://deb.parrot.sh/parrot/iso/>) and
  `version` in `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```

## Login password

Each clone gets its own password for `vmlab` and `parrot` at its first boot
(`scripts/firstboot.ws`), before the clone is reported ready, so no lab
starts with the published build password.

- To choose the password, declare a login for the account on the machine in
  the lab file: `login "vmlab" { user = "vmlab" password = "..." }`. The
  first boot sets it. The same works for `parrot`. A declared login also becomes the default
  identity of `vmlab exec` and `vmlab shell` on that machine.
- An account without a declared password gets a random 20-character
  password. Both accounts get the same generated password. Read it with
  `vmlab exec <vm> -- cat /root/vmlab-password` (the file is root only).
- To change it later: `vmlab exec <vm> -- sh -c 'echo vmlab:NEWPASS | chpasswd'`.

`vmlab exec`, `vmlab shell` and provisions go through the guest agent, which
runs as root and needs no password.
