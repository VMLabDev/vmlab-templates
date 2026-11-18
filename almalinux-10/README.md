# AlmaLinux 10 template

Builds `x86_64/almalinux-10` into the local template store from the official
AlmaLinux **GenericCloud** image + cloud-init. AlmaLinux and Rocky are the
two community RHEL rebuilds; this pairs with the `rocky-9` template.

```sh
vmlab validate
vmlab template build
vmlab template list      # → x86_64/almalinux-10@10.2
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the cloud image with `cloudinit/` attached as a
   `CIDATA` volume (NoCloud datasource).
2. cloud-init creates user `vmlab` (build password `vmlab`, replaced per clone, see [Login password](#login-password); passwordless sudo),
   installs the vmlab guest agent (from the auto-attached VMLAB ISO), enables it, and disables cloud-init for
   subsequent boots.
3. The script waits for the guest agent to respond and cloud-init to finish.
4. vmlab powers the VM off and seals the disk into the store.

Point-release bumps: update `version`, the image filename in `url`, and
`sha256` (from the `CHECKSUM` beside the image under
<https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/>).

The profile is `linux-modern` with `firmware = "seabios"` — cloud images
boot via BIOS. Note RHEL 10 requires an x86-64-v3 host CPU.

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
