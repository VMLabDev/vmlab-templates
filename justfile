# Each template declares its own publish repo via the `registry` field in its
# vmlab.wcl (e.g. ghcr.io/vmlabdev/vmlab-templates/<name>), so `push` needs no
# namespace here. The GHCR namespace must be lowercase (org VMLabDev -> vmlabdev).

[default, private]
main:
	@just --list

# Build one template dir (skips refs already in the store; stages fetch-deps.sh payloads)
[group('build')]
template-build dir ref:
	#!/usr/bin/env bash
	set -euo pipefail
	if found=$(vmlab template exists '{{ ref }}' 2>/dev/null); then
		echo "$found already in the store; skipping (vmlab template rm to rebuild)"
		exit 0
	fi
	cd '{{ dir }}'
	if [ -x fetch-deps.sh ]; then ./fetch-deps.sh; fi
	vmlab template build

# Build the Alpine Linux 3.23 template
[group('build')]
alpine-build: (template-build 'alpine-3.23' 'x86_64/alpine-3.23')

# Build the Debian 13 template
[group('build')]
debian-build: (template-build 'debian-13' 'x86_64/debian-13')

# Build the Fedora 44 template
[group('build')]
fedora-build: (template-build 'fedora-44' 'x86_64/fedora-44')

# Build the Kali Linux template
[group('build')]
kali-build: (template-build 'kali' 'x86_64/kali')

# Build the NixOS 25.11 template
[group('build')]
nixos-build: (template-build 'nixos-25.11' 'x86_64/nixos-25.11')

# Build the Parrot OS Security template
[group('build')]
parrot-build: (template-build 'parrot' 'x86_64/parrot')

# Build the Rocky Linux 9 template
[group('build')]
rocky-build: (template-build 'rocky-9' 'x86_64/rocky-9')

# Build the Ubuntu Server 24.04 template
[group('build')]
ubuntu-build: (template-build 'ubuntu-24.04' 'x86_64/ubuntu-24.04')

# Build the Windows Server 2025 template (sysprep-generalized)
[group('build')]
windows-build: (template-build 'windows-server-2025' 'x86_64/windows-server-2025')

# Build the Windows Server 2022 template (sysprep-generalized)
[group('build')]
windows-server-2022-build: (template-build 'windows-server-2022' 'x86_64/windows-server-2022')

# Build the Windows Server 2019 template (sysprep-generalized)
[group('build')]
windows-server-2019-build: (template-build 'windows-server-2019' 'x86_64/windows-server-2019')

# Build the Windows 11 Enterprise template (sysprep-generalized)
[group('build')]
windows-11-build: (template-build 'windows-11' 'x86_64/windows-11')

# Build the Windows 10 Enterprise template (sysprep-generalized)
[group('build')]
windows-10-build: (template-build 'windows-10' 'x86_64/windows-10')

# Build every download-backed template on a clean machine: x86_64 natively,
# then the slower TCG arm64 + riscv64 groups. Everything here fetches its own
# media (URL sources / fetch-deps.sh), so no files need to be placed by hand.
# The local-media Windows (`build-windows-local`) and vintage (`build-vintage`)
# groups are NOT included — those need their ISOs copied into iso/ first.
[group('build')]
build: alpine-build debian-build fedora-build kali-build nixos-build parrot-build rocky-build ubuntu-build windows-build windows-server-2022-build windows-server-2019-build windows-11-build windows-10-build build-arm64 build-riscv64

# --- Local-media Windows (Vista–2016, keyless, sysprep-generalized) ---
# These install from the MSDN/VL ISOs you place in iso/ (gitignored, see
# iso/README.md), not from a download — a fresh clone needs those files. They
# show as arch `x86` (32-bit) or `x86_64` in the store. Kept out of `build`
# above because that one is for download-backed templates.

# Build Windows Vista Enterprise (x64 + x86)
[group('build-windows-local')]
windows-vista-build: (template-build 'windows-vista' 'x86_64/windows-vista')
[group('build-windows-local')]
windows-vista-x86-build: (template-build 'windows-vista-x86' 'x86/windows-vista')

