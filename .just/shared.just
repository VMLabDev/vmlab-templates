# Guards for the external tooling the recipes shell out to, so a missing tool
# reports as a missing tool instead of as a confusing failure further in.

[private]
require-vmlab:
	@command -v vmlab > /dev/null 2>&1 || (echo "vmlab is required (cargo install --git https://github.com/wiltaylor/vmlab.git vmlab)" && exit 1)

[private]
require-wcl:
	@command -v wcl > /dev/null 2>&1 || (echo "wcl is required (cargo install --git https://github.com/wiltaylor/wcl.git wcl)" && exit 1)

[private]
require-uv:
	@command -v uv > /dev/null 2>&1 || (echo "uv is required (https://docs.astral.sh/uv/)" && exit 1)

[private]
require-git:
	@command -v git > /dev/null 2>&1 || (echo "git is required" && exit 1)
