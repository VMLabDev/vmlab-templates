# debian-13 (riscv64)

Debian 13 (trixie) for **riscv64**, built from the official `generic` cloud
qcow2 with a NoCloud cloud-init seed. Store ref: `riscv64/debian-13`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- vmlab guest agent installed and enabled.
- Boots UEFI (EDK2 RiscVVirt) on the QEMU `virt` machine (`acpi=off`). On
  x86 hosts it runs under **TCG** (no KVM), so the build is slow.
- Host needs `qemu-system-riscv64` (QEMU ≥ 8.1) and the riscv64 UEFI
  firmware (`qemu-efi-riscv64`, or edk2's `RISCV_VIRT_*.fd`).
- **Versioning caveat:** riscv64 cloud images are currently published only
  under `trixie/latest` (no dated build carries them yet), so `url` tracks
  `latest`. The `sha256` is pinned to the file as of 2026-06-17 — when
  `latest` rolls forward the hash will stop matching; recompute it
  (`sha256sum` the downloaded qcow2) and bump `version`.

```sh
vmlab template build
```