# Build Windows 7 Enterprise (x64 + x86)
[group('build-windows-local')]
windows-7-build: (template-build 'windows-7' 'x86_64/windows-7')
[group('build-windows-local')]
windows-7-x86-build: (template-build 'windows-7-x86' 'x86/windows-7')

# Build Windows 8 Enterprise (x64 + x86)
[group('build-windows-local')]
windows-8-build: (template-build 'windows-8' 'x86_64/windows-8')
[group('build-windows-local')]
windows-8-x86-build: (template-build 'windows-8-x86' 'x86/windows-8')

# Build Windows 8.1 Enterprise (x64 + x86)
[group('build-windows-local')]
windows-8-1-build: (template-build 'windows-8.1' 'x86_64/windows-8.1')
[group('build-windows-local')]
windows-8-1-x86-build: (template-build 'windows-8.1-x86' 'x86/windows-8.1')

# Build Windows Server 2008 (x64 + x86)
[group('build-windows-local')]
windows-server-2008-build: (template-build 'windows-server-2008' 'x86_64/windows-server-2008')
[group('build-windows-local')]
windows-server-2008-x86-build: (template-build 'windows-server-2008-x86' 'x86/windows-server-2008')

# Build Windows Server 2008 R2 / 2012 / 2012 R2 / 2016 (x64)
[group('build-windows-local')]
windows-server-2008-r2-build: (template-build 'windows-server-2008-r2' 'x86_64/windows-server-2008-r2')
[group('build-windows-local')]
windows-server-2012-build: (template-build 'windows-server-2012' 'x86_64/windows-server-2012')
[group('build-windows-local')]
windows-server-2012-r2-build: (template-build 'windows-server-2012-r2' 'x86_64/windows-server-2012-r2')
[group('build-windows-local')]
windows-server-2016-build: (template-build 'windows-server-2016' 'x86_64/windows-server-2016')

# Build every local-media Windows template (needs the iso/ files)
[group('build-windows-local')]
build-windows-local: windows-vista-build windows-vista-x86-build windows-7-build windows-7-x86-build windows-8-build windows-8-x86-build windows-8-1-build windows-8-1-x86-build windows-server-2008-build windows-server-2008-x86-build windows-server-2008-r2-build windows-server-2012-build windows-server-2012-r2-build windows-server-2016-build

# --- Vintage x86 (DOS / Windows 3.x–ME / 2000), driven by wisp UI automation ---
# These layer or install from local media in iso/ (gitignored) and are driven
# over the live screen (VNC + OCR), since they predate answer files and have no
# guest agent. They run on the x86_64 emulator but show as arch `x86`.

# Build the FreeDOS 1.3 template (Full package set, FDI-driven install)
[group('build-vintage')]
freedos-build:
	#!/usr/bin/env bash
	set -euo pipefail
	# --version pins 1.3 (the upstream release) instead of auto-incrementing, so
	# rebuilds stay 1.3 — the FreeDOS version, not a vmlab build counter.
	if found=$(vmlab template exists 'x86/freedos-1.3' 2>/dev/null); then
		echo "$found already in the store; skipping (vmlab template rm to rebuild)"
		exit 0
	fi
	cd freedos-1.3
	./fetch-deps.sh
	vmlab template build --version 1.3

# Build the MS-DOS 6.22 template (bootable C:, driven install)
[group('build-vintage')]
dos-6-22-build: (template-build 'dos-6.22' 'x86/dos-6.22')

# Build Windows for Workgroups 3.11 (layers on dos-6.22; auto-launches Windows)
[group('build-vintage')]
windows-3-11-build: dos-6-22-build (template-build 'windows-3.11' 'x86/windows-3.11')

# Build Windows 2000 Professional SP4 (unattended via winnt.sif; needs .env key)
[group('build-vintage')]
windows-2000-build: (template-build 'windows-2000' 'x86/windows-2000')

# Build every vintage x86 template into the local store
[group('build-vintage')]
build-vintage: freedos-build dos-6-22-build windows-3-11-build windows-2000-build

