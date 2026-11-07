#!/usr/bin/env python3
"""VML-85 QEMU helper. Runs on helios with python3 -I.

q.py hmp  <monsock> <command...>     run one HMP command, print the reply
q.py type <monsock> <text>           type text with sendkey (\\n = ret)
q.py key  <monsock> <key> [...]      send raw sendkey names (f8, ret, spc, n)
q.py text <monsock> <tmpfile>        print the 80x25 VGA text screen
q.py shot <monsock> <png>            screendump as PNG
q.py host <agentsock> <log> <secs> <interval> [silent]
    act as the vmlab daemon: every <interval> s connect, send a Hello frame,
    read for a while, log every byte, stop after <secs> s.
"""
import json
import os
import socket
import struct
import sys
import time


def hmp(path, cmd, wait=0.3):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    s.settimeout(1.0)
    buf = b""
    try:
        while not buf.endswith(b"(qemu) "):
            buf += s.recv(4096)
    except socket.timeout:
        pass
    s.sendall(cmd.encode() + b"\n")
    time.sleep(wait)
    out = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
            if out.endswith(b"(qemu) "):
                break
    except socket.timeout:
        pass
    s.close()
    return out.decode(errors="replace")


def clean(out):
    return "\n".join(l for l in out.splitlines() if "\x1b" not in l)


KEYMAP = {" ": "spc", "\n": "ret", "\\": "backslash", ":": "shift-semicolon", ".": "dot",
          "-": "minus", "/": "slash", "=": "equal", ",": "comma", ";": "semicolon",
          "_": "shift-minus", "*": "shift-8", ">": "shift-dot", "\"": "shift-apostrophe"}


def keyname(c):
    if c in KEYMAP:
        return KEYMAP[c]
    if c.isupper():
        return "shift-" + c.lower()
    return c


def main():
    op = sys.argv[1]
    if op == "hmp":
        print(clean(hmp(sys.argv[2], " ".join(sys.argv[3:]), 1.0)))
    elif op == "type":
        text = sys.argv[3].replace("\\n", "\n")
        for c in text:
            hmp(sys.argv[2], "sendkey " + keyname(c), 0.05)
            time.sleep(0.08)
    elif op == "key":
        for k in sys.argv[3:]:
            hmp(sys.argv[2], "sendkey " + k, 0.05)
            time.sleep(0.2)
    elif op == "text":
        tmp = sys.argv[3]
        hmp(sys.argv[2], "pmemsave 0xb8000 4000 \"%s\"" % tmp, 0.5)
        with open(tmp, "rb") as f:
            data = f.read()
        for row in range(25):
            line = data[row * 160:(row + 1) * 160:2]
            print(line.decode("cp437", errors="replace").rstrip())
    elif op == "shot":
        print(clean(hmp(sys.argv[2], "screendump \"%s\" -f png" % sys.argv[3], 1.0)))
    elif op == "host":
        host(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]),
             len(sys.argv) > 6 and sys.argv[6] == "silent")
    elif op == "exec":
        sys.exit(do_exec(sys.argv[2], int(sys.argv[3]), sys.argv[4:]))
    else:
        sys.exit("unknown op " + op)


def read_frames(s, buf):
    """Return (frames, rest) with frames as (kind, channel, payload)."""
    out = []
    while True:
        i = buf.find(b"VMLB")
        if i < 0:
            return out, buf[-3:]
        buf = buf[i:]
        if len(buf) < 13:
            return out, buf
        n = struct.unpack("<I", buf[4:8])[0]
        if len(buf) < 13 + n:
            return out, buf
        out.append((buf[8], struct.unpack("<I", buf[9:13])[0], buf[13:13 + n]))
        buf = buf[13 + n:]


def do_exec(path, timeout, argv):
    """q.py exec <agentsock> <timeout> <argv...>: run argv through the agent."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(path)
    s.settimeout(1.0)
    s.sendall(frame(json.dumps({"cmd": "hello", "proto_version": 2, "token": "v85x"}).encode()))
    end = time.time() + timeout
    buf = b""
    state = "hello"
    code = None
    while time.time() < end:
        try:
            c = s.recv(65536)
            if not c:
                print("closed", file=sys.stderr)
                return 3
            buf += c
        except socket.timeout:
            continue
        frames, buf = read_frames(s, buf)
        for kind, ch, payload in frames:
            if kind == 0 and ch == 0:
                msg = json.loads(payload.decode(errors="replace"))
                if state == "hello" and msg.get("cmd") == "hello" and msg.get("token") == "v85x":
                    print("agent: %s" % payload.decode(errors="replace"), file=sys.stderr)
                    s.sendall(frame(json.dumps({"cmd": "open_exec", "id": 1, "argv": argv}).encode()))
                    state = "exec"
                elif msg.get("cmd") == "exited" and msg.get("id") == 1:
                    code = msg.get("code")
                    print("exit %s" % code, file=sys.stderr)
                    s.close()
                    return 0 if code == 0 else 1
                elif state == "exec":
                    print("ctrl: %s" % payload.decode(errors="replace"), file=sys.stderr)
            elif ch == 1:
                sys.stdout.write(payload.decode("cp437", errors="replace"))
                sys.stdout.flush()
    print("timeout in state %s" % state, file=sys.stderr)
    return 4


def frame(payload):
    return b"VMLB" + struct.pack("<I", len(payload)) + b"\x00" + struct.pack("<I", 0) + payload


def host(path, logpath, secs, interval, silent):
    end = time.time() + secs
    n = 0
    with open(logpath, "a") as log:
        def w(msg):
            log.write("%s %s\n" % (time.strftime("%H:%M:%S"), msg))
            log.flush()
        w("host start silent=%s interval=%d" % (silent, interval))
        while time.time() < end:
            n += 1
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(path)
            except OSError as e:
                w("connect failed: %s" % e)
                time.sleep(2)
                continue
            if not silent:
                tok = "v85-%d" % n
                s.sendall(frame(json.dumps({"cmd": "hello", "proto_version": 2, "token": tok}).encode()))
                w("sent hello %s" % tok)
            s.settimeout(1.0)
            got = b""
            t0 = time.time()
            while time.time() - t0 < interval and time.time() < end:
                try:
                    c = s.recv(65536)
                    if not c:
                        w("closed by qemu")
                        break
                    got += c
                    w("recv %d bytes: %r" % (len(c), c[:200]))
                    if b'"hello"' in got and b"v85-%d" % n in got:
                        w("ANSWERED hello v85-%d" % n)
                except socket.timeout:
                    pass
            s.close()
        w("host end")


if __name__ == "__main__":
    main()
