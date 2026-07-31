# vmlab-templates

A collection of [vmlab](https://github.com/wiltaylor/vmlab) template
definitions for common operating systems. Each directory is a standalone
template: `cd` into it and run `vmlab template build`.

The root [`vmlab.wcl`](vmlab.wcl) is a unified catalog of every definition in
this repository. It is generated from the standalone files with
`scripts/generate-unified-wcl.sh`; edit the per-template definitions and
regenerate rather than editing the root file directly.

## Build from the Web UI

The included Compose stack runs the unified catalog with the vmlab
`0.6.0-alpha` prerelease, which supports same-name templates on multiple
architectures:

```sh
docker compose pull
docker compose up -d
```

Open <http://localhost:7879>, select the `templates` lab, then use the
**Templates** tab to build or publish an exact architecture/template pair.
The template store, build working data, and downloaded artefacts live in named
Docker volumes, so they survive container replacement. Override the image when
testing another build:

```sh
VMLAB_IMAGE=ghcr.io/vmlabdev/vmlab:latest docker compose up -d
```

The repository is bind-mounted at `/lab`, so prerequisites generated on the
host are immediately visible in the container. Compose deliberately does not
run `fetch-deps.sh` automatically: prepare the templates that need staged
drivers, extracted images, or answer files with their existing `just` recipe
or script before clicking Build. Templates backed by proprietary media also
need the documented ISO in `iso/`; `windows-2000` additionally needs the
product key in `.env`. The Windows 11 ARM64 definition remains experimental
and retains its deliberate placeholder URL/hash tripwire.

Linux/KVM is required by the Compose stack (`/dev/kvm`). Non-native ARM64 and
RISC-V builds still use TCG inside vmlab and can take substantially longer.

## Templates

| Directory | OS | Source strategy |
|---|---|---|
| `ubuntu-24.04/` | Ubuntu Server 24.04 LTS | Installer ISO + subiquity autoinstall |
| `ubuntu-26.04/` | Ubuntu Server 26.04 LTS | Cloud qcow2 + cloud-init |
| `debian-13/` | Debian 13 (trixie) | Cloud qcow2 + cloud-init |
| `arch/` | Arch Linux (rolling) | Cloud qcow2 + cloud-init |
| `almalinux-10/` | AlmaLinux 10 | GenericCloud qcow2 + cloud-init |
| `fedora-44/` | Fedora 44 | Cloud Base qcow2 + cloud-init |
| `rocky-9/` | Rocky Linux 9 | GenericCloud qcow2 + cloud-init |
| `alpine-3.23/` | Alpine Linux 3.23 | NoCloud qcow2 + cloud-init |
| `nixos-25.11/` | NixOS 25.11 | Minimal ISO + scripted nixos-install |
| `kali/` | Kali Linux 2026.1 | Official QEMU qcow2 (run `fetch-deps.sh` first) |
| `parrot/` | Parrot OS Security 7.2 | Official QEMU qcow2 (run `fetch-deps.sh` first) |
| `windows-server-2025/` | Windows Server 2025 Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |
| `windows-server-2022/` | Windows Server 2022 Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |
| `windows-server-2019/` | Windows Server 2019 Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |
| `windows-11/` | Windows 11 Enterprise Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |
| `windows-10/` | Windows 10 Enterprise Eval | Installer ISO + autounattend, sysprep-generalized (run `fetch-deps.sh` first) |

All Windows eval ISOs are downloaded and sha256-verified by vmlab just like the
Linux ones; `fetch-deps.sh` only fetches the virtio guest drivers that get baked
into the answer-file media (and `just` runs it for you).

### Vintage x86 (DOS / Windows 3.x–2000)

These predate answer files and have no guest agent, so they install from local
or downloaded media driven over the live screen (VNC + OCR). They run on the
x86_64 emulator but show as arch `x86`. Built via `just build-vintage` (the
proprietary entries need their ISOs placed in `iso/` first — see `iso/README.md`).

| Directory | OS | Source strategy |
|---|---|---|
| `freedos-1.3/` | FreeDOS 1.3 (Full set) | LiveCD download + sha256 (run `fetch-deps.sh` first); **publishable** |
| `dos-6.22/` | MS-DOS 6.22 | Local bootable ISO, screen-driven install |
| `windows-3.11/` | Windows for Workgroups 3.11 | Pre-installed tree layered on `dos-6.22` |
| `windows-2000/` | Windows 2000 Professional SP4 | Local ISO + `winnt.sif` unattend (needs `.env` key) |

FreeDOS is the one vintage template that is FOSS / freely redistributable, so it
is download-backed and can be pushed to the registry (`just freedos-push`); the
proprietary entries are local-only.

### arm64 (aarch64)

These build the same distros for `aarch64`, all from cloud images +
cloud-init. They boot UEFI (AAVMF) on the QEMU `virt` machine; on x86 hosts
they run under **TCG** (no KVM), so builds are slow.

| Directory | OS | Store ref |
|---|---|---|
| `alpine-3.23-arm64/` | Alpine Linux 3.23 | `aarch64/alpine-3.23` |
| `debian-13-arm64/` | Debian 13 (trixie) | `aarch64/debian-13` |
| `fedora-44-arm64/` | Fedora 44 | `aarch64/fedora-44` |
| `ubuntu-arm64/` | Ubuntu Server 24.04 LTS | `aarch64/ubuntu-24.04` |

`windows-11-arm64/` also exists but is **experimental and not part of
`just build-arm64`**: Microsoft publishes no stable ARM64 eval ISO link/hash, so
you must fill in `url`/`sha256`/`version` in its `vmlab.wcl` first, then build it
on its own with `just windows-11-arm64-build`. See its README.

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
just build              # build all x86_64 templates
just debian-arm64-build # build one arm64 template
just build-arm64        # build all arm64 templates (slow under TCG)
```

Or by hand:

```sh
cd debian-13
vmlab template build    # download, install, seal into the local store
vmlab template list     # confirm it landed
```

Builds are idempotent: a template already in the store is skipped (per
`vmlab template exists`; run `vmlab template rm <ref>` to force a
rebuild), and templates with a `fetch-deps.sh` get their payloads staged
automatically. Requires vmlab with the `template exists` verb.

Reference a built template from a lab:

```wcl
vm "box" { template = "x86_64/debian-13" }
```

## Verification

`just ci::check` is the merge bar — everything a change must pass before it
lands. It runs in under a second from a clean checkout, needs no network, and
needs only `vmlab`, `wcl`, `git` and `uv`:

```sh
just ci                 # list the parts
just ci::check          # the whole gate
just ci::wcl-sync-check # vmlab.wcl matches a regen from the per-template files
just ci::wcl-check      # parse + schema-check every template definition
just ci::examples-check # parse + schema-check every examples/<name>/ lab
just ci::docs-build     # build the docs site (what deploy-site.yml deploys)
```

A single template definition cannot be checked on its own: each one begins
`import <vmlab.wcl>`, a system import that only the `vmlab` binary registers (so
plain `wcl check` fails on all of them), and `vmlab validate` wants a `lab`
block. `ci::wcl-check` therefore validates them through the generated unified
`vmlab.wcl`, which is why `ci::wcl-sync-check` runs first — a per-template edit
that was never regenerated would otherwise go unchecked.

Because the gate builds and downloads nothing, two classes of `vmlab validate`
error are tolerated, and only these: a reference to a **gitignored** local
artefact (the `iso/` media, the `fetch-deps.sh` payloads) and a lab whose
template is **not in this machine's store**. Anything else fails — including a
diagnostic the checker cannot parse.

Building templates is **not** in the gate: hours of runtime, KVM, and
hand-supplied ISOs. Neither is `just docs-data`, which needs GHCR auth and a
network. The `autounattend.xml`, `.ps1` and `.sh` files are not verified by
anything yet.
