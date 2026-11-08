#!/usr/bin/env python3
"""Drive the NES build in FCEUX (headless) with scripted input; take screenshots, read memory.
Usage: play.py OUTDIR SCRIPT [--window]
Script steps separated by ';':
   wait N          run N frames, holding the current buttons
   hold BUTTONS    hold these from now on: any of up down left right A B start select, or none
   shot NAME       screenshot OUTDIR/NAME.png
   peek SYMBOL [N] print N bytes (a label from build/labels.txt, or a hex address)
   poke SYMBOL V.. write bytes (decimal, or 0x..)
   room N          jump to room N (C64 order: 0 graveyard ... 12 crypt), keeping the position
Every step is counted in emulated frames, so runs are repeatable.
"""
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(ROOT, ".tools")


def labels():
    out = {}
    for m in re.finditer(r"^al ([0-9A-F]+) \.(\w+)", open(os.path.join(ROOT, "build/labels.txt")).read(), re.M):
        out[m.group(2)] = int(m.group(1), 16)
    return out


def main():
    out, script = os.path.abspath(sys.argv[1]), sys.argv[2]
    window = "--window" in sys.argv
    os.makedirs(out, exist_ok=True)
    lab = labels()
    done = os.path.join(out, "_done")
    log = os.path.join(out, "_peek.txt")
    for f in (done, log):
        if os.path.exists(f):
            os.remove(f)
    lua = ['local held = {}', f'local log = io.open("{log}", "w")',
           'local function run(n) for i = 1, n do joypad.set(1, held); emu.frameadvance() end end']
    for step in script.split(";"):
        w = step.split()
        if not w:
            continue
        if w[0] == "wait":
            lua.append(f"run({int(w[1])})")
        elif w[0] == "hold":
            keys = [k for k in w[1:] if k != "none"]
            lua.append("held = {" + ", ".join(f"{k} = true" for k in keys) + "}")
        elif w[0] == "shot":
            path = os.path.join(out, w[1] + ".png")
            if os.path.exists(path):
                os.remove(path)
            lua.append(f'gui.savescreenshotas("{path}"); run(2)')
        elif w[0] == "poke":
            addr = lab[w[1]] if w[1] in lab else int(w[1], 16)
            for i, v in enumerate(w[2:]):
                lua.append(f"memory.writebyte({addr + i}, {int(v, 0)})")
        elif w[0] == "room":
            lua.append(f"memory.writebyte({lab['dbg_room']}, {int(w[1]) + 1}); run(1)")
        elif w[0] == "peek":
            addr = lab[w[1]] if w[1] in lab else int(w[1], 16)
            n = int(w[2]) if len(w) > 2 else 1
            lua.append(f'log:write("{w[1]}"); for i = 0, {n - 1} do log:write(" " .. memory.readbyte({addr} + i)) end; log:write("\\n")')
    lua += ['log:close()', f'io.open("{done}", "w"):close()', 'while true do emu.frameadvance() end']
    script_path = os.path.join(out, "_script.lua")
    open(script_path, "w").write("\n".join(lua) + "\n")

    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = os.path.join(T, "root/usr/lib/x86_64-linux-gnu")
    env["QT_PLUGIN_PATH"] = os.path.join(T, "root/usr/lib/x86_64-linux-gnu/qt5/plugins")
    env["FCEUX_HOME"] = os.path.join(T, "fceux-home")
    if not window:
        env["QT_QPA_PLATFORM"] = "offscreen"
    args = [os.path.join(T, "root/usr/games/fceux"), "--no-config", "1", "--sound", "0",
            "--loadlua", script_path, os.path.join(ROOT, "build/ghosthour.nes")]
    p = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        t0 = time.time()
        while not os.path.exists(done):
            if p.poll() is not None:
                sys.exit("fceux exited early")
            if time.time() - t0 > 120:
                sys.exit("timed out")
            time.sleep(0.2)
    finally:
        p.kill()            # FCEUX ignores SIGTERM
        p.wait()
    if os.path.exists(log):
        sys.stdout.write(open(log).read())


main()