# Build the Alpine Linux 3.23 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
alpine-arm64-build: (template-build 'alpine-3.23-arm64' 'aarch64/alpine-3.23')

# Build the Debian 13 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
debian-arm64-build: (template-build 'debian-13-arm64' 'aarch64/debian-13')

# Build the Fedora 44 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
fedora-arm64-build: (template-build 'fedora-44-arm64' 'aarch64/fedora-44')

# Build the Home Assistant OS aarch64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
home-assistant-arm64-build: (template-build 'home-assistant-aarch64' 'aarch64/home-assistant')

# Build the Ubuntu Server 24.04 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
ubuntu-arm64-build: (template-build 'ubuntu-arm64' 'aarch64/ubuntu-24.04')

# EXPERIMENTAL Windows 11 arm64 — excluded from `build-arm64`: needs a
# hand-supplied ARM64 eval ISO in its vmlab.wcl, very slow under TCG (README)
[group('build-arm64')]
windows-11-arm64-build: (template-build 'windows-11-arm64' 'aarch64/windows-11-arm64')

# Build every arm64 template into the local store (slow under TCG)
[group('build-arm64')]
build-arm64: alpine-arm64-build debian-arm64-build fedora-arm64-build home-assistant-arm64-build ubuntu-arm64-build

# Build the Debian 13 riscv64 template (runs under TCG on x86 hosts)
[group('build-riscv64')]
debian-riscv64-build: (template-build 'debian-riscv64' 'riscv64/debian-13')

# Build the Fedora 42 riscv64 template (runs under TCG on x86 hosts)
[group('build-riscv64')]
fedora-riscv64-build: (template-build 'fedora-riscv64' 'riscv64/fedora-42')

# Build the Ubuntu Server 24.04 riscv64 template (runs under TCG on x86 hosts)
[group('build-riscv64')]
ubuntu-riscv64-build: (template-build 'ubuntu-riscv64' 'riscv64/ubuntu-24.04')

# Build every riscv64 template into the local store (slow under TCG)
[group('build-riscv64')]
build-riscv64: debian-riscv64-build fedora-riscv64-build ubuntu-riscv64-build

# --- Push built templates to an OCI registry (PRD §6.4) ---
# Upload a template already in the local store. The target repo + version come
# from the template itself (its `registry` field and the store version), so each
# `arch/name` pushes to `<registry>/<name>:<version>` and also moves the moving
# `:latest` tag; pushing several arches of the same name+version merges them into
# one multi-arch index. Run a build (or `just build`) first — push uploads what
# is in the store, it does not build. Only the download-backed Linux templates
# are wired up here; the Windows templates are deliberately omitted (their
# eval/VL media is not ours to redistribute). Authenticate once with
# `vmlab template login` beforehand.

# Push one store ref to its template's registry, moving `:latest`
[group('push')]
template-push ref:
	vmlab template push '{{ ref }}'

# Publish any store ref as a pre-release (moves `:latest-prerelease`, not `:latest`)
[group('push')]
prerelease ref:
	vmlab template push --prerelease '{{ ref }}'

[group('push')]
alpine-push: (template-push 'x86_64/alpine-3.23')
[group('push')]
debian-push: (template-push 'x86_64/debian-13')
[group('push')]
fedora-push: (template-push 'x86_64/fedora-44')
[group('push')]
kali-push: (template-push 'x86_64/kali')
[group('push')]
nixos-push: (template-push 'x86_64/nixos-25.11')
[group('push')]
parrot-push: (template-push 'x86_64/parrot')
[group('push')]
rocky-push: (template-push 'x86_64/rocky-9')
[group('push')]
ubuntu-push: (template-push 'x86_64/ubuntu-24.04')

# FreeDOS 1.3 is FOSS/redistributable (unlike the other vintage + Windows media),
# so it is safe to publish; kept standalone, not in the `push` aggregate.

# Push the FreeDOS 1.3 template to its registry
[group('push')]
freedos-push: (template-push 'x86/freedos-1.3')

