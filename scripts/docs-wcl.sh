#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
rev=$(cat "$repo/.wcl-rev")
root="$repo/.scratch/tools/wcl/$rev"

if [[ ${1:-} == --install ]]; then
	cargo install --git https://github.com/wiltaylor/wcl.git --rev "$rev" --locked --root "$root" wcl
	exit 0
fi

if [[ ! -x "$root/bin/wcl" ]]; then
	printf 'Pinned WCL %s is required. Run: just docs-tool-install\n' "$rev" >&2
	exit 1
fi

exec "$root/bin/wcl" "$@"
