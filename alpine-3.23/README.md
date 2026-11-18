# alpine-3.23

Alpine Linux 3.23 built from the official NoCloud cloud image (UEFI +
cloud-init variant).

- Credentials: `vmlab` with a password per clone (see [Login password](#login-password)) (passwordless sudo via wheel, `sudo`
  installed by the seed), SSH password auth on.
- vmlab guest agent installed and added to the default runlevel.
- To bump: pick the `nocloud_alpine-*-x86_64-uefi-cloudinit-r*.qcow2`
  from <https://dl-cdn.alpinelinux.org/alpine/> under
  `releases/cloud/`, verify its `.sha512`, compute the sha256 and update
  `vmlab.wcl`.

```sh
vmlab template build
```

## Login password

Each clone gets its own password for `vmlab` at its first boot
(`scripts/firstboot.ws`), before the clone is reported ready, so no lab
starts with the published build password.

- To choose the password, declare a login for the account on the machine in
  the lab file: `login "vmlab" { user = "vmlab" password = "..." }`. The
  first boot sets it. A declared login also becomes the default
  identity of `vmlab exec` and `vmlab shell` on that machine.
- An account without a declared password gets a random 20-character
  password. Read it with
  `vmlab exec <vm> -- cat /root/vmlab-password` (the file is root only).
- To change it later: `vmlab exec <vm> -- sh -c 'echo vmlab:NEWPASS | chpasswd'`.

`vmlab exec`, `vmlab shell` and provisions go through the guest agent, which
runs as root and needs no password.
