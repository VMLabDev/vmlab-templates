# fedora-44 (arm64)

Fedora 44 for **aarch64**, built from the official Cloud Base Generic qcow2
with a NoCloud cloud-init seed. Store ref: `aarch64/fedora-44`.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel), SSH
  password auth on.
- QEMU guest agent enabled with Fedora's RPC filter removed (a systemd
  override drops the blocklist, which otherwise blocks `vmlab exec`/`cp`).
- SELinux is set **permissive**: enforcing denies the guest agent
  exec'ing binaries, which breaks vmlab provisioning. Revert in
  `/etc/selinux/config` if you need enforcing.
- Boots UEFI (AAVMF) on the QEMU `virt` machine. On x86 hosts it runs under
  **TCG** (no KVM), so the build is slow.
- To bump: take the aarch64 qcow2 URL and sha256 from the `*-CHECKSUM` file
  under <https://download.fedoraproject.org/pub/fedora/linux/releases/> and
  update `vmlab.wcl`.

```sh
vmlab template build
```
