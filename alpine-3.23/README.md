# alpine-3.23

Alpine Linux 3.23 built from the official NoCloud cloud image (UEFI +
cloud-init variant).

- Credentials: `vmlab` / `vmlab` (passwordless sudo via wheel, `sudo`
  installed by the seed), SSH password auth on.
- vmlab guest agent installed and added to the default runlevel.
- To bump: pick the `nocloud_alpine-*-x86_64-uefi-cloudinit-r*.qcow2`
  from <https://dl-cdn.alpinelinux.org/alpine/> under
  `releases/cloud/`, verify its `.sha512`, compute the sha256 and update
  `vmlab.wcl`.

```sh
vmlab template build
```
