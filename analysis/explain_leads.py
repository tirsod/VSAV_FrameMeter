"""
Work out what determines each recovery's LEAD, and say so.

The lead is the distance, in game ticks, from the point the script arms a
reversal to the tick the character becomes actionable. Getting it wrong is the
only remaining cause of failure: too short and the motion has not finished
going in, too long and the second direction is held past the command
recogniser's 14-19 tick step timeout and the motion is gone.

Two of the five recovery variants are solved and this script shows why:

    hit stun (short)   $59 -> 14 / 19 / 23      three buttons, three durations
    air recovery       lead = 0.094 * Y + 31.6  how far there is left to fall

$59 is not a guess. 0x075E2C copies it out of the attack's own row in the
table at 0x0764EA, so for a ground normal it IS the light/medium/heavy
distinction, and for a special it is whatever that move's row says.

The long hit-stun class ($07 reaching 0x0C) is not solved. Its leads came out
bimodal - 9..13 and 19, nothing between - on 21 spans, and no byte in the
object predicted it. This script re-runs that question against every candidate
each time, so the answer appears as soon as a batch contains it: hit count,
the attacker's move, the attack index, and an exhaustive byte sweep.

Usage:  python explain_leads.py [log_dir]
"""
import glob
import json
import os
import statistics
import sys
import collections

from classify_reversals import reconstruct, get_byte

# A special starting within this many ticks of the actionable tick counts as a
# reversal.
#
# This was 20 for one round, on the theory that $06 turning 0x0E marks the
# ACTIVE part of the move and a throw's startup would push that out - Bishamon's
# command throw measured a tight 12-13. The user, watching the screen, says
# those are not reversals: the move comes out, but late. 20 was counting misses
# as hits.
#
# 4 is deliberately tight. If a move genuinely has slow startup it will show up
# as a cluster in the reported delay rather than being silently credited.
REVERSAL_WINDOW = 4


def canonical(ticks):
    """Drop ticks the emulator re-ran. See VSAV_ENGINE.md 8.6.9."""
    out = []
    for t in ticks:
        while out:
            d = (t['g'] - out[-1]['g']) % 256
            if d == 1:
                break
            back = (out[-1]['g'] - t['g']) % 256
            if 0 <= back <= 8:
                out.pop()
            else:
                break
        out.append(t)
    return out


def region_label(addr):
    """Name an address by which object it belongs to."""
    if 0xFF8800 <= addr < 0xFF8C00:
        return "P2 $%03X" % (addr - 0xFF8800)
    if 0xFF8400 <= addr < 0xFF8800:
        return "P1 $%03X" % (addr - 0xFF8400)
    if 0xFF8000 <= addr < 0xFF8400:
        return "global $%03X" % (addr - 0xFF8000)
    return "proj +0x%03X" % (addr - 0xFF9400)


def gb(frame, addr):
    try:
        return get_byte(frame, addr)
    except Exception:
        return None


def _delay(can, i):
    """Ticks from the actionable tick until a special actually starts.

    The old success test read `$06 in (0x0E, 0x10, 0x12)` at exactly i - one
    tick after free - and a batch where Bishamon's command throw came out 17
    times scored 0/18 under it. The move was there, 13 ticks later:

        free    00/00/00
        +1..12  00/04/02      standing
        +13     00/0E/02      the special starts
        +19     00/0E/06 -> 0E/08 -> 0E/0A

    So the state test was right and the WINDOW was wrong. Returning the delay
    instead of a boolean also separates "came out as a reversal" from "came out
    late", which one tick could never distinguish.
    """
    for k in range(i, min(i + 40, len(can))):
        if can[k]['b'] in (0x0E, 0x10, 0x12):
            return k - i
    return None


