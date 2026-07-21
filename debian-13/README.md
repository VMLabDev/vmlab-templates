# debian-13

Debian 13 (trixie) built from the official `genericcloud` qcow2 with a
NoCloud cloud-init seed.

- Credentials: `vmlab` / `vmlab` (passwordless sudo), SSH password auth on.
- vmlab guest agent installed and enabled.
- Image pinned to cloud build `20260601-2496`. To bump: pick a build from
  <https://cloud.debian.org/images/cloud/trixie/>, verify the file against
  its `SHA512SUMS`, compute the sha256 and update `vmlab.wcl`.

```sh
vmlab template build
```
