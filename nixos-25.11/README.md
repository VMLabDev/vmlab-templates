# nixos-25.11

NixOS 25.11 installed from the official minimal ISO with a scripted
`nixos-install`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel); root login
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
