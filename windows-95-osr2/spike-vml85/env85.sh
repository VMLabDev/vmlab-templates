# VML-85 private vmlab env on helios (MEM-104). Source it.
# Private data (build workdirs), runtime, state, config (vm = "qemu").
# Templates: a symlink to the shared store (MEM-101). Guest assets: symlinks
# to wil's read-only asset dirs.
B=/var/build/cache/vmlab/vml85
export XDG_DATA_HOME=$B/data
export XDG_RUNTIME_DIR=/tmp/v85run
export XDG_STATE_HOME=$B/state
export XDG_CONFIG_HOME=$B/config
export XDG_CACHE_HOME=$B/xdgcache
export VMLAB_SKIP_UPDATES=1
export CARGO_BUILD_JOBS=4
export VMLAB_GUEST_ASSET_DIR=$B/guest
export PATH=$B/vmlab/bin:$PATH
mkdir -p -m 700 "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_STATE_HOME" "$XDG_CONFIG_HOME/vmlab" "$XDG_DATA_HOME/vmlab/cache" "$XDG_CACHE_HOME" "$B/guest"
shared=$(readlink -f "$HOME/.local/share/vmlab/templates")
[ -n "$shared" ] && [ "$shared" != / ] || { echo "v85: shared store unresolved" >&2; return 1; }
[ -L "$XDG_DATA_HOME/vmlab/templates" ] || ln -s "$shared" "$XDG_DATA_HOME/vmlab/templates"
[ "$(readlink -f "$XDG_DATA_HOME/vmlab/templates")" = "$shared" ] || { echo "v85: REFUSED: store mismatch" >&2; return 1; }
case "$(readlink -f "$XDG_DATA_HOME/vmlab/cache")" in
  /var/build/cache/vmlab/vml85/data/vmlab/cache) ;;
  *) echo "v85: REFUSED: cache not private" >&2; return 1;;
esac
for a in agent firmware x86_64 aarch64; do
  [ -L "$B/guest/$a" ] || ln -s "/home/wil/.local/share/vmlab/guest/$a" "$B/guest/$a"
done
cat > "$XDG_CONFIG_HOME/vmlab/config.wcl" <<'W'
// VML-85 private host config: QEMU KVM for the windows-9x (i440fx) profile.
import <vmlab-host.wcl>
host {
  hypervisor { vm = "qemu" }
}
W
echo "v85: store $shared (shared), builds $XDG_DATA_HOME/vmlab/cache/builds (private), runtime $XDG_RUNTIME_DIR" >&2
