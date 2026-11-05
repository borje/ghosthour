"""Static level check: confirms every room, item and the clock can be reached (and that you can get
back), using conservative player physics: walk, fall, ladders, and jumps of up to 2 tiles."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import rooms, tiles

def flags(r, x, y):
    if not (0 <= y < 11 and 0 <= x < 20):
        return 0
    return tiles.TILES[rooms.ROOMS[r]["map"][y][x]][0]

def solid(r, x, y): return flags(r, x, y) & tiles.SOLID
def ladder(r, x, y): return flags(r, x, y) & tiles.LADDER
def standable(r, x, y): return flags(r, x, y) & (tiles.SOLID | tiles.PLATFORM | tiles.LADDER)
def clear(r, x, y): return not solid(r, x, y) and not solid(r, x, y - 1)

def neighbours(state):
    r, x, y = state          # the player's body occupies (x, y) and (x, y-1); feet rest on y+1
    ex = rooms.ROOMS[r]["exits"]
    out = []
    grounded = standable(r, x, y + 1) or ladder(r, x, y)
    if not grounded:
        if y + 1 > 10:
            if "D" in ex: out.append((ex["D"], x, 0))
        else:
            out.append((r, x, y + 1))
        return out
    for dx in (-1, 1):
        nx = x + dx
        if nx < 0:
            if "L" in ex and clear(ex["L"], 19, y): out.append((ex["L"], 19, y))
        elif nx > 19:
            if "R" in ex and clear(ex["R"], 0, y): out.append((ex["R"], 0, y))
        elif clear(r, nx, y):
            out.append((r, nx, y))
    # ladders
    if ladder(r, x, y) or ladder(r, x, y + 1):
        if ladder(r, x, y) and y - 1 >= 0 and (ladder(r, x, y - 1) or not solid(r, x, y - 1)):
            out.append((r, x, y - 1))
        if y == 0 and ladder(r, x, 0) and "U" in ex:
            out.append((ex["U"], x, 10))
        if y + 1 <= 10 and ladder(r, x, y + 1):
            out.append((r, x, y + 1))
        if y == 10 and ladder(r, x, y) and "D" in ex:
            out.append((ex["D"], x, 0))
    if y + 1 == 11 and "D" in ex and ladder(ex["D"], x, 0):
        out.append((ex["D"], x, 0))
    # jumps: up to 2 tiles high and 3 across, needing headroom straight above the take-off
    for h in (1, 2):
        if any(solid(r, x, y - k) or solid(r, x, y - 1 - k) for k in range(1, h + 1)):
            break
        for dx in range(-3, 4):
            nx, ny = x + dx, y - h
            if 0 <= nx < 20 and ny >= 0 and clear(r, nx, ny) and standable(r, nx, ny + 1):
                step = 1 if dx > 0 else -1
                if all(clear(r, cx, ny) for cx in range(x, nx, step or 1)):
                    out.append((r, nx, ny))
    # flat running jumps across a gap
    for dx in (-3, -2, 2, 3):
        nx = x + dx
        if 0 <= nx < 20 and clear(r, nx, y) and standable(r, nx, y + 1):
            step = 1 if dx > 0 else -1
            if all(clear(r, cx, y) and clear(r, cx, y - 1) for cx in range(x, nx, step)):
                out.append((r, nx, y))
    return out

def explore(start):
    seen, todo = {start}, [start]
    while todo:
        for n in neighbours(todo.pop()):
            if n not in seen:
                seen.add(n); todo.append(n)
    return seen

def main():
    bad = 0
    for name, rm in rooms.ROOMS.items():
        assert len(rm["map"]) == 11, name
        for row in rm["map"]:
            assert len(row) == 20, (name, row)
        for side, target in rm["exits"].items():
            assert target in rooms.ROOMS, target
    start = (rooms.START_ROOM, 3, 9)
    seen = explore(start)
    # the clock tile in the hall: stand next to it on the floor
    hall = rooms.HALL_ROOM
    clock_spot = next(s for s in seen if s[0] == hall and flags(*s) & tiles.CLOCK)
    for name, rm in rooms.ROOMS.items():
        if not any(s[0] == name for s in seen):
            print("UNREACHABLE ROOM:", name); bad += 1
        spots_to_check = [rm["item"][1:]] if rm["item"] else []
        spots_to_check += [e[1:] for e in rm["enemies"] if e[0] == rooms.BROOKE]
        for ix, iy in spots_to_check:
            # reachable if we can stand within a jump's reach of it
            spots = [s for s in seen if s[0] == name and abs(s[1] - ix) <= 1 and 0 <= s[2] - iy <= 2]
            if not spots:
                print(f"UNREACHABLE ITEM in {name} at {ix},{iy}"); bad += 1
                continue
            if clock_spot not in explore(spots[0]):
                print(f"NO WAY BACK from item in {name}"); bad += 1
    # also: no stranded rooms - every reachable state can get back to the clock
    back = 0
    for s in list(seen):
        if s[0] != hall and not any(n[0] == hall for n in explore(s)):
            back += 1
            if back < 8: print("  trapped state:", s)
    if back:
        print("TRAPPED STATES:", back); bad += 1
    print("map check:", "OK" if not bad else f"{bad} problem(s)", f"({len(seen)} standing spots)")
    return bad

if __name__ == "__main__":
    sys.exit(1 if main() else 0)
