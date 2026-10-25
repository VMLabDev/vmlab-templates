#!/bin/sh
# Runs inside debian:trixie for build.sh: Venus only, x86_64 and i686.
set -eu
export DEBIAN_FRONTEND=noninteractive
# Hand out/ back to the caller whether or not the build succeeds.
trap 'chown -R "$HOST_UID:$HOST_GID" /out' EXIT

dpkg --add-architecture i386
apt-get update -qq
# Per-architecture libraries for both builds; meson, mako and glslang run natively.
libs="libdrm-dev libwayland-dev libx11-dev libx11-xcb-dev libxcb1-dev libxcb-dri3-dev
      libxcb-present-dev libxcb-randr0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-shm0-dev
      libxshmfence-dev libxrandr-dev libexpat1-dev zlib1g-dev libzstd-dev libudev-dev"
i386_libs=""
for p in $libs; do i386_libs="$i386_libs $p:i386"; done
apt-get install -y -qq --no-install-recommends \
    meson ninja-build python3-mako python3-yaml python3-packaging pkg-config \
    gcc g++ gcc-i686-linux-gnu g++-i686-linux-gnu wayland-protocols libwayland-bin \
    glslang-tools bison flex xz-utils patch ca-certificates $libs $i386_libs >/dev/null

mkdir -p /build
tar -C /build -xf "/venus/dl/mesa-${MESA_VERSION}.tar.xz"
cd "/build/mesa-${MESA_VERSION}"
for p in /venus/patches/*.patch; do
    echo "applying $(basename "$p")"
    patch -s -p1 < "$p"
done

cat > /build/i686.cross <<'EOF'
[binaries]
c = 'i686-linux-gnu-gcc'
cpp = 'i686-linux-gnu-g++'
ar = 'i686-linux-gnu-ar'
strip = 'i686-linux-gnu-strip'
pkg-config = 'pkg-config'

[properties]
pkg_config_libdir = ['/usr/lib/i386-linux-gnu/pkgconfig', '/usr/share/pkgconfig']

[host_machine]
system = 'linux'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
EOF

# Only the Venus ICD: no Gallium, GL, EGL, GBM or LLVM. x11 and wayland are
# the window systems Venus's WSI has to serve under gamescope and Plasma.
opts="--prefix=/usr --buildtype=release -Dvulkan-drivers=virtio -Dgallium-drivers=
      -Dplatforms=x11,wayland -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false
      -Dgles1=disabled -Dgles2=disabled -Dllvm=disabled -Dvalgrind=disabled
      -Dlibunwind=disabled -Dvideo-codecs= -Dtools="

build() {  # build <arch> [meson args...]
    arch="$1"; shift
    meson setup "/build/b-$arch" $opts "$@" > "/build/meson-$arch.log" 2>&1 ||
        { tail -40 "/build/meson-$arch.log"; exit 1; }
    ninja -C "/build/b-$arch" src/virtio/vulkan/libvulkan_virtio.so > "/build/ninja-$arch.log" 2>&1 ||
        { tail -40 "/build/ninja-$arch.log"; exit 1; }
    mkdir -p "/out/$arch"
    cp "/build/b-$arch/src/virtio/vulkan/libvulkan_virtio.so" "/out/$arch/"
    echo "$arch: needs $(objdump -T "/out/$arch/libvulkan_virtio.so" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
}

build x86_64 --libdir=lib
build i686 --libdir=lib32 --cross-file /build/i686.cross
