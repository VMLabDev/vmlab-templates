"""Parse and schema-check the repo's .wcl definitions with `vmlab validate`.

    validate-templates.py templates   # every template definition
    validate-templates.py examples    # every examples/<name>/ lab

`wcl check` cannot be used for either: every definition starts with
`import <vmlab.wcl>`, a system import that only the `vmlab` binary registers, so
plain `wcl` fails on all of them regardless of their contents. `vmlab validate`
does register it and walks the whole document — but it also asserts facts about
the machine it runs on, and a merge bar has to pass from a clean checkout:

  * Referenced source files must exist. The local-media templates (the MSDN/VL
    Windows ISOs in iso/, and the payloads each fetch-deps.sh stages) point at
    artefacts that are deliberately gitignored and absent from a fresh clone.
  * A lab's template must be in the local store. Nothing is built at gate time.

So a diagnostic is tolerated only when it is one of those two, and a missing
path only when git agrees it is ignored. Every other diagnostic fails the check,
as does any diagnostic this script cannot parse — an unrecognised
`vmlab validate` failure must never read as a pass.

The templates are checked through the generated unified vmlab.wcl, since
`vmlab validate` wants a `lab` block and a template directory has none. Run
`just ci::wcl-sync-check` alongside this, or the file checked here may be a
stale rendering of the per-template definitions.
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
MISSING_TEMPLATE = re.compile(r"^template (\S+) not in the template store$")


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


def is_ignored(directory, path):
    return (
        subprocess.run(
            ["git", "check-ignore", "-q", "--", path],
            cwd=directory,
            capture_output=True,
        ).returncode
        == 0
    )


def excuse(directory, messages):
    """What absent-from-this-machine thing this diagnostic is about, if any."""
    for message in messages:
        match = MISSING_TEMPLATE.match(message)
        if match:
            return f"template {match.group(1)} (not in this store)"
        match = MISSING_PATH.search(message)
        if match:
            path = match.group(1)
            if not (directory / path).exists() and is_ignored(directory, path):
                return f"{path} (gitignored local media)"
    return None


def validate(directory):
    """Run `vmlab validate` in one directory.

    Returns (excused, unexplained): what was tolerated, and what was not.
    """
    result = subprocess.run(
        ["vmlab", "validate"],
        cwd=directory,
        capture_output=True,
        text=True,
        env={**os.environ, "NO_COLOR": "1"},
    )
    if result.returncode == 0:
        return [], []

    output = result.stdout + result.stderr
    excused, unexplained = [], []
    for parts in diagnostics(output):
        messages = unwrapped(parts)
        if any(BANNER.match(message) for message in messages):
            continue
        excused_by = excuse(directory, messages)
        if excused_by:
            excused.append(excused_by)
        else:
            unexplained.append(messages[0])

    if not excused and not unexplained:
        # A non-zero exit we could not account for at all: report it whole.
        unexplained.append(output.strip() or "vmlab validate failed silently")
    return excused, unexplained


def report(label, directory):
    """Validate one directory, printing what happened. True if it passed."""
    excused, unexplained = validate(directory)
    if unexplained:
        print(f"{label}: FAILED", file=sys.stderr)
        for message in unexplained:
            print(f"  {message}", file=sys.stderr)
        return False
    for message in sorted(set(excused)):
        print(f"  - {message}")
    return True


def main(argv):
    if len(argv) != 2 or argv[1] not in ("templates", "examples"):
        print(f"usage: {argv[0]} templates|examples", file=sys.stderr)
        return 2

    if argv[1] == "templates":
        print("vmlab.wcl — every template definition")
        return 0 if report("vmlab.wcl", ROOT) else 1

    labs = sorted(
        path.parent
        for path in (ROOT / "examples").glob("*/vmlab.wcl")
    )
    print(f"examples/ — {len(labs)} lab(s)")
    # Every lab is checked before failing, so one broken example does not hide
    # the rest.
    return 0 if all([report(f"examples/{lab.name}", lab) for lab in labs]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
