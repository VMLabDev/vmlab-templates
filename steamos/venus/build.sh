#!/bin/sh
# Build the Venus Vulkan driver (libvulkan_virtio.so, 64- and 32-bit) that the
# steamos template installs over the one SteamOS ships.
#
# SteamOS 3.8.14 ships Mesa 25.3.0, whose Venus forces Mesa's software WSI
# whenever the host GPU runs NVIDIA's proprietary driver. Every Vulkan and
# Zink-on-Vulkan X11 window then presents by CPU copy, and in game mode Steam's
# own UI (CEF composited on the GPU) comes out black. Mesa 26.0 restricts the
# software WSI to NVIDIA drivers older than 590.48.01; patches/ backports that
# (upstream f4cd0bf8, and 5106ab5c, which it needs) onto the 25.3.0 release.
# On AMD and Intel hosts the result behaves as SteamOS's own build.
#
# The build runs in debian:trixie, whose glibc (2.41) is SteamOS 3.8's, and
# writes out/x86_64/libvulkan_virtio.so and out/i686/libvulkan_virtio.so.
# Needs curl and Docker. The release tarball is cached in dl/.
set -eu

MESA_VERSION="25.3.0"
MESA_URL="https://archive.mesa3d.org/mesa-${MESA_VERSION}.tar.xz"
MESA_SHA256="0fd54fea7dbbddb154df05ac752b18621f26d97e27863db3be951417c6abe8ae"

cd "$(dirname "$0")"
here="$(pwd)"

if [ -f out/x86_64/libvulkan_virtio.so ] && [ -f out/i686/libvulkan_virtio.so ] &&
   [ out/x86_64/libvulkan_virtio.so -nt build.sh ] && [ -z "$(find patches -newer out/x86_64/libvulkan_virtio.so)" ]; then
    echo "venus: out/ is up to date"
    exit 0
fi

mkdir -p dl
tarball="dl/mesa-${MESA_VERSION}.tar.xz"
if [ ! -f "$tarball" ]; then
    echo "venus: downloading ${MESA_URL} ..."
    curl -L --fail -o "$tarball.part" "$MESA_URL"
    mv "$tarball.part" "$tarball"
fi
echo "${MESA_SHA256}  ${tarball}" | sha256sum -c -

rm -rf out
mkdir -p out
docker run --rm \
    -v "$here:/venus:ro" \
    -v "$here/out:/out" \
    -e MESA_VERSION="$MESA_VERSION" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    debian:trixie sh /venus/container-build.sh

ls -l out/x86_64/libvulkan_virtio.so out/i686/libvulkan_virtio.so
