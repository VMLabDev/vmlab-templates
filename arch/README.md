# Arch Linux template

Builds `x86_64/arch` into the local template store from the official Arch
**cloud image** (downloaded and sha256-verified automatically). Arch has no
unattended ISO installer, so this uses the cloud image + cloud-init instead
of an installer dance.

```sh
vmlab validate
vmlab template build
vmlab template list      # → x86_64/arch@20260601
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the cloud image with `cloudinit/` attached as a
   `CIDATA` volume (NoCloud datasource).
2. cloud-init creates user `vmlab` (build password `vmlab`, replaced per clone, see [Login password](#login-password); passwordless sudo),
   installs the vmlab guest agent (from the auto-attached VMLAB ISO), enables it, and disables cloud-init for
   subsequent boots.
3. The script waits for the guest agent to respond (proof the install
   landed) and for cloud-init to finish.
4. vmlab powers the VM off and seals the disk into the store.

Arch is a rolling release, so this pins a dated image. To refresh, pick a
newer `vYYYYMMDD.N` directory from
<https://geo.mirror.pkgbuild.com/images/> and update `url`, `sha256` (from
the `.SHA256` beside the image), and `version` in `vmlab.wcl`.

The profile is `linux-modern` with `firmware = "seabios"` — cloud images
boot via BIOS. If a future image is UEFI-only, switch to `firmware =
"ovmf"`.

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
