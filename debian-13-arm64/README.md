# debian-13 (arm64)

Debian 13 (trixie) for **aarch64**, built from the official `genericcloud`
qcow2 with a NoCloud cloud-init seed. Store ref: `aarch64/debian-13`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- QEMU guest agent installed and enabled.
- Boots UEFI (AAVMF) on the QEMU `virt` machine. On x86 hosts it runs under
  **TCG** (no KVM), so the build is slow.
- Image pinned to cloud build `20260601-2496`. To bump: pick a build from
  <https://cloud.debian.org/images/cloud/trixie/>, verify the arm64 qcow2
  against its `SHA512SUMS`, compute the sha256 and update `vmlab.wcl`.

```sh
vmlab template build
```
