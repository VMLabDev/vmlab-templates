# Ubuntu Server 24.04 template

Builds `x86_64/ubuntu-24.04` into the local template store from the
official live-server ISO (downloaded and sha256-verified automatically)
using a subiquity autoinstall config delivered on a CIDATA ISO.

```sh
vmlab validate
vmlab template build
vmlab template list      # → x86_64/ubuntu-24.04@24.04.4
```

What happens (`scripts/install.ws` narrates it in the build log):

1. The build VM boots the installer ISO with `cloudinit/` attached as a
   `CIDATA` volume (NoCloud datasource).
2. The script answers subiquity's "Continue with autoinstall?" prompt via
   OCR + keystrokes.
3. Autoinstall partitions the disk, creates user `vmlab` (build password
   `vmlab`, replaced per clone, see [Login password](#login-password)), installs the vmlab guest agent (from the auto-attached VMLAB ISO), and powers the VM off.
4. vmlab flattens and seals the disk into the store.

Point-release bumps: update `version`, the ISO filename, and `sha256`
(from <https://releases.ubuntu.com/24.04/SHA256SUMS>) in `vmlab.wcl`.

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
