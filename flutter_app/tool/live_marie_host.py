#!/usr/bin/env python3
"""Mac side of integration_test/v3_marie_live_test.dart.

Tails the flutter drive log; on `CMD:<name>` plays /tmp/ft_ws/phone_clips/<name>.wav
through the Mac speaker (afplay). `BGSTART:<name>` loops a clip in the
background until `BGSTOP`. Writes `<log dir>/host_events.txt` with epoch ms.
Usage: live_marie_host.py <run.log>
"""
import os, re, subprocess, sys, time, threading
LOG = sys.argv[1]; CL = os.environ.get("CLIPS", "/tmp/ft_ws/phone_clips")
OUT = open(os.path.join(os.path.dirname(LOG), "host_events.txt"), "a", buffering=1)
bg = None
def ev(s): OUT.write(f"{int(time.time()*1000)} {s}\n")
def play(name):
    ev(f"SAY_START {name}"); subprocess.run(["afplay", f"{CL}/{name}.wav"]); ev(f"SAY_END {name}")
def bgstart(name):
    global bg
    def loop():
        while bg is not None and bg.get("run"):
            p = subprocess.Popen(["afplay", "-v", "0.15", f"{CL}/{name}.wav"]); bg["p"] = p; p.wait()
    bg = {"run": True}; threading.Thread(target=loop, daemon=True).start(); ev(f"BG_START {name}")
def bgstop():
    global bg
    if bg: bg["run"] = False; p = bg.get("p"); p and p.terminate(); bg = None; ev("BG_STOP")
f = open(LOG)
while True:
    line = f.readline()
    if not line: time.sleep(0.05); continue
    m = re.search(r"E2E_MARK \d+ \d+ (CMD|BGSTART|BGSTOP)(?::(\w+))?", line)
    if not m: continue
    kind, name = m.groups()
    if kind == "CMD": threading.Thread(target=play, args=(name,), daemon=True).start()
    elif kind == "BGSTART": bgstart(name)
    else: bgstop()
