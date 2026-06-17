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

# Build every x86_64 template into the local store
[group('build')]
build: alpine-build debian-build fedora-build kali-build nixos-build parrot-build rocky-build ubuntu-build windows-build

# Build the Alpine Linux 3.23 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
alpine-arm64-build: (template-build 'alpine-3.23-arm64' 'aarch64/alpine-3.23')

# Build the Debian 13 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
debian-arm64-build: (template-build 'debian-13-arm64' 'aarch64/debian-13')

# Build the Fedora 44 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
fedora-arm64-build: (template-build 'fedora-44-arm64' 'aarch64/fedora-44')

# Build the Ubuntu Server 24.04 arm64 template (runs under TCG on x86 hosts)
[group('build-arm64')]
ubuntu-arm64-build: (template-build 'ubuntu-arm64' 'aarch64/ubuntu-24.04')

# Build every arm64 template into the local store (slow under TCG)
[group('build-arm64')]
build-arm64: alpine-arm64-build debian-arm64-build fedora-arm64-build ubuntu-arm64-build
