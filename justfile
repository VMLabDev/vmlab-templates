[default, private]
main:
	@just --list

# Build one template directory (skips if already in the store; runs fetch-deps.sh if present)
[group('build')]
template-build dir:
	uv run python scripts/template-build.py '{{ dir }}'

# Build the Alpine Linux 3.23 template
[group('build')]
alpine-build: (template-build 'alpine-3.23')

# Build the Debian 13 template
[group('build')]
debian-build: (template-build 'debian-13')

# Build the Fedora 44 template
[group('build')]
fedora-build: (template-build 'fedora-44')

# Build the Kali Linux template
[group('build')]
kali-build: (template-build 'kali')

# Build the NixOS 25.11 template
[group('build')]
nixos-build: (template-build 'nixos-25.11')

# Build the Parrot OS Security template
[group('build')]
parrot-build: (template-build 'parrot')

# Build the Rocky Linux 9 template
[group('build')]
rocky-build: (template-build 'rocky-9')

# Build the Ubuntu Server 24.04 template
[group('build')]
ubuntu-build: (template-build 'ubuntu-24.04')

# Build the Windows Server 2025 template (sysprep-generalized)
[group('build')]
windows-build: (template-build 'windows-server-2025')

# Build every template into the local store
[group('build')]
build: alpine-build debian-build fedora-build kali-build nixos-build parrot-build rocky-build ubuntu-build windows-build
