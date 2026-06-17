# alpine-3.23 (arm64)

Alpine Linux 3.23 for **aarch64**, built from the official NoCloud cloud
image (UEFI + cloud-init variant). Store ref: `aarch64/alpine-3.23`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel, `sudo`
  installed by the seed), SSH password auth on.
- QEMU guest agent installed and added to the default runlevel.
- Boots UEFI (AAVMF) on the QEMU `virt` machine. On x86 hosts it runs under
  **TCG** (no KVM); being the smallest image, it is the fastest arm64
  template to build.
- To bump: pick the `nocloud_alpine-*-aarch64-uefi-cloudinit-r*.qcow2` from
  <https://dl-cdn.alpinelinux.org/alpine/> under `releases/cloud/`, verify
  its `.sha512`, compute the sha256 and update `vmlab.wcl`.

```sh
vmlab template build
```
