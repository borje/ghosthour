#!/usr/bin/env python3
"""Records a demo video: a bot plays a debug build from the title screen to Brooke's rescue.
It steps VICE one frame at a time through the remote monitor, captures each frame as a PNG and
the SID output as a WAV, then muxes them into an MP4.
Usage: record_demo.py WORKDIR OUTPUT.mp4 [--no-video | --mux-only | --no-video --full]
--full plays the whole game as a test, with nerve and wax kept topped up."""
import os, re, shutil, socket, subprocess, sys, time, array, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VICE = os.path.join(ROOT, ".tools/root/usr/share/vice")
PORT = 6510
FPS = 985248 / 19656
UP, DOWN, LEFT, RIGHT, FIRE = 1, 2, 4, 8, 16
PROMPT = re.compile(rb"\(C:\$[0-9a-f]{4}\) ")

def labels():
    return {k: int(v, 16) for k, v in re.findall(r"^\s*(\w+)\s*=\s*\$([0-9a-fA-F]+)",
                                                  open(os.path.join(ROOT, "build/labels.txt")).read(), re.M)}

class Mon:
    def __init__(self):
        for _ in range(60):
            try:
                self.s = socket.create_connection(("127.0.0.1", PORT), timeout=30)
                return
            except OSError:
                time.sleep(0.25)
        raise SystemExit("no monitor")

    def read_until(self, pattern):
        data = b""
        while not pattern.search(data):
            chunk = self.s.recv(65536)
            if not chunk:
                raise SystemExit("monitor closed")
            data += chunk
        return data.decode(errors="replace")

    def drain(self):
        self.s.setblocking(False)
        try:
            while self.s.recv(65536):
                pass
        except BlockingIOError:
            pass
        self.s.setblocking(True)
        self.s.settimeout(60)

    def cmd(self, text, expect=PROMPT):
        self.drain()
        self.s.sendall((text + "\n").encode())
        return self.read_until(expect)

    def resume_to(self, addr):
        """Run until the breakpoint at addr stops the machine again."""
        self.drain()
        self.s.sendall(b"x\n")
        self.read_until(re.compile(b"\\(C:\\$%04x\\) " % addr))

class S:  # game state, refreshed every frame
    px = py = room = grounded = on_ladder = rescued = wax = nerve = parts = flash = game_over = 0

def route():
    """A generator yielding the joystick bits for each frame."""
    def hold(j, n):
        for _ in range(n):
            yield j

    def walk_to(x):
        while abs(S.px - x) > 1:
            yield RIGHT if x > S.px else LEFT
        yield 0

    def until_room(r, j):
        while S.room != r:
            yield j

    def jump(d, xstop, target):
        """Jump in direction d, stop steering past xstop, must land at py == target."""
        yield UP | d
        yield d
        yield d
        while not S.grounded:
            passed = (d == LEFT and S.px <= xstop) or (d == RIGHT and S.px >= xstop) or d == 0
            yield 0 if passed else d
        yield 0
        if S.py != target:
            raise RuntimeError(f"jump missed: room {S.room} px {S.px} py {S.py}, wanted {target}")

    yield from hold(0, 220)              # title screen
    yield from hold(FIRE, 8)
    yield from hold(0, 500)              # read the story
    yield from hold(FIRE, 8)
    for i in range(200):                 # wait until the game has really started
        if S.nerve == 5 and S.room == 0:
            break
        yield 0
    else:
        raise RuntimeError("game did not start")
    yield from hold(0, 40)
    yield from until_room(1, RIGHT)      # graveyard
    yield from until_room(2, RIGHT)      # terrace
    yield from walk_to(60)               # Great Hall: the candle box
    yield from hold(0, 15)
    yield from hold(FIRE, 45)            # show the candle flare
    yield from hold(0, 10)
    yield from walk_to(108)              # the ladder
    yield from until_room(4, UP)
    while S.on_ladder:
        yield UP
    yield from walk_to(20)               # Gallery: below the left plank
    yield from jump(0, 0, 107)
    yield from until_room(5, LEFT)       # into the Bedroom
    yield from walk_to(250)
    yield from jump(LEFT, 225, 75)
    yield from walk_to(205)
    yield from jump(LEFT, 165, 59)       # passes the candle
    yield from walk_to(140)
    yield from jump(LEFT, 100, 43)
    yield from walk_to(76)
    yield from jump(LEFT, 56, 27)
    yield from hold(0, 25)               # she asks for the candle
    while not S.rescued:
        yield FIRE
    yield from hold(0, 240)              # thank-you message, then fade out