[group('push')]
alpine-arm64-push: (template-push 'aarch64/alpine-3.23')
[group('push')]
debian-arm64-push: (template-push 'aarch64/debian-13')
[group('push')]
fedora-arm64-push: (template-push 'aarch64/fedora-44')
[group('push')]
home-assistant-arm64-push: (template-push 'aarch64/home-assistant')
[group('push')]
ubuntu-arm64-push: (template-push 'aarch64/ubuntu-24.04')

[group('push')]
debian-riscv64-push: (template-push 'riscv64/debian-13')
[group('push')]
fedora-riscv64-push: (template-push 'riscv64/fedora-42')
[group('push')]
ubuntu-riscv64-push: (template-push 'riscv64/ubuntu-24.04')

# Push every arm64 template (merges into the shared multi-arch indexes)
[group('push')]
push-arm64: alpine-arm64-push debian-arm64-push fedora-arm64-push home-assistant-arm64-push ubuntu-arm64-push

# Push every riscv64 template (merges into the shared multi-arch indexes)
[group('push')]
push-riscv64: debian-riscv64-push fedora-riscv64-push ubuntu-riscv64-push

# Push every download-backed Linux template (x86_64 + arm64 + riscv64) to the registry
[group('push')]
push: alpine-push debian-push fedora-push kali-push nixos-push parrot-push rocky-push ubuntu-push push-arm64 push-riscv64

# Build everything `just build` covers, then push the Linux templates upstream
[group('push')]
release: build push

# --- Examples: smoke-test a single template ---
# Each template has a ready-to-run one-VM lab under examples/<name>/ (<name>
# matches the template directory). The template must be in the store (built
# locally or pulled). The per-template recipes delegate to these shared workers;
# recipe names sanitise dots to hyphens, like the build recipes.

[private]
example-up name:
	cd examples/{{ name }} && vmlab up && vmlab console guest

[private]
example-down name:
	cd examples/{{ name }} && vmlab destroy

# Boot the alpine-3.23 example (up + console)
[group('example')]
alpine-3-23-example-up: (example-up 'alpine-3.23')
# Destroy the alpine-3.23 example
[group('example')]
alpine-3-23-example-down: (example-down 'alpine-3.23')

# Boot the alpine-3.23-arm64 example (up + console)
[group('example')]
alpine-3-23-arm64-example-up: (example-up 'alpine-3.23-arm64')
# Destroy the alpine-3.23-arm64 example
[group('example')]
alpine-3-23-arm64-example-down: (example-down 'alpine-3.23-arm64')

# Boot the debian-13 example (up + console)
[group('example')]
debian-13-example-up: (example-up 'debian-13')
# Destroy the debian-13 example
[group('example')]
debian-13-example-down: (example-down 'debian-13')

# Boot the debian-13-arm64 example (up + console)
[group('example')]
debian-13-arm64-example-up: (example-up 'debian-13-arm64')
# Destroy the debian-13-arm64 example
[group('example')]
debian-13-arm64-example-down: (example-down 'debian-13-arm64')

# Boot the debian-riscv64 example (up + console)
[group('example')]
debian-riscv64-example-up: (example-up 'debian-riscv64')
# Destroy the debian-riscv64 example
[group('example')]
debian-riscv64-example-down: (example-down 'debian-riscv64')

# Boot the dos-6.22 example (up + console)
[group('example')]
dos-6-22-example-up: (example-up 'dos-6.22')
# Destroy the dos-6.22 example
[group('example')]
dos-6-22-example-down: (example-down 'dos-6.22')

# Boot the fedora-44 example (up + console)
[group('example')]
fedora-44-example-up: (example-up 'fedora-44')
# Destroy the fedora-44 example
[group('example')]
fedora-44-example-down: (example-down 'fedora-44')

# Boot the fedora-44-arm64 example (up + console)
[group('example')]
fedora-44-arm64-example-up: (example-up 'fedora-44-arm64')
# Destroy the fedora-44-arm64 example
[group('example')]
fedora-44-arm64-example-down: (example-down 'fedora-44-arm64')

