# nixos-25.11

NixOS 25.11 installed from the official minimal ISO with a scripted
`nixos-install`.

- Credentials: `vmlab` with a password per clone (see [Login password](#login-password)) (passwordless sudo via wheel); root login
  locked. SSH password auth on.
- vmlab guest agent enabled (`services.qemuGuest`).
- System config baked from `nix/configuration.nix`
  (`system.stateVersion = "25.11"`); the generated
  `hardware-configuration.nix` is kept.
- To bump: resolve
  `https://channels.nixos.org/nixos-<ver>/latest-nixos-minimal-x86_64-linux.iso`
  to its pinned releases.nixos.org URL, take the sha256 from the `.sha256`
  file next to it, and update `vmlab.wcl` plus `stateVersion`.

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
