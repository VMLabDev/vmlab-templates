# kali

Kali Linux (rolling, 2026.1) from the official prebuilt QEMU image.

- Credentials: `kali` (image default account, password per clone) plus `vmlab` with a password per clone (see [Login password](#login-password))
  (added by the provision, in sudo group). SSH enabled.
- vmlab-agent: Kali's QEMU image has no cloud-init or unattended-install
  hook, so `fetch-deps.sh` offline-injects a `virt-customize` firstboot
  command that mounts the VMLAB bootstrap ISO (attached during the build)
  and runs its `install.sh`. The agent is up and verified before the
  provision runs, and the install is baked into the sealed image so clones
  come up "ready". **Requires `virt-customize` (libguestfs) on the build
  host.**
- Kali distributes the image as a `.7z`, which vmlab's URL sources cannot
  unpack — run `./fetch-deps.sh` once to download, sha256-verify, extract
  `disk/kali.qcow2` and inject the agent bootstrap (all gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `SHA256SUMS` at <https://cdimage.kali.org/>) and `version` in
  `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```

## Login password

Each clone gets its own password for `vmlab` and `kali` at its first boot
(`scripts/firstboot.ws`), before the clone is reported ready, so no lab
starts with the published build password.

- To choose the password, declare a login for the account on the machine in
  the lab file: `login "vmlab" { user = "vmlab" password = "..." }`. The
  first boot sets it. The same works for `kali`. A declared login also becomes the default
  identity of `vmlab exec` and `vmlab shell` on that machine.
- An account without a declared password gets a random 20-character
  password. Both accounts get the same generated password. Read it with
  `vmlab exec <vm> -- cat /root/vmlab-password` (the file is root only).
- To change it later: `vmlab exec <vm> -- sh -c 'echo vmlab:NEWPASS | chpasswd'`.

`vmlab exec`, `vmlab shell` and provisions go through the guest agent, which
runs as root and needs no password.