def full_route():
    """Plays the whole game, on foot: every part, Brooke, then the clock. No teleporting."""
    def hold(j, n):
        for _ in range(n):
            yield j

    def walk_to(x):
        limit = 900
        while abs(S.px - x) > 1:
            limit -= 1
            if limit == 0:
                raise RuntimeError(f"stuck walking to {x}: room {S.room} px {S.px} py {S.py}")
            yield RIGHT if x > S.px else LEFT
        yield 0

    def settle():
        for _ in range(200):
            if S.grounded and not S.on_ladder:
                break
            yield 0

    def until_room(r, j):
        for _ in range(1500):
            if S.room == r:
                return
            yield j
        raise RuntimeError(f"never reached room {r}: room {S.room} px {S.px} py {S.py} ladder {S.on_ladder}")

    def jump(d, xstop, target):
        yield from settle()
        yield UP | d
        yield d
        yield d
        while not S.grounded:
            passed = (d == LEFT and S.px <= xstop) or (d == RIGHT and S.px >= xstop) or d == 0
            yield 0 if passed else d
        yield 0
        if S.py != target:
            raise RuntimeError(f"jump missed: room {S.room} px {S.px} py {S.py}, wanted {target}")

    def climb(j, py=None):
        """Hold j on a ladder, until py if given, otherwise until the ladder ends."""
        yield j
        yield j
        for _ in range(900):
            if (py is not None and S.py == py) or not S.on_ladder:
                return
            yield j
        raise RuntimeError(f"ladder never ended: room {S.room} py {S.py}")

    def expect(mask):
        yield 0
        yield 0
        if S.parts & mask != mask:
            raise RuntimeError(f"part {mask} NOT taken: room {S.room} px {S.px} py {S.py} parts {S.parts}")
        print(f"  got part {mask} (parts now {S.parts}) in room {S.room}", flush=True)

    yield from hold(0, 60)
    yield from hold(FIRE, 8)
    yield from hold(0, 40)
    yield from hold(FIRE, 8)
    for i in range(300):
        if S.nerve == 5 and S.room == 0:
            break
        yield 0
    yield from hold(0, 20)
    yield from until_room(1, RIGHT)
    yield from until_room(2, RIGHT)
    yield from walk_to(108)                  # Great Hall -> Gallery
    yield from until_room(4, UP)
    yield from climb(UP)
    yield from settle()
    # --- Library: the cog
    yield from walk_to(258)                  # below the right-hand plank in the Gallery
    yield from jump(0, 0, 107)
    yield from until_room(6, RIGHT)
    yield from settle()
    yield from walk_to(60)                   # ladder, col 4
    yield from settle()
    yield from climb(UP, 27)                 # up to the first plank
    yield 0
    yield from hold(RIGHT, 4)
    yield from settle()
    yield from walk_to(124)
    yield from jump(RIGHT, 165, 43)
    yield from walk_to(172)
    yield from jump(RIGHT, 225, 27)
    yield from walk_to(262)
    yield from expect(1)
    # --- Lab: the spring. Back along the plank, down to the floor, up the long ladder
    yield from walk_to(214)
    yield from hold(LEFT, 14)
    yield from settle()
    while S.py != 139:                       # drop off whatever we landed on
        yield from walk_to(S.px - 40 if S.px > 80 else 66)
        yield from settle()
    yield from walk_to(60)
    yield from settle()
    yield from until_room(8, UP)
    yield from climb(UP)
    yield from settle()
    yield from walk_to(250)                  # across the Lab floor
    yield from jump(0, 0, 107)
    yield from jump(LEFT, 225, 75)
    yield from jump(0, 0, 43)
    yield from walk_to(262)
    yield from expect(2)
    # --- Crypt: the pendulum. Lab -> Library -> Gallery -> Hall -> outside -> down
    yield from walk_to(205)
    yield from hold(LEFT, 14)
    yield from settle()
    while S.py != 139:
        yield from walk_to(S.px - 40 if S.px > 80 else 66)
        yield from settle()
    yield from walk_to(60)
    yield from settle()
    yield from until_room(6, DOWN)
    yield from climb(DOWN)
    yield from settle()
    yield from walk_to(8)
    yield from jump(0, 0, 107)
    yield from until_room(4, LEFT)
    yield from settle()
    yield from walk_to(108)
    yield from settle()
    yield from until_room(2, DOWN)
    yield from climb(DOWN)
    yield from settle()
    yield from until_room(1, LEFT)
    yield from until_room(0, LEFT)
    yield from walk_to(28)
    yield from settle()
    yield from until_room(12, DOWN)
    yield from climb(DOWN)
    yield from settle()
    yield from walk_to(92)
    yield from jump(RIGHT, 132, 59)
    yield from walk_to(150)
    yield from jump(RIGHT, 205, 43)
    yield from walk_to(248)
    yield from expect(4)
    # --- home via the Tunnel and Cellar
    yield from walk_to(205)                  # off the plank: its right end is a wall
    yield from hold(LEFT, 14)
    yield from settle()
    yield from until_room(11, RIGHT)
    yield from settle()
    yield from until_room(9, RIGHT)
    yield from settle()
    yield from walk_to(132)
    yield from jump(0, 0, 107)
    yield from jump(RIGHT, 178, 75)
    yield from walk_to(220)
    yield from until_room(2, UP)
    yield from climb(UP)
    yield from settle()
    # --- Bedroom: Brooke and the key
    yield from walk_to(108)
    yield from until_room(4, UP)
    yield from climb(UP)
    yield from settle()
    yield from walk_to(20)
    yield from jump(0, 0, 107)
    yield from until_room(5, LEFT)
    yield from walk_to(250)
    yield from jump(LEFT, 225, 75)
    yield from walk_to(205)
    yield from jump(LEFT, 165, 59)
    yield from walk_to(140)
    yield from jump(LEFT, 100, 43)
    yield from walk_to(76)
    yield from jump(LEFT, 56, 27)
    for _ in range(300):
        if S.rescued:
            break
        yield FIRE
    yield from expect(8)
    # --- back to the clock
    yield from until_room(4, RIGHT)
    yield from settle()
    yield from walk_to(108)
    yield from settle()
    yield from until_room(2, DOWN)
    yield from climb(DOWN)
    yield from settle()
    for _ in range(300):
        if S.game_over:
            print("  CLOCK REACHED, game_over =", S.game_over, flush=True)
            return
        yield RIGHT
    raise RuntimeError(f"never reached the clock: px {S.px} py {S.py} parts {S.parts}")

