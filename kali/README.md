# kali

Kali Linux (rolling, 2026.1) from the official prebuilt QEMU image.

- Credentials: `kali` / `kali` (image default) plus `vmlab` / `vmlab`
  (added by the provision, in sudo group). SSH enabled.
- vmlab guest agent ships preinstalled in Kali's QEMU image; the provision
  falls back to a blind tty2 install if it ever stops being bundled.
- Kali distributes the image as a `.7z`, which vmlab's URL sources cannot
  unpack — run `./fetch-deps.sh` once to download, sha256-verify and
  extract `disk/kali.qcow2` (gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `SHA256SUMS` at <https://cdimage.kali.org/>) and `version` in
  `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```
