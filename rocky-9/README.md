# rocky-9

Rocky Linux 9 built from the official GenericCloud qcow2 with a NoCloud
cloud-init seed.

- Credentials: `vmlab` with a password per clone (see [Login password](#login-password)) (passwordless sudo via wheel), SSH
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

## Login password

Each clone gets its own password for `vmlab` at its first boot
(`scripts/firstboot.ws`), before the clone is reported ready, so no lab
starts with the published build password.

- To choose the password, declare a login for the account on the machine in
  the lab file: `login "vmlab" { user = "vmlab" password = "..." }`. The
  first boot sets it. A declared login also becomes the default
  identity of `vmlab exec` and `vmlab shell` on that machine.
- An account without a declared password gets a random 20-character
  password. Read it with
  `vmlab exec <vm> -- cat /root/vmlab-password` (the file is root only).
- To change it later: `vmlab exec <vm> -- sh -c 'echo vmlab:NEWPASS | chpasswd'`.

`vmlab exec`, `vmlab shell` and provisions go through the guest agent, which
runs as root and needs no password.
