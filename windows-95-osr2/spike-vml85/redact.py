#!/usr/bin/env python3
"""Copy stdin to stdout with the OEM key and its digit groups replaced.
Usage: redact.py <file holding one WINDOWS_95_OEM_KEY=... line>"""
import sys

line = open(sys.argv[1]).read().strip()
key = line.split("=", 1)[1].strip().strip('"').strip("'") if "=" in line else ""
parts = [key] + [p for p in key.split("-") if len(p) >= 5 and p.upper() != "OEM"]
if key:
    parts.append(key.replace("-", ""))
if len(sys.argv) > 2 and sys.argv[2] == "--scan":
    import os
    hits = 0
    for root in sys.argv[3:]:
        for d, _, files in os.walk(root):
            for f in files:
                path = os.path.join(d, f)
                if f == ".env" or f.endswith((".qcow2", ".iso", ".img", ".IMA", ".ZIP", ".EXE", ".png")):
                    continue
                try:
                    data = open(path, "rb").read()
                except OSError:
                    continue
                if key and any(p.encode() in data for p in parts if p):
                    hits += 1
                    print("key found in", path)
    print("key scan: %d files hold the key (disks, images, .env excluded)" % hits)
    sys.exit(0)
for raw in sys.stdin:
    for p in parts:
        if p:
            raw = raw.replace(p, "<REDACTED>")
    sys.stdout.write(raw)
    sys.stdout.flush()
