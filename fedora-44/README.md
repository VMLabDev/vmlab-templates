# fedora-44

Fedora 44 built from the official Cloud Base Generic qcow2 with a NoCloud
cloud-init seed.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel), SSH
  password auth on.
- QEMU guest agent enabled with Fedora's RPC filter removed (a systemd
  override drops `--allow-rpcs`/blocklists, which otherwise block
  `vmlab exec`/`cp`).
- SELinux is set **permissive**: enforcing denies the guest agent
  exec'ing binaries, which breaks vmlab provisioning. Revert in
  `/etc/selinux/config` if you need enforcing.
- To bump: take the qcow2 URL and sha256 from the `*-CHECKSUM` file under
  <https://download.fedoraproject.org/pub/fedora/linux/releases/> and
  update `vmlab.wcl`.

```sh
vmlab template build
```
