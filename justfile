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

# Build every x86_64 template into the local store
[group('build')]
build: alpine-build debian-build fedora-build kali-build nixos-build parrot-build rocky-build ubuntu-build windows-build windows-server-2022-build windows-server-2019-build windows-11-build windows-10-build

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
build-vintage: dos-6-22-build windows-3-11-build windows-2000-build

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