def main():
    work, out = sys.argv[1], sys.argv[2]
    if "--mux-only" in sys.argv:
        return mux(work, out, len(os.listdir(os.path.join(work, "frames"))))
    video = "--no-video" not in sys.argv
    frames = os.path.join(work, "frames")
    shutil.rmtree(frames, ignore_errors=True)
    os.makedirs(frames)
    wav_raw = os.path.join(work, "raw.wav")
    lab = labels()
    env = dict(os.environ, LD_LIBRARY_PATH=os.path.join(ROOT, ".tools/root/usr/lib/x86_64-linux-gnu"))
    p = subprocess.Popen([os.path.join(ROOT, ".tools/root/usr/bin/x64sc"), "-default",
                          "-directory", f"{VICE}/C64:{VICE}/DRIVES:{VICE}", "-sound", "-sounddev", "wav",
                          "-soundarg", wav_raw, "+confirmonexit", "-remotemonitor",
                          "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}", "-autostartprgmode", "1",
                          os.path.join(ROOT, "build/ghosthour_debug.prg")],
                         env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    m = Mon()
    hook = lab["read_input"]
    m.cmd(f"break exec {hook:04x}", re.compile(b"BREAK|Stop|STOP|exec", re.I))
    time.sleep(0.2)
    full = "--full" in sys.argv
    bot = full_route() if full else route()
    n, flashes, jumps, t0 = 0, [], [], time.time()
    prev_flash = 0
    try:
        m.resume_to(hook)
        while True:
            r = m.cmd("m 0020 005f", re.compile(rb">C:[\s\S]*\(C:\$[0-9a-f]{4}\) "))
            vals = []
            for line in re.findall(r">C:[0-9a-f]{4}\s+((?:[0-9a-f]{2}\s+)+)", r):
                vals += [int(x, 16) for x in line.split()]
            g = lambda name: vals[lab[name] - 0x20]
            hi = vals[lab["px"] + 1 - 0x20]
            S.px = (hi << 8 | g("px")) - (65536 if hi >= 128 else 0)
            S.py, S.room, S.grounded, S.on_ladder = g("py"), g("room"), g("grounded"), g("on_ladder")
            S.rescued, S.wax, S.nerve, S.parts, S.flash = g("rescued"), g("wax"), g("nerve"), g("parts"), g("flash")
            S.game_over = g("game_over")
            if S.flash and not prev_flash:
                flashes.append(n)
            prev_flash = S.flash
            try:
                j = next(bot)
            except StopIteration:
                break
            m.cmd(f">C:0002 {j:02x}")
            if full:                             # testing the route, not the difficulty
                m.cmd(">C:002d 05")
                m.cmd(">C:002e 40")
            if video:
                m.cmd(f'screenshot "{os.path.abspath(frames)}/{n:05d}.png" 2')
            n += 1
            if n % 500 == 0:
                print(f"frame {n}: room {S.room} px {S.px} py {S.py} wax {S.wax} nerve {S.nerve} ({time.time() - t0:.0f}s)", flush=True)
            m.resume_to(hook)
    finally:
        print(f"stopped at frame {n}: room {S.room} px {S.px} py {S.py} rescued {S.rescued} parts {S.parts} wax {S.wax} nerve {S.nerve}")
        try:
            m.s.sendall(b"quit\n")
        except OSError:
            pass
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.kill()
    print("flash frames:", flashes)
    if video:
        mux(work, out, n)

def mux(work, out, n):
    # The WAV's length field may be unfinished, so read the raw samples. VICE only opens the WAV
    # when the SID is first touched, right as the title appears, so audio and frame 0 line up.
    raw = array.array("h")
    data = open(os.path.join(work, "raw.wav"), "rb").read()[44:]
    raw.frombytes(data[:len(data) // 2 * 2])
    rate = 48000
    print(f"audio {len(raw) / rate:.2f}s, video {n / FPS:.2f}s")
    clip = raw[:int(n / FPS * rate)]
    wav_out = os.path.join(work, "audio.wav")
    frames = os.path.join(work, "frames")
    with wave.open(wav_out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(clip.tobytes())
    import imageio_ffmpeg
    subprocess.check_call([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error",
                           "-framerate", f"{FPS:.5f}", "-i", os.path.join(frames, "%05d.png"), "-i", wav_out,
                           "-vf", "scale=iw*3:ih*3:flags=neighbor,format=yuv420p",
                           "-c:v", "libx264", "-crf", "16", "-preset", "medium",
                           "-af", "volume=14dB", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out])
    print("wrote", out)

main()
