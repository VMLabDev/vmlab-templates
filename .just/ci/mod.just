# The verification gate for this repo. Everything here runs from a clean
# checkout with no prior build step, reads only in-repo files, and needs no
# network.
#
# Recipes run from the repo root, not from .just/ci/.

import '../shared.just'

set working-directory := '../..'

[default, private]
main:
	@just --list ci

# Template *builds* are deliberately not in the gate: hours of runtime, KVM, and
# hand-supplied ISOs for the Windows and vintage targets. Nor is `just
# docs-data`, which needs GHCR auth and a network.

# Everything a change must pass before it can merge
[group('ci')]
check: wcl-sync-check wcl-check examples-check docs-build

# Regenerating from the per-template definitions and diffing keeps an edit to
# <template>/vmlab.wcl from landing unpropagated — and is what makes wcl-check
# below a check on the definitions actually in the tree.

# Verify vmlab.wcl matches a regeneration from the per-template definitions
[group('ci')]
wcl-sync-check:
	#!/usr/bin/env bash
	set -euo pipefail
	generated=$(mktemp)
	trap 'rm -f "$generated"' EXIT
	scripts/generate-unified-wcl.sh "$generated"
	if ! diff -u vmlab.wcl "$generated"; then
		echo
		echo "vmlab.wcl is stale — regenerate it with: bash scripts/generate-unified-wcl.sh"
		exit 1
	fi
	echo "vmlab.wcl matches the per-template definitions"

# Goes through the unified vmlab.wcl because `wcl check` cannot read the
# definitions on its own: they import the system schema <vmlab.wcl>, which only
# the vmlab binary registers.

# Parse and schema-check every template definition
[group('ci')]
wcl-check: require-vmlab require-uv require-git
	uv run python scripts/validate-templates.py templates

# A lab whose template is not in this machine's store is tolerated — the gate
# builds nothing — so this catches a malformed example, not a wrong ref.

# Parse and schema-check every examples/<name>/ lab
[group('ci')]
examples-check: require-vmlab require-uv require-git
	uv run python scripts/validate-templates.py examples

# The same build deploy-site.yml deploys, so a broken docs change fails here
# rather than on main. Writes the gitignored docs/_site (`just docs-clean`
# removes it).

# Build the template-library website
[group('ci')]
docs-build: require-wcl
	wcl wdoc build docs/main.wcl --out docs/_site
