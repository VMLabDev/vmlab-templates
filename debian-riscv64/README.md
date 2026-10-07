# debian-13 (riscv64)

Debian 13 (trixie) for **riscv64**, built from the official `generic` cloud
qcow2 with a NoCloud cloud-init seed. Store ref: `riscv64/debian-13`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- vmlab guest agent installed and enabled.
- Boots UEFI (EDK2 RiscVVirt) on the QEMU `virt` machine (`acpi=off`). On
  x86 hosts it runs under **TCG** (no KVM), so the build is slow.
- Host needs `qemu-system-riscv64` (QEMU ≥ 8.1) and the riscv64 UEFI
  firmware (`qemu-efi-riscv64`, or edk2's `RISCV_VIRT_*.fd`).
- Image pinned to cloud build `20261001-2618`. To bump: pick a build from
  <https://cloud.debian.org/images/cloud/trixie/>, verify the file against
  its `SHA512SUMS`, compute the sha256 and update `vmlab.wcl`.

```sh
vmlab template build
```
