# ubuntu-24.04 (arm64)

Ubuntu Server 24.04 LTS (noble) for **aarch64**, built from the official
cloud image qcow2 with a NoCloud cloud-init seed. Store ref:
`aarch64/ubuntu-24.04`.

Unlike the x86 `ubuntu-24.04` template (installer ISO + subiquity
autoinstall), this arm64 build uses the cloud image + cloud-init — far
faster under TCG and consistent with the other arm64 cloud-image templates.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- vmlab guest agent installed and enabled.
- Boots UEFI (AAVMF) on the QEMU `virt` machine. On x86 hosts it runs under
  **TCG** (no KVM), so the build is slow.
- Image pinned to cloud build serial `20260518`. To bump: pick a serial from
  <https://cloud-images.ubuntu.com/noble/>, take the arm64 `.img` sha256
  from its `SHA256SUMS` and update `vmlab.wcl`.

```sh
vmlab template build
```
