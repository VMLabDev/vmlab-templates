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

# --- Examples: smoke-test one template in a throwaway one-VM lab ---
# `example-up` stamps the chosen `<arch>/<name>` over the default ref in
# examples/vmlab.wcl into examples/.run/ (gitignored), brings the lab up and
# opens its console; `example-down` destroys it. Only the named template needs
# to be in the store (built locally or pulled). See examples/vmlab.wcl.

# Boot a one-VM lab for a template (arch defaults to x86_64) and open its console
[group('example')]
example-up name arch='x86_64':
	#!/usr/bin/env bash
	set -euo pipefail
	mkdir -p examples/.run
	[ -f examples/.run/vmlab.wcl ] && (cd examples/.run && vmlab destroy >/dev/null 2>&1 || true)
	sed 's#x86_64/ubuntu-24.04#{{ arch }}/{{ name }}#' examples/vmlab.wcl > examples/.run/vmlab.wcl
	cd examples/.run
	vmlab up
	vmlab console guest

# Destroy the example lab spun up by `example-up`
[group('example')]
example-down:
	cd examples/.run && vmlab destroy
