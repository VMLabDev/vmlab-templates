# fedora-42 (riscv64)

Fedora 42 for **riscv64**, built from the official Cloud Base Generic qcow2
with a NoCloud cloud-init seed. Store ref: `riscv64/fedora-42`.

RISC-V is a Fedora **alternative-architecture** port (not officially
supported), currently at release **42** — behind the primary aarch64/x86_64
templates here, which track 44. Images live under
<https://dl.fedoraproject.org/pub/alt/risc-v/release/>.

- Credentials: `vmlab` with a password per clone (see [Login password](#login-password)) (passwordless sudo via wheel), SSH
  password auth on.
- vmlab guest agent enabled with Fedora's RPC filter removed (a systemd
  override drops the blocklist, which otherwise blocks `vmlab exec`/`cp`).
- SELinux is set **permissive**: enforcing denies the guest agent
  exec'ing binaries, which breaks vmlab provisioning. Revert in
  `/etc/selinux/config` if you need enforcing.
- Boots UEFI (EDK2 RiscVVirt) on the QEMU `virt` machine (`acpi=off`). On
  x86 hosts it runs under **TCG** (no KVM), so the build is slow.
- To bump: take the riscv64 qcow2 URL and its `.qcow2.sha256` from the alt
  risc-v release dir and update `vmlab.wcl`.

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
