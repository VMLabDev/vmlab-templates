# vmlab-templates

A collection of [vmlab](https://github.com/wiltaylor/vmlab) template
definitions for common operating systems. Each directory is a standalone
template: `cd` into it and run `vmlab template build`.

## Templates

| Directory | OS | Source strategy |
|---|---|---|
| `ubuntu-24.04/` | Ubuntu Server 24.04 LTS | Installer ISO + subiquity autoinstall |
| `debian-13/` | Debian 13 (trixie) | Cloud qcow2 + cloud-init |
| `fedora-44/` | Fedora 44 | Cloud Base qcow2 + cloud-init |
| `rocky-9/` | Rocky Linux 9 | GenericCloud qcow2 + cloud-init |
| `alpine-3.23/` | Alpine Linux 3.23 | NoCloud qcow2 + cloud-init |
| `nixos-25.11/` | NixOS 25.11 | Minimal ISO + scripted nixos-install |
| `kali/` | Kali Linux 2026.1 | Official QEMU qcow2 (run `fetch-deps.sh` first) |
| `parrot/` | Parrot OS Security 7.2 | Official QEMU qcow2 (run `fetch-deps.sh` first) |
| `windows-server-2025/` | Windows Server 2025 Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |

## Conventions

- Credentials baked into every template: user `vmlab`, password `vmlab`
  (Windows: `Administrator` / `vmlab123!` — see its README).
- The QEMU guest agent is installed and enabled, so lab clones come up
  with the "ready" flag and support `vmlab exec` / `vmlab cp`.
- Versions are pinned; ISO/qcow2 sources carry sha256 sums from the
  vendor's official checksum files. Downloads are cached and verified by
  vmlab under `~/.cache/vmlab/artefacts/`.
- Build VMs get NAT (`nic { nat = true }`) for package installs during
  provisioning.

## Usage

With [just](https://github.com/casey/just):

```sh
just                    # list recipes
just debian-build       # build one template (skips if already in the store)
just build              # build them all
```

Or by hand:

```sh
cd debian-13
vmlab validate          # sanity-check the definition
vmlab template build    # download, install, seal into the local store
vmlab template list     # confirm it landed
```

Builds are idempotent via `scripts/template-build.py`: a template already
in the store is skipped (`vmlab template rm <ref>` to force a rebuild),
and templates with a `fetch-deps.sh` get their payloads staged
automatically.

Reference a built template from a lab:

```wcl
vm "box" { template = "x86_64/debian-13" }
```
