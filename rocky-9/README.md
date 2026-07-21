# rocky-9

Rocky Linux 9 built from the official GenericCloud qcow2 with a NoCloud
cloud-init seed.

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel), SSH
  password auth on.
- vmlab guest agent enabled with EL's RPC allow-list removed (a systemd
  override drops `--allow-rpcs`, which otherwise blocks `vmlab exec`/`cp`).
- SELinux is set **permissive**: enforcing denies the guest agent
  exec'ing binaries, which breaks vmlab provisioning. Revert in
  `/etc/selinux/config` if you need enforcing.
- To bump: take the qcow2 URL and sha256 from the `CHECKSUM` file under
  <https://download.rockylinux.org/pub/rocky/9/images/x86_64/> and update
  `vmlab.wcl`.

```sh
vmlab template build
```
