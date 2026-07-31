"""Parse and schema-check every template definition in the unified vmlab.wcl.

`wcl check` cannot be used here: every template definition starts with
`import <vmlab.wcl>`, a system import that only the `vmlab` binary registers, so
plain `wcl` fails on all of them regardless of their contents. `vmlab validate`
does register it, and walks the whole document — but it also asserts that every
referenced source file exists. The local-media templates (the MSDN/VL Windows
ISOs in iso/, and the payloads each fetch-deps.sh stages) point at artefacts that
are deliberately gitignored and absent from a clean checkout.

So: a "<path> does not exist" diagnostic is tolerated when, and only when, git
agrees the path is ignored. Every other diagnostic fails the check, as does any
diagnostic this script cannot parse — an unrecognised `vmlab validate` failure
must never read as a pass.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# `  × the message`, plus `  │ its continuation` for messages miette wrapped.
# Source-frame lines carry a line number before the bar (` 910 │ ...`), so they
# do not match the continuation pattern.
DIAGNOSTIC = re.compile(r"^\s*×\s?(.*)$")
CONTINUATION = re.compile(r"^\s*│\s?(.*)$")

# The `N error(s) in <file>` banner miette prints above the individual errors.
BANNER = re.compile(r"^\d+ error\(s\) in ")
MISSING_PATH = re.compile(r"(\S+) does not exist$")


def diagnostics(output):
    """Yield each diagnostic as its list of (possibly wrapped) message lines."""
    lines = output.splitlines()
    index = 0
    while index < len(lines):
        match = DIAGNOSTIC.match(lines[index])
        index += 1
        if not match:
            continue
        parts = [match.group(1).rstrip()]
        while index < len(lines):
            continuation = CONTINUATION.match(lines[index])
            if not continuation:
                break
            parts.append(continuation.group(1).rstrip())
            index += 1
        yield parts


def unwrapped(parts):
    """Reconstructions of a wrapped message.

    miette breaks a long message at a space, but breaks a long *token* after a
    `-` or `/` with no space to restore. Both readings are tried; a message we
    cannot reassemble simply fails to match and is reported as unexplained.
    """
    joined = parts[0]
    for part in parts[1:]:
        joined += part if joined.endswith(("-", "/")) else " " + part
    return [" ".join(parts), joined]


def is_ignored(path):
    return (
        subprocess.run(
            ["git", "check-ignore", "-q", "--", path],
            cwd=ROOT,
            capture_output=True,
        ).returncode
        == 0
    )


def tolerated_path(messages):
    """The gitignored local artefact this diagnostic is about, if it is one."""
    for message in messages:
        match = MISSING_PATH.search(message)
        if not match:
            continue
        path = match.group(1)
        if not (ROOT / path).exists() and is_ignored(path):
            return path
    return None


def main():
    result = subprocess.run(
        ["vmlab", "validate"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        env={**os.environ, "NO_COLOR": "1"},
    )
    output = result.stdout + result.stderr
    if result.returncode == 0:
        print("vmlab validate: ok")
        return 0

    tolerated = []
    unexplained = []
    for parts in diagnostics(output):
        messages = unwrapped(parts)
        if any(BANNER.match(message) for message in messages):
            continue
        path = tolerated_path(messages)
        if path:
            tolerated.append(path)
        else:
            unexplained.append(messages[0])

    if unexplained or not tolerated:
        print(output, end="" if output.endswith("\n") else "\n", file=sys.stderr)
        if unexplained:
            print(
                f"{len(unexplained)} vmlab validate error(s) are not missing "
                "local media:",
                file=sys.stderr,
            )
            for message in unexplained:
                print(f"  - {message}", file=sys.stderr)
        else:
            print(
                "vmlab validate failed with no diagnostics this check could "
                "account for",
                file=sys.stderr,
            )
        return 1

    print(
        f"vmlab validate: ok ({len(tolerated)} reference(s) to gitignored local "
        "media absent from this checkout)"
    )
    for path in sorted(set(tolerated)):
        print(f"  - {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
