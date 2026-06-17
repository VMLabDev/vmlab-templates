# fedora-42 (riscv64)

Fedora 42 for **riscv64**, built from the official Cloud Base Generic qcow2
with a NoCloud cloud-init seed. Store ref: `riscv64/fedora-42`.

RISC-V is a Fedora **alternative-architecture** port (not officially
supported), currently at release **42** — behind the primary aarch64/x86_64
templates here, which track 44. Images live under
<https://dl.fedoraproject.org/pub/alt/risc-v/release/>.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel), SSH
  password auth on.
- QEMU guest agent enabled with Fedora's RPC filter removed (a systemd
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
