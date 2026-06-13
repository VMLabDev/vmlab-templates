"""Build one template directory, idempotently.

Reads arch/name/version from the directory's vmlab.wcl, skips the build if
that exact ref is already in the local store (vmlab refuses to overwrite),
runs fetch-deps.sh first when the template has one (Kali/Parrot/Windows
stage payloads vmlab cannot download itself), then runs the build.
"""

import re
import subprocess
import sys
from pathlib import Path


def wcl_attr(text: str, pattern: str, path: Path) -> str:
    m = re.search(pattern, text)
    if not m:
        sys.exit(f"could not find {pattern!r} in {path}")
    return m.group(1)


def main() -> None:
    tdir = Path(sys.argv[1])
    wcl_path = tdir / "vmlab.wcl"
    wcl = wcl_path.read_text()

    name = wcl_attr(wcl, r'template\s+"([^"]+)"', wcl_path)
    arch = wcl_attr(wcl, r'arch\s*=\s*"([^"]+)"', wcl_path)
    version = wcl_attr(wcl, r'version\s*=\s*"([^"]+)"', wcl_path)
    ref = f"{arch}/{name}@{version}"

    listing = subprocess.run(
        ["vmlab", "template", "list"], capture_output=True, text=True, check=True
    ).stdout
    in_store = any(
        line.split()[:3] == [arch, name, version]
        for line in listing.splitlines()[1:]
        if line.strip()
    )
    if in_store:
        print(f"{ref} already in the store; skipping (vmlab template rm to rebuild)")
        return

    if (tdir / "fetch-deps.sh").exists():
        subprocess.run(["./fetch-deps.sh"], cwd=tdir, check=True)

    subprocess.run(["vmlab", "template", "build"], cwd=tdir, check=True)


if __name__ == "__main__":
    main()