# Boot the fedora-riscv64 example (up + console)
[group('example')]
fedora-riscv64-example-up: (example-up 'fedora-riscv64')
# Destroy the fedora-riscv64 example
[group('example')]
fedora-riscv64-example-down: (example-down 'fedora-riscv64')

# Boot the freedos-1.3 example (up + console)
[group('example')]
freedos-1-3-example-up: (example-up 'freedos-1.3')
# Destroy the freedos-1.3 example
[group('example')]
freedos-1-3-example-down: (example-down 'freedos-1.3')

# Boot the home-assistant-aarch64 example (up + console)
[group('example')]
home-assistant-aarch64-example-up: (example-up 'home-assistant-aarch64')
# Destroy the home-assistant-aarch64 example
[group('example')]
home-assistant-aarch64-example-down: (example-down 'home-assistant-aarch64')

# Boot the kali example (up + console)
[group('example')]
kali-example-up: (example-up 'kali')
# Destroy the kali example
[group('example')]
kali-example-down: (example-down 'kali')

# Boot the nixos-25.11 example (up + console)
[group('example')]
nixos-25-11-example-up: (example-up 'nixos-25.11')
# Destroy the nixos-25.11 example
[group('example')]
nixos-25-11-example-down: (example-down 'nixos-25.11')

# Boot the parrot example (up + console)
[group('example')]
parrot-example-up: (example-up 'parrot')
# Destroy the parrot example
[group('example')]
parrot-example-down: (example-down 'parrot')

# Boot the rocky-9 example (up + console)
[group('example')]
rocky-9-example-up: (example-up 'rocky-9')
# Destroy the rocky-9 example
[group('example')]
rocky-9-example-down: (example-down 'rocky-9')

# Boot the ubuntu-24.04 example (up + console)
[group('example')]
ubuntu-24-04-example-up: (example-up 'ubuntu-24.04')
# Destroy the ubuntu-24.04 example
[group('example')]
ubuntu-24-04-example-down: (example-down 'ubuntu-24.04')

# Boot the ubuntu-arm64 example (up + console)
[group('example')]
ubuntu-arm64-example-up: (example-up 'ubuntu-arm64')
# Destroy the ubuntu-arm64 example
[group('example')]
ubuntu-arm64-example-down: (example-down 'ubuntu-arm64')

# Boot the ubuntu-riscv64 example (up + console)
[group('example')]
ubuntu-riscv64-example-up: (example-up 'ubuntu-riscv64')
# Destroy the ubuntu-riscv64 example
[group('example')]
ubuntu-riscv64-example-down: (example-down 'ubuntu-riscv64')

# Boot the windows-10 example (up + console)
[group('example')]
windows-10-example-up: (example-up 'windows-10')
# Destroy the windows-10 example
[group('example')]
windows-10-example-down: (example-down 'windows-10')

# Boot the windows-11 example (up + console)
[group('example')]
windows-11-example-up: (example-up 'windows-11')
# Destroy the windows-11 example
[group('example')]
windows-11-example-down: (example-down 'windows-11')

# Boot the windows-11-arm64 example (up + console)
[group('example')]
windows-11-arm64-example-up: (example-up 'windows-11-arm64')
# Destroy the windows-11-arm64 example
[group('example')]
windows-11-arm64-example-down: (example-down 'windows-11-arm64')

# Boot the windows-2000 example (up + console)
[group('example')]
windows-2000-example-up: (example-up 'windows-2000')
# Destroy the windows-2000 example
[group('example')]
windows-2000-example-down: (example-down 'windows-2000')

# Boot the windows-3.11 example (up + console)
[group('example')]
windows-3-11-example-up: (example-up 'windows-3.11')
# Destroy the windows-3.11 example
[group('example')]
windows-3-11-example-down: (example-down 'windows-3.11')

# Boot the windows-7 example (up + console)
[group('example')]
windows-7-example-up: (example-up 'windows-7')
# Destroy the windows-7 example
[group('example')]
windows-7-example-down: (example-down 'windows-7')

# Boot the windows-7-x86 example (up + console)
[group('example')]
windows-7-x86-example-up: (example-up 'windows-7-x86')
# Destroy the windows-7-x86 example
[group('example')]
windows-7-x86-example-down: (example-down 'windows-7-x86')

