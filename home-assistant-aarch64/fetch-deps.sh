#!/usr/bin/env bash
# Prepare the Home Assistant OS build image with the vmlab guest agent injected.
#
# HAOS is a sealed, immutable A/B appliance: its rootfs is read-only (erofs), it
# has no package manager and no in-guest install path, so the normal VMLAB
# bootstrap ISO can't run. Instead we inject the agent OFFLINE into the two
# writable partitions the OS keeps across updates:
#
#   hassos-data (sda8)     -> /vmlab/vmlab-agent          (the aarch64 agent)
#   hassos-overlay (sda7)  -> /etc/modules-load.d/vmlab.conf   (load virtio_console)
#                             /etc/udev/rules.d/99-vmlab-agent.rules
#
# HAOS's "overlay" is NOT a general /etc overlay — it bind-mounts only specific
# config dirs from the overlay partition (modules-load.d, udev/rules.d, ...), so
# a plain systemd unit can't be added that way. The launch is therefore a udev
# rule that hands off to systemd-run when the vmlab.agent.0 virtio-serial port
# appears; modules-load.d guarantees the port exists. Restart=always with the
# rate limit disabled rides out /mnt/data mounting after the rule fires, and the
# agent itself polls /sys/class/virtio-ports until the port binds — so every
# boot-ordering race is retried into success.
#
# Output: haos_generic-aarch64-<ver>.qcow2 (gitignored) — the template's source.
set -euo pipefail
cd "$(dirname "$0")"

VER="17.3"
URL="https://github.com/home-assistant/operating-system/releases/download/${VER}/haos_generic-aarch64-${VER}.qcow2.xz"
XZ_SHA256="f5b2f350557cfff91b4d2e33777b623c0203858d94a116b29962c8147ab456e5"
OUT="haos_generic-aarch64-${VER}.qcow2"

# The aarch64 agent binary, built by ../../vmlab/guest/build-agent.sh and
# installed into the guest asset dir (or pointed at by VMLAB_GUEST_ASSET_DIR).
agent_bin=""
for d in "${VMLAB_GUEST_ASSET_DIR:-}" /usr/share/vmlab/guest "$HOME/.local/share/vmlab/guest"; do
    [ -n "$d" ] || continue
    if [ -f "$d/agent/linux-aarch64/vmlab-agent" ]; then
        agent_bin="$d/agent/linux-aarch64/vmlab-agent"
        break
    fi
done
[ -n "$agent_bin" ] || {
    echo "error: no linux-aarch64 vmlab-agent found; build it with" >&2
    echo "  ../../vmlab/guest/build-agent.sh linux-aarch64" >&2
    echo "and install it under ~/.local/share/vmlab/guest/agent/linux-aarch64/" >&2
    exit 1
}
echo "using agent: $agent_bin"

for t in curl xz sha256sum guestfish; do command -v "$t" >/dev/null || { echo "missing $t" >&2; exit 1; }; done

# Download + verify the compressed image (cached).
CACHE="${TMPDIR:-/tmp}/vmlab-haos/haos_generic-aarch64-${VER}.qcow2.xz"
if [ ! -f "$CACHE" ]; then
    mkdir -p "$(dirname "$CACHE")"
    echo "downloading HAOS ${VER}..."
    curl -fSL --retry 3 -o "$CACHE.tmp" "$URL"
    mv "$CACHE.tmp" "$CACHE"
fi
echo "$XZ_SHA256  $CACHE" | sha256sum -c --quiet - || { echo "sha256 mismatch on $CACHE" >&2; exit 1; }

echo "decompressing..."
xz -dc "$CACHE" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

# --- staging: the config files to inject into the overlay ---------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'virtio_console\n' > "$work/vmlab.modules-load.conf"

# udev fires this when the agent port appears; systemd-run hands the daemon off
# to systemd (udev would otherwise reap it). Restart=always + no rate limit ride
# out /mnt/data mounting late; --collect garbage-collects the unit if it exits.
cat > "$work/99-vmlab-agent.rules" <<'RULES'
ACTION=="add", SUBSYSTEM=="virtio-ports", ATTR{name}=="vmlab.agent.0", RUN+="/usr/bin/systemd-run --unit=vmlab-agent --collect --property=Restart=always --property=RestartSec=2 --property=StartLimitIntervalSec=0 /mnt/data/vmlab/vmlab-agent"
RULES

# --- inject (guestfish, read-write) ------------------------------------------
echo "injecting agent + launch hooks into $OUT..."
guestfish --rw -a "$OUT" <<EOF
run
# hassos-data (persistent): the agent binary
mount /dev/sda8 /
mkdir-p /vmlab
upload $agent_bin /vmlab/vmlab-agent
chmod 0755 /vmlab/vmlab-agent
umount /
# hassos-overlay: the bind-mounted config that loads the module + launches it.
# mkdir-p is a no-op where the bind-source dirs already exist.
mount /dev/sda7 /
mkdir-p /etc/modules-load.d
mkdir-p /etc/udev/rules.d
upload $work/vmlab.modules-load.conf /etc/modules-load.d/vmlab.conf
upload $work/99-vmlab-agent.rules /etc/udev/rules.d/99-vmlab-agent.rules
umount /
EOF

echo "done: $OUT (agent injected)"
