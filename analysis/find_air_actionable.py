"""Find the byte that says "this character can act again" IN THE AIR.

The ground test is $05 == 0 and $06 == 0. Neither ever reaches zero in the air,
so Wait = Auto has never worked there and air chains have to be timed by hand.

WHAT MAKES THIS FINDABLE.

airChainProbe.lua records one row per TICK for the length of a sequence run,
and the sequence used for the recordings has waits that are the FASTEST that
work - confirmed by the user for both gaps. So the tick an attack's input goes
in is the first tick it could have gone in, and that is a boundary the answer
has to line up with exactly.

Two boundaries per run, five runs. A byte that is "ready" one tick early at any
of the ten fails, and so does a byte that is still "not ready" at the boundary.
That is a strong enough filter to run blind.

Usage:  python find_air_actionable.py [dir]
"""

import glob
import io
import json
import os
import sys

SPAN = 0x400


def load(path):
    d = json.load(io.open(path, encoding="utf-8"))
    cur = [0] * SPAN
    rows = []
    for t in d["ticks"]:
        dd = t["d"]
        for i in range(0, len(dd), 2):
            cur[dd[i]] = dd[i + 1]
        rows.append((t["lg"], t["inp"], list(cur)))
    return d, rows


def boundaries(rows):
    """The ticks an attack's input went in, as row indices.

    Buttons only: a lever-only entry is a dash tap or a jump, not a move whose
    timing the user tuned. 0x4002 is forward+HK, so the low byte is masked off
    rather than tested for zero.
    """
    out = []
    for i, (lg, inp, _) in enumerate(rows):
        if (inp & 0xFF00) != 0 or (inp & 0x00F0) != 0:
            out.append(i)
    return out


def main():
    where = sys.argv[1] if len(sys.argv) > 1 else "."
    files = sorted(glob.glob(os.path.join(where, "air_0*.json")))
    if not files:
        print("no air_0*.json in " + where)
        return

    runs = []
    for fn in files:
        d, rows = load(fn)
        b = boundaries(rows)
        # The attacks are the last three button entries: HK, LK, LP. Only the
        # gaps the user tuned to the frame are usable, so HK is the reference
        # and LK/LP are the boundaries.
        runs.append((os.path.basename(fn), rows, b))
        print("%s  %d ticks  button ticks at rows %s"
              % (os.path.basename(fn), len(rows), b))

    # THE RECORDED TICK IS NOT ALWAYS THE EARLIEST ONE.
    #
    # Measured by walking the waits down until the move stopped coming out:
    # LK's floor is 25, which is what the recording used, but LP's floor is 24
    # and the recording used 25. So LP's input sits one tick LATE and the
    # boundary to test against is one tick before it.
    #
    # That the two floors differ at all is itself the finding: a single fixed
    # recovery would give the same number twice.
    EARLY = {1: 0, 2: 1}      # index among the attacks -> ticks the input was late
    # READ THE TICK BEFORE THE INPUT, NOT THE TICK OF IT.
    #
    # The first pass tested the boundary tick itself and came back with the
    # input word and its mirrors - $122, $124, $126, $12A, $1AC, $396 all read
    # 16 there because 16 is the LK bit we had just injected. That is the
    # causality backwards: they changed BECAUSE of the press.
    #
    # The character has to be ready before the press can be taken, so the state
    # is read at cut-1 and must already differ from everything since the
    # previous attack. Nothing we do can have touched it yet.
    print("\n--- 候補 ---")
    hits = []
    for off in range(SPAN):
        ok = True
        detail = []
        for name, rows, b in runs:
            if len(b) < 3:
                ok = False
                break
            for n, k in enumerate((len(b) - 2, len(b) - 1), start=1):   # LK, LP
                # The earliest tick the move could have gone in, then one back
                # from that: the state has to already say "ready" before the
                # press is read, and nothing we injected can have touched it.
                cut = b[k] - EARLY[n] - 1
                prev = b[k - 1]
                at = rows[cut][2][off]
                run_up = [rows[i][2][off] for i in range(prev + 2, cut)]
                if not run_up or at in run_up:
                    ok = False
                    break
                detail.append((name, cut, at, run_up[-6:]))
            if not ok:
                break
        if ok:
            hits.append((off, detail))

    if not hits:
        print("  条件を満たすバイトなし")
    for off, detail in hits:
        name, cut, at, tail = detail[0]
        print("  $0x%03X  境界-1 の値=%3d  その前6ティック=%s" % (off, at, tail))
    print("\n%d 候補" % len(hits))

    # For anything that survives, show both boundaries side by side. A real
    # "ready" byte reaches the same value at both; a coordinate or a counter
    # that happens to be passing through will not.
    for off, _ in hits:
        print("\n  $0x%03X" % off)
        name, rows, b = runs[0]
        for k in (len(b) - 2, len(b) - 1):
            cut = b[k]
            win = [rows[i][2][off] for i in range(cut - 8, min(cut + 3, len(rows)))]
            print("    境界 row %-3d  -8..+2 = %s" % (cut, win))


if __name__ == "__main__":
    main()