def spans(paths):
    """Every recovery, with its lead and the state at the arming point."""
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        can = canonical(data.get('ticks') or [])
        frames = reconstruct(data['rows'])
        for i in range(1, len(can)):
            if not (can[i - 1]['a'] == 0x02 and can[i]['a'] == 0):
                continue
            start = i - 1
            while start > 0 and can[start - 1]['a'] != 0:
                start -= 1
            prev = can[i - 1]
            recovery = prev.get('r')
            long0c = any(can[k]['c'] == 0x0C for k in range(start, i))
            # Where each variant arms.
            mark = None
            if recovery == 0x0A:
                # A knockdown arms on its own clock, not on the $06 edge -
                # measuring it from the edge gives leads of 90-150 that mean
                # nothing. KD_ARM_AT is 23.
                for k in range(i - 1, 0, -1):
                    if can[k]['a'] != 0x02:
                        break
                    if can[k]['k'] == 23:
                        mark = k
                        break
            elif long0c:
                for k in range(start, i):
                    if can[k]['c'] == 0x0C:
                        mark = k
                        break
            else:
                for k in range(i - 1, 0, -1):
                    if can[k]['a'] != 0x02:
                        break
                    if can[k]['b'] == 0x02 and can[k - 1]['b'] == 0x00:
                        mark = k
                        break
            if mark is None:
                continue
            # WAKE-UP VARIANT COMES FROM $07 AT THE START, NOT FROM $1a7.
            #
            # This used to split on prev['k'] > 40, which is Morrigan's number:
            # her wake-up ends at $1a7 == 27 and her roll at 47. Bishamon ends
            # at 23 and 30, so BOTH of his variants fell under 40 and his
            # rolling wake-ups were being counted as ordinary ones - which made
            # a report of "Bishamon 12/28 -> 22/39" hide that the roll had not
            # moved at all.
            #
            # $07 at the tick $1a7 first reads 1 separates them cleanly for
            # every character measured: 0x02 ordinary, 0x04 rolling
            # (section 8.6.106).
            kd_kind = 'knockdown'
            if recovery == 0x0A:
                start07 = None
                for k in range(i - 1, max(0, i - 80), -1):
                    if can[k].get('k') == 1:
                        start07 = can[k].get('c')
                        break
                if start07 == 0x04:
                    kd_kind = 'knockdown-roll'
                elif start07 is None:
                    # $1a7 == 1 outside the window; fall back on the old test
                    kd_kind = ('knockdown-roll' if prev['k'] > 40
                               else 'knockdown-?')
            kind = ('air' if recovery == 0x04 else
                    'throw' if recovery == 0x0E else
                    kd_kind if recovery == 0x0A else
                    'hitstun-long' if long0c else 'hitstun-short')
            yield {
                'kind': kind,
                'lead': i - mark,
                'tick': can[mark],
                'frame': frames.get(can[mark]['f']),
                'hits': can[i - 1].get('hc'),
                # SUCCESS = A SPECIAL CAME OUT, read from the move id.
                #
                # The old test was `$06 in (0x0E, 0x10, 0x12)`, which a throw
                # never satisfies. A batch where Bishamon's command throw came
                # out 17 times out of 18 scored 0/18 under it. $106 (0xFF8906)
                # is the game's own special-move id - charMoves.lua names the
                # values per character - so it says both whether a special is
                # out and which one.
                #
                # Falls back to the old test on recordings taken before v110,
                # which do not carry 'mv'.
                # REVERSAL_WINDOW ticks, not one. A special that starts
                # well after the character became actionable is a move, but it
                # is not a reversal - keep the delay so the two can be told
                # apart instead of collapsing them into one boolean.
                # `x or 99` treats a delay of ZERO as "no move", because 0 is
                # falsy in Python - and zero is the BEST possible result, a
                # special starting on the very tick the character becomes
                # actionable. A batch that was working scored 0/97 under it.
                'moved': (_delay(can, i) is not None
                          and _delay(can, i) <= REVERSAL_WINDOW),
                'delay': _delay(can, i),
                'move_id': can[i].get('mv'),
                # The ticks the motion was actually going in over, for the
                # pacing check.
                'window': can[max(0, i - 16):i],
            }


def pacing(name, rows):
    """Was the emulator running smoothly through each attempt?

    The motion is delivered one entry per Lua frame callback, so the quantity
    that matters is how many GAME TICKS a callback covered while the motion was
    going in. Steady is about 1 with run-ahead off and about 4 with it on; a
    callback that covers more than that stretches the motion and holds the
    second direction longer, which is how these failures look.

    Measured per attempt from the trace itself - the span of ticks that share a
    displayed-frame number - rather than from a session-wide average, because a
    single hitch during one attempt is invisible in a session mean.
    """
    buckets = collections.defaultdict(collections.Counter)
    for r in rows:
        seq = r.get('window') or []
        if not seq:
            continue
        per = collections.Counter(t['f'] for t in seq)
        worst = max(per.values()) if per else 0
        buckets[worst]['REV' if r['moved'] else 'no'] += 1
    if not buckets:
        return
    print("   worst ticks-in-one-frame during delivery x outcome:")
    for k in sorted(buckets):
        b = buckets[k]
        print("      %2d ticks: %3d reversal / %3d nothing" % (k, b['REV'], b['no']))


