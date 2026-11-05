#!/usr/bin/env python3
"""Drive the game in VICE through its remote monitor and take screenshots.
Usage: shot.py OUTDIR SCRIPT    (needs a DEBUG build: make debug)
Script is a list of steps separated by ';':
   wait N          run N frames (by wall clock in warp-free mode)
   joy BITS        hold joystick bits (1 up,2 down,4 left,8 right,16 fire; 0 = none)
   room N          warp to room N
   poke ADDR VAL   (hex) write memory
   shot NAME       screenshot OUTDIR/NAME.png
   peek SYMBOL     print a byte
"""
import os, re, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VICE = os.path.join(ROOT, ".tools/root/usr/share/vice")
PORT = 6510

def labels():
    return {k: int(v, 16) for k, v in re.findall(r"^\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)",
                                                  open(os.path.join(ROOT, "build/labels.txt")).read(), re.M)}

class Monitor:
    """One persistent connection; sending anything drops VICE into its monitor, 'x' resumes."""
    def __init__(self):
        self.s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
        self.s.settimeout(0.5)

    def _read(self):
        data = b""
        try:
            while True:
                chunk = self.s.recv(4096)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            pass
        return data

    def cmd(self, text):
        self.s.sendall((text + "\n").encode())
        data = self._read()
        self.s.sendall(b"x\n")
        self._read()
        return data.decode(errors="replace")

def main():
    out, script = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = os.path.join(ROOT, ".tools/root/usr/lib/x86_64-linux-gnu")
    args = [os.path.join(ROOT, ".tools/root/usr/bin/x64sc"), "-default",
            "-directory", f"{VICE}/C64:{VICE}/DRIVES:{VICE}", "-sounddev", "dummy", "+confirmonexit",
            "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
            "-autostartprgmode", "1", os.path.join(ROOT, "build/ghosthour_debug.prg")]
    p = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(6)
    m = Monitor()
    lab = labels()
    try:
        for step in script.split(";"):
            w = step.split()
            if not w:
                continue
            if w[0] == "wait":
                time.sleep(int(w[1]) / 50.0)
            elif w[0] == "joy":
                m.cmd(f">C:0002 {int(w[1]):02x}")
            elif w[0] == "room":
                m.cmd(f">C:0003 {int(w[1]) + 1:02x}")
            elif w[0] == "poke":
                m.cmd(f">C:{w[1]} {chr(32).join(w[2:])}")
            elif w[0] == "peek":
                addr = lab[w[1]] if w[1] in lab else int(w[1], 16)
                r = m.cmd(f"m {addr:04x} {addr + int(w[2] if len(w) > 2 else 1) - 1:04x}")
                print(w[1], re.findall(r">C:[0-9a-f]{4}\s+((?:[0-9a-f]{2}\s+)+)", r))
            elif w[0] == "shot":
                path = os.path.abspath(os.path.join(out, w[1] + ".png"))
                m.cmd(f'screenshot "{path}" 2')
                print("shot", path)
    finally:
        p.terminate()
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.kill()

main()
