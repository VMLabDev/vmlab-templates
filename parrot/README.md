# parrot

Parrot OS Security edition 7.2 from the official prebuilt QEMU qcow2.

- Credentials: `parrot` / `parrot` (image default) plus `vmlab` / `vmlab`
  (added by the provision, in sudo group). SSH enabled.
- vmlab-agent: Parrot's QEMU image has no cloud-init or unattended-install
  hook, so `fetch-deps.sh` offline-injects a `virt-customize` firstboot
  command that mounts the VMLAB bootstrap ISO (attached during the build)
  and runs its `install.sh`. The agent is up and verified before the
  provision runs, and the install is baked into the sealed image so clones
  come up "ready". **Requires `virt-customize` (libguestfs) on the build
  host.**
- Parrot distributes the image zipped — run `./fetch-deps.sh` once to
  download, sha256-verify, extract `disk/parrot.qcow2` and inject the agent
  bootstrap (all gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `signed-hashes.txt` under <https://deb.parrot.sh/parrot/iso/>) and
  `version` in `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```