def describe(name, rows):
    """Report what predicts the lead for one variant."""
    leads = [r['lead'] for r in rows]
    ok = sum(1 for r in rows if r['moved'])
    print("\n=== %s ===  n=%d   reversal %d/%d" % (name, len(rows), ok, len(rows)))
    hist = collections.Counter(leads)
    print("   lead: " + ", ".join("%d:%d" % (k, hist[k]) for k in sorted(hist)))
    if len(hist) == 1:
        print("   constant - nothing to explain")
        return
    # Gaps of 3 or more with values on both sides mean a single constant, or a
    # mean, describes nothing that actually occurs.
    keys = sorted(hist)
    gaps = [(a, b) for a, b in zip(keys, keys[1:]) if b - a >= 3]
    if gaps:
        print("   NOT a single cluster - empty range(s) " +
              ", ".join("%d..%d" % (a + 1, b - 1) for a, b in gaps))

    pacing(name, rows)

    # 1. the fields the trace carries directly
    for label, key in (('hit count', 'hits'), ('$a attack index', 'ad'),
                       ('$59 stun class', 'ac'), ("attacker $382", 'pm'),
                       ("attacker $a", 'pa')):
        g = collections.defaultdict(list)
        miss = False
        for r in rows:
            v = r['hits'] if key == 'hits' else r['tick'].get(key)
            if v is None:
                miss = True
                break
            g[v].append(r['lead'])
        if miss or len(g) < 2:
            continue
        worst = max(max(v) - min(v) for v in g.values())
        verdict = "EXACT" if worst == 0 else ("within %d" % worst if worst <= 2 else None)
        if verdict:
            print("   %s: %s -> %s" % (label, verdict,
                  {k: (min(v) if min(v) == max(v) else (min(v), max(v)))
                   for k, v in sorted(g.items())}))

    # 2. a continuous fit against position, the way air recovery resolved
    for label, addr in (('Y ($14)', 0xFF8814), ('X ($10)', 0xFF8810)):
        pts = []
        for r in rows:
            if r['frame'] is None:
                continue
            hi, lo = gb(r['frame'], addr), gb(r['frame'], addr + 1)
            if hi is None or lo is None:
                continue
            v = hi * 256 + lo
            if v >= 32768:
                v -= 65536
            pts.append((v, r['lead']))
        if len(pts) < 10:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        if len(set(xs)) < 3:
            continue
        mx, my = statistics.mean(xs), statistics.mean(ys)
        den = sum((x - mx) ** 2 for x in xs)
        if den == 0:
            continue
        a = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den
        b = my - a * mx
        good = sum(1 for x, y in pts if abs(y - (a * x + b)) <= 1)
        if good >= len(pts) * 0.9:
            print("   %s: lead = %.4f * v + %.2f   within +-1 on %d/%d"
                  % (label, a, b, good, len(pts)))

    # 3. exhaustive sweep, for anything the above missed
    best, counters = [], []
    sweep = (list(range(0xFF8800, 0xFF8C00)) + list(range(0xFF8400, 0xFF8800))
             + list(range(0xFF8000, 0xFF8400)) + list(range(0xFF9400, 0xFF9C00)))
    for addr in sweep:
        g = collections.defaultdict(list)
        okay = True
        for r in rows:
            if r['frame'] is None:
                okay = False
                break
            v = gb(r['frame'], addr)
            if v is None:
                okay = False
                break
            g[v].append(r['lead'])
        if not okay or len(g) < 2:
            continue
        worst = max(max(v) - min(v) for v in g.values())
        # REJECT BYTES THAT ARE SIMPLY UNIQUE PER SAMPLE.
        #
        # A byte taking a different value in almost every span has a spread of
        # zero inside each value for the trivial reason that each value was
        # seen once. That is not a relationship, and reporting it as one is
        # worse than reporting nothing - it invites a table to be built out of
        # noise. Require most values to have been seen more than once, and the
        # number of distinct values to be well under the sample count.
        repeats = sum(1 for v in g.values() if len(v) >= 2)
        # ...but a genuine COUNTDOWN looks exactly like a unique-per-sample
        # byte, because a counter takes a different value in almost every span.
        # Filtering first and looking for countdowns afterwards meant the real
        # stun timer ($15c) was thrown away before it could be recognised, and
        # this script reported "no byte predicts it" for weeks. Test the
        # countdown shape BEFORE the filter can discard the candidate.
        diffs = {lead - v for v, leads in g.items() for lead in leads}
        if len(diffs) == 1 and len(g) >= 3:
            counters.append((addr, list(diffs)[0], len(g)))
        if len(g) > len(rows) / 3 or repeats < len(g) / 2:
            continue
        best.append((worst, addr, g))
    # A counter that runs the phase shows up as value == lead + constant, i.e.
    # every observed (value, lead) pair sharing one difference. Worth naming
    # separately from a lookup-table relation.
    for addr, off, n in counters[:3]:
        print("   COUNTDOWN 0x%04X (%s): lead = value %+d   (%d distinct values)"
              % (addr, region_label(addr), off, n))
    best.sort(key=lambda t: t[0])
    if best and best[0][0] <= 2:
        worst, addr, g = best[0]
        print("   byte 0x%04X (%s): within %d -> %s"
              % (addr, region_label(addr), worst,
                 {k: (min(v) if min(v) == max(v) else (min(v), max(v)))
                  for k, v in sorted(g.items())}))
    elif best:
        print("   no byte predicts it (best within-value spread %d, %s)"
              % (best[0][0], region_label(best[0][1])))
    else:
        print("   no byte predicts it (every candidate was unique-per-sample)")


def main():
    log_dir = sys.argv[1] if len(sys.argv) > 1 else \
        r"C:\fightcade\emulator\fbneo\scripts\reversal_logs"
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("no kd_*.json in", log_dir)
        return
    versions = {json.load(open(p, encoding='utf-8')).get('script_version')
                for p in paths}
    if len(versions) > 1:
        print("WARNING: mixed script versions, do not pool:", sorted(versions, key=str))
    rows = list(spans(paths))
    by = collections.defaultdict(list)
    for r in rows:
        by[r['kind']].append(r)
    for name in sorted(by):
        describe(name, by[name])


if __name__ == "__main__":
    main()