# Boot the windows-8 example (up + console)
[group('example')]
windows-8-example-up: (example-up 'windows-8')
# Destroy the windows-8 example
[group('example')]
windows-8-example-down: (example-down 'windows-8')

# Boot the windows-8.1 example (up + console)
[group('example')]
windows-8-1-example-up: (example-up 'windows-8.1')
# Destroy the windows-8.1 example
[group('example')]
windows-8-1-example-down: (example-down 'windows-8.1')

# Boot the windows-8.1-x86 example (up + console)
[group('example')]
windows-8-1-x86-example-up: (example-up 'windows-8.1-x86')
# Destroy the windows-8.1-x86 example
[group('example')]
windows-8-1-x86-example-down: (example-down 'windows-8.1-x86')

# Boot the windows-8-x86 example (up + console)
[group('example')]
windows-8-x86-example-up: (example-up 'windows-8-x86')
# Destroy the windows-8-x86 example
[group('example')]
windows-8-x86-example-down: (example-down 'windows-8-x86')

# Boot the windows-server-2008 example (up + console)
[group('example')]
windows-server-2008-example-up: (example-up 'windows-server-2008')
# Destroy the windows-server-2008 example
[group('example')]
windows-server-2008-example-down: (example-down 'windows-server-2008')

# Boot the windows-server-2008-r2 example (up + console)
[group('example')]
windows-server-2008-r2-example-up: (example-up 'windows-server-2008-r2')
# Destroy the windows-server-2008-r2 example
[group('example')]
windows-server-2008-r2-example-down: (example-down 'windows-server-2008-r2')

# Boot the windows-server-2008-x86 example (up + console)
[group('example')]
windows-server-2008-x86-example-up: (example-up 'windows-server-2008-x86')
# Destroy the windows-server-2008-x86 example
[group('example')]
windows-server-2008-x86-example-down: (example-down 'windows-server-2008-x86')

# Boot the windows-server-2012 example (up + console)
[group('example')]
windows-server-2012-example-up: (example-up 'windows-server-2012')
# Destroy the windows-server-2012 example
[group('example')]
windows-server-2012-example-down: (example-down 'windows-server-2012')

# Boot the windows-server-2012-r2 example (up + console)
[group('example')]
windows-server-2012-r2-example-up: (example-up 'windows-server-2012-r2')
# Destroy the windows-server-2012-r2 example
[group('example')]
windows-server-2012-r2-example-down: (example-down 'windows-server-2012-r2')

# Boot the windows-server-2016 example (up + console)
[group('example')]
windows-server-2016-example-up: (example-up 'windows-server-2016')
# Destroy the windows-server-2016 example
[group('example')]
windows-server-2016-example-down: (example-down 'windows-server-2016')

# Boot the windows-server-2019 example (up + console)
[group('example')]
windows-server-2019-example-up: (example-up 'windows-server-2019')
# Destroy the windows-server-2019 example
[group('example')]
windows-server-2019-example-down: (example-down 'windows-server-2019')

# Boot the windows-server-2022 example (up + console)
[group('example')]
windows-server-2022-example-up: (example-up 'windows-server-2022')
# Destroy the windows-server-2022 example
[group('example')]
windows-server-2022-example-down: (example-down 'windows-server-2022')

# Boot the windows-server-2025 example (up + console)
[group('example')]
windows-server-2025-example-up: (example-up 'windows-server-2025')
# Destroy the windows-server-2025 example
[group('example')]
windows-server-2025-example-down: (example-down 'windows-server-2025')

# Boot the windows-vista example (up + console)
[group('example')]
windows-vista-example-up: (example-up 'windows-vista')
# Destroy the windows-vista example
[group('example')]
windows-vista-example-down: (example-down 'windows-vista')

# Boot the windows-vista-x86 example (up + console)
[group('example')]
windows-vista-x86-example-up: (example-up 'windows-vista-x86')
# Destroy the windows-vista-x86 example
[group('example')]
windows-vista-x86-example-down: (example-down 'windows-vista-x86')
