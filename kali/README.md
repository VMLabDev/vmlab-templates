# kali

Kali Linux (rolling, 2026.1) from the official prebuilt QEMU image.

- Credentials: `kali` / `kali` (image default) plus `vmlab` / `vmlab`
  (added by the provision, in sudo group). SSH enabled.
- vmlab-agent: Kali's QEMU image has no cloud-init or unattended-install
  hook, so `fetch-deps.sh` offline-injects a `virt-customize` firstboot
  command that mounts the VMLAB bootstrap ISO (attached during the build)
  and runs its `install.sh`. The agent is up and verified before the
  provision runs, and the install is baked into the sealed image so clones
  come up "ready". **Requires `virt-customize` (libguestfs) on the build
  host.**
- Kali distributes the image as a `.7z`, which vmlab's URL sources cannot
  unpack — run `./fetch-deps.sh` once to download, sha256-verify, extract
  `disk/kali.qcow2` and inject the agent bootstrap (all gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `SHA256SUMS` at <https://cdimage.kali.org/>) and `version` in
  `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```
