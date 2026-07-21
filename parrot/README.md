# parrot

Parrot OS Security edition 7.2 from the official prebuilt QEMU qcow2.

- Credentials: `parrot` / `parrot` (image default) plus `vmlab` / `vmlab`
  (added by the provision, in sudo group). SSH enabled.
- The provision waits for the vmlab guest agent and falls back to a blind
  tty2 install if the image does not bundle it.
- Parrot distributes the image zipped — run `./fetch-deps.sh` once to
  download, sha256-verify and extract `disk/parrot.qcow2` (gitignored).
- To bump: update `VERSION` and `SHA256` in `fetch-deps.sh` (sums in
  `signed-hashes.txt` under <https://deb.parrot.sh/parrot/iso/>) and
  `version` in `vmlab.wcl`.

```sh
./fetch-deps.sh
vmlab template build
```
