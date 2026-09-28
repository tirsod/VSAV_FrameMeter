"""Read airGuardLog.lua's recordings (scripts/reversal_logs/airg_s*.json).

Each file is one air-blocked chain. Rows are ticks; the first row carries both
player objects in full as dwords (P1 0xFF8400 then P2 0xFF8800, 0x400 bytes
each) and every later row only the dwords that changed.

    python air_guard_report.py                 # one line per air guard
    python air_guard_report.py outcomes        # attack start vs result
    python air_guard_report.py table           # the hit stop table (0x0195A2)
    python air_guard_report.py dump 9 5 60     # airg_s09, rows 5..60

Tick 0 below is the FIRST TICK THE DEFENDER CAN ACT: the one after 0x025286
put it back in the jump state (T0 + 1). Measured 2026-09-26 on 120 air
guards: a press before it produces nothing, held or not.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOG_DIR = os.path.join(HERE, "..", "scripts", "reversal_logs")
BTN = 0x77   # the six attack buttons, as timers.lua's and77 masks $126


def load(path):
    with open(path, encoding="utf-8") as fh:
        d = json.load(fh)
    cur = list(d["rows"][0]["base"])
    frames = []
    for r in d["rows"]:
        if "d" in r:
            dd = r["d"]
            for k in range(0, len(dd), 2):
                cur[dd[k] - 1] = dd[k + 1]
        b = bytearray()
        for v in cur:
            b += int(v).to_bytes(4, "big")
        frames.append((r["lg"], bytes(b[:0x400]), bytes(b[0x400:])))
    return d, frames


def files():
    return sorted(glob.glob(os.path.join(LOG_DIR, "airg_s*.json")))


def state(o):
    return "%02X%02X%02X%02X" % (o[4], o[5], o[6], o[7])


def guards(d, fr):
    """One entry per air guard the defender made, with what followed it.

    Every tick count is relative to tick 0, the first tick the defender can
    act (see the module docstring)."""
    out = []
    dp = d["def"]
    me = (lambda i: fr[i][1]) if dp == 1 else (lambda i: fr[i][2])
    foe = (lambda i: fr[i][2]) if dp == 1 else (lambda i: fr[i][1])
    n = len(fr)
    for e in [x["i"] - 1 for x in d["events"] if x["p"] == dp]:
        # T0: the tick 0x025286 put the defender back in the jump state.
        t0 = None
        for i in range(e + 1, n):
            o = me(i)
            if o[5] == 0x00 and o[6] == 0x06:
                t0 = i
                break
            if o[5] != 0x02:
                break
        if t0 is None:
            out.append({"row": e + 1, "t0": None})
            continue
        z = t0 + 1
        # What next struck the defender: a guard, a hit, or it landed.
        nxt, kind = None, None
        for i in range(z, n):
            o = me(i)
            if o[5] == 0x02 and me(i - 1)[5] != 0x02:
                nxt, kind = i, ("guard" if o[0x54] == 0xFF else "hit")
                break
            if o[0x38] == 0 and me(i - 1)[0x38] != 0:
                nxt, kind = i, "land"
                break
        end = nxt if nxt is not None else n
        presses = [(i - z, me(i)[0x126] & BTN)
                   for i in range(e, end) if me(i)[0x126] & BTN]
        # The defender's own attack: $07 leaves 02 while still in the jump.
        atk = None
        for i in range(z, end):
            o = me(i)
            if o[5] == 0x00 and o[6] == 0x06 and o[7] != 0x02:
                atk = i - z
                break
        # The defender striking the attacker before it was struck itself.
        struck = None
        for i in range(z, min(end + 1, n)):
            f = foe(i)
            if f[5] == 0x02 and foe(i - 1)[5] != 0x02:
                struck = (i - z, "guard" if f[0x54] == 0xFF else "hit")
                break
        foe_free = next((i - z for i in range(e + 1, n) if foe(i)[0x5C] == 0), None)
        out.append({"row": e + 1, "t0": t0, "from_guard": z - e,
                    "hs": me(e)[0x5C], "foe_hs": foe(e)[0x5C], "foe_free": foe_free,
                    "next": None if nxt is None else nxt - z, "kind": kind,
                    "presses": presses, "atk": atk, "struck": struck})
    return out


def result(g):
    if g["atk"] is None:
        return None
    s = g["struck"]
    if s is None:
        return "lose" if g["kind"] == "hit" else "whiff"
    if g["kind"] == "hit" and s[0] == g["next"]:
        return "trade"
    return "win"


def summary():
    for p in files():
        d, fr = load(p)
        for g in guards(d, fr):
            tag = os.path.basename(p)[5:8]
            if g["t0"] is None:
                print("%s row %3d  (never back in the jump state)" % (tag, g["row"]))
                continue
            print("%s row %3d  guard->0 %d  hs %d/%d  foe_free %+d  next %s %-5s  press %-22s atk %s  %s" % (
                tag, g["row"], g["from_guard"], g["hs"], g["foe_hs"], g["foe_free"],
                ("%+d" % g["next"]) if g["next"] is not None else "-", g["kind"] or "",
                " ".join("%+d:%02X" % x for x in g["presses"]) or "-",
                ("%+d" % g["atk"]) if g["atk"] is not None else "-", result(g) or ""))


def outcomes():
    print(" next  start btn reach result  file row  pressed-before-0")
    rows = []
    for p in files():
        d, fr = load(p)
        for g in guards(d, fr):
            if g["t0"] is None or g["atk"] is None:
                continue
            btn = next((b for (t, b) in g["presses"] if t == g["atk"]), None)
            reach = (g["struck"][0] - g["atk"]) if g["struck"] else None
            early = any(t < 0 for (t, _) in g["presses"])
            rows.append((g["next"] if g["kind"] == "hit" else None, g["atk"], btn, reach,
                         result(g), os.path.basename(p)[5:8], g["row"], early))
    for r in sorted(rows, key=lambda r: (str(r[0]), r[1])):
        print("%5s  %+4d   %s   %s    %-6s %s %3d  %s" % (
            "-" if r[0] is None else "%+d" % r[0], r[1],
            "%02X" % r[2] if r[2] is not None else "--",
            "%d" % r[3] if r[3] is not None else "-", r[4], r[5], r[6], "yes" if r[7] else ""))
    early_only = []
    for p in files():
        d, fr = load(p)
        for g in guards(d, fr):
            if g["t0"] is not None and g["atk"] is None and any(t < 0 for (t, _) in g["presses"]):
                early_only.append((os.path.basename(p)[5:8], g["row"], g["kind"]))
    print("pressed only before 0, nothing came out:", early_only)


def table():
    d = json.load(open(files()[0], encoding="utf-8"))
    t = d["hitstop_table"]
    print("idx  hit att/def   guard att/def")
    for i in range(len(t) // 4):
        q = t[i * 4:i * 4 + 4]
        print("%02X   %3d %3d        %3d %3d" % (i, q[0], q[1], q[2], q[3]))


def dump(slot, lo, hi):
    d, fr = load(os.path.join(LOG_DIR, "airg_s%02d.json" % slot))
    ev = {e["i"]: e["p"] for e in d["events"]}
    print("airg_s%02d seq %d def P%d  cid %02X/%02X" % (slot, d["seq"], d["def"], d["cid1"], d["cid2"]))
    print(" row  lg | P1 state 140 38 5C 54 0A 126 122 12B | P2 state 38 5C 54 0A 122 126")
    for i in range(lo - 1, min(hi, len(fr))):
        lg, p1, p2 = fr[i]
        print("%s%3d %3d | %s  %02X %02X %02X %02X %02X  %02X  %02X  %02X | %s %02X %02X %02X %02X  %02X  %02X" % (
            "G" if (i + 1) in ev else " ", i + 1, lg,
            state(p1), p1[0x140], p1[0x38], p1[0x5C], p1[0x54], p1[0x0A], p1[0x126], p1[0x122], p1[0x12B],
            state(p2), p2[0x38], p2[0x5C], p2[0x54], p2[0x0A], p2[0x122], p2[0x126]))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["dump"]:
        dump(int(a[1]), int(a[2]), int(a[3]))
    elif a[:1] == ["outcomes"]:
        outcomes()
    elif a[:1] == ["table"]:
        table()
    else:
        summary()
