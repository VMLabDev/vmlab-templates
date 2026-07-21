# ubuntu-24.04 (riscv64)

Ubuntu Server 24.04 LTS (noble) for **riscv64**, built from the official
cloud image qcow2 with a NoCloud cloud-init seed. Store ref:
`riscv64/ubuntu-24.04`.

Uses the cloud image + cloud-init (like the arm64 templates) — far faster
under TCG than an installer ISO.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- vmlab guest agent installed and enabled.
- Boots UEFI (EDK2 RiscVVirt) on the QEMU `virt` machine (`acpi=off`). On
  x86 hosts it runs under **TCG** (no KVM), so the build is slow.
- Host needs `qemu-system-riscv64` (QEMU ≥ 8.1) and the riscv64 UEFI
  firmware (`qemu-efi-riscv64`, or edk2's `RISCV_VIRT_*.fd`).
- Image pinned to cloud build serial `20260518`. To bump: pick a serial from
  <https://cloud-images.ubuntu.com/noble/>, take the riscv64 `.img` sha256
  from its `SHA256SUMS` and update `vmlab.wcl`.

```sh
vmlab template build
```
