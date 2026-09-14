"""Per-character wake-up report: what armed, what was delivered, what came out.

simulate_arm.py answers "where would the rule fire". It cannot answer "did the
motion actually reach the game", which is the question the input history on
screen is asking - a column of repeated single directions means entries are
being delivered and then the sequence is dropped before it finishes.

Everything needed is already in the tick trace:

    k   $1a7 wake-up tally      c   $07 sub-state (2 ordinary, 4/6 rolling)
    ka  kd_armed*100 + by_land*10 + hs_armed
    rl  released*100 + current_frame*10 + #sequence   (-1 = no sequence)
    j   $394 raw lever+buttons   i  $122/$123 after the facing swap
    b   $06 action category      a  $05 master state

Raw lever bits (pre-facing-swap, 0x022194 exchanges bit0/bit1):
    0x01 bit0   0x02 bit1   0x04 down   0x08 up

    python kd_report.py [log_dir] [--spans]

Without --spans it prints one block per character; with it, every span's last
ticks are dumped so a specific failure can be read directly.
"""
import collections
import glob
import json
import os
import sys

from explain_leads import canonical, REVERSAL_WINDOW
from simulate_arm import NAMES

MOVE_VALUES = (0x0E, 0x10, 0x12)


def lever(t):
    """The raw lever nibble as arrows, from $394."""
    v = (t.get('j') or 0) % 256
    d = v % 16
    if d == 0:
        return '.'
    return ''.join(c for b, c in ((0x08, 'U'), (0x04, 'D'),
                                  (0x02, '2'), (0x01, '1')) if d & b)


def btn(t):
    """Button bits of $394's high byte, if any."""
    v = (t.get('j') or 0)
    return '%02X' % (v // 256) if v // 256 else '..'


def seq_state(t):
    rl = t.get('rl')
    if rl is None or rl < 0:
        return '----'
    return '%s%d/%d' % ('R' if rl // 100 else '-', (rl // 10) % 10, rl % 10)


def btn_at(ticks):
    """Ticks before free that the BUTTON was asserted, and the lever with it.

    This is the one measurement that does not depend on understanding the
    controller's internals: whatever queued it, the button edge is the moment
    the game is asked for the move, and $394's high byte shows it.
    """
    for j, t in enumerate(ticks):
        if (t.get('j') or 0) // 256:
            return len(ticks) - j
    return None


def motion(ticks, back=10):
    """The last `back` ticks of lever activity as a compact string."""
    out = []
    for t in ticks[-back:]:
        s = lever(t)
        b = (t.get('j') or 0) // 256
        out.append(s + ('+' if b else ''))
    return ' '.join(out)


def outcome(can, i):
    """Ticks from the actionable tick until a special starts, or None."""
    for k in range(i, min(i + 40, len(can))):
        if can[k]['b'] in MOVE_VALUES:
            return k - i
    return None


def spans(paths):
    """Every knockdown span: (char, ticks up to and including free-1, free idx)."""
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        can = canonical(data.get('ticks') or [])
        cfg = data.get('settings') or {}
        st = "%s+%s" % (cfg.get('counter_attack_stick_dummy'),
                        cfg.get('counter_attack_button2'))
        for i in range(1, len(can)):
            if not (can[i - 1]['a'] == 0x02 and can[i]['a'] == 0):
                continue
            if can[i - 1].get('r') != 0x0A:
                continue
            start = i - 1
            while start > 0 and can[start - 1].get('r') == 0x0A:
                start -= 1
            yield os.path.basename(path), st, can, start, i


def start_07(ticks):
    """$07 at the tick $1a7 first reads 1 - the wake-up variant."""
    for t in ticks:
        if t.get('k') == 1:
            return t.get('c')
    return ticks[0].get('c') if ticks else None


def arm_at(ticks):
    """Ticks before free that kd_armed first went up, how many times, and the
    $1a7 value it went up on - the latter is what the rule actually tests."""
    first, count, prev, k = None, 0, False, None
    for j, t in enumerate(ticks):
        now = (t.get('ka') or 0) // 100 == 1
        if now and not prev:
            count += 1
            if first is None:
                first = len(ticks) - j
                k = t.get('k')
        prev = now
    return first, count, k


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    show = '--spans' in sys.argv
    viewer = '--viewer' in sys.argv
    log_dir = args[0] if args else \
        r"C:\fightcade\emulator\fbneo\scripts\reversal_logs"
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("kd_*.json ga nai:", log_dir)
        return

    if viewer:
        show_viewer(paths)
        return

    per = collections.defaultdict(list)
    for name, st, can, start, i in spans(paths):
        ticks = can[start:i]
        cid = can[i - 1].get('p2c')
        rec = {
            'file': name, 'stick': st,
            'c07': start_07(ticks), 'end_k': can[i - 1].get('k'),
            'delay': outcome(can, i), 'n': len(ticks),
            'ticks': ticks, 'can': can, 'free': i,
        }
        rec['arm'], rec['arms'], rec['arm_k'] = arm_at(ticks)
        rec['btn'] = btn_at(ticks)
        rec['motion'] = motion(ticks)
        per[cid].append(rec)

    for cid in sorted(per, key=lambda c: NAMES.get(c, '')):
        rows = per[cid]
        print("=" * 72)
        print("%s (0x%02X)  spans=%d" % (NAMES.get(cid, cid), cid, len(rows)))
        by07 = collections.defaultdict(list)
        for r in rows:
            by07[(r['c07'], r['stick'])].append(r)
        for key in sorted(by07, key=str):
            c07, stick = key
            grp = by07[key]
            ok = sum(1 for r in grp if r['delay'] == 0)
            late = sum(1 for r in grp
                       if r['delay'] is not None and r['delay'] > 0)
            none = sum(1 for r in grp if r['delay'] is None)
            kind = {0x02: 'sono-ba', 0x04: 'roll', 0x06: 'roll6'}.get(c07, '?')
            print("  $07=%s (%s) %s  n=%d  REVERSAL %d / late %d / none %d"
                  % (c07, kind, stick, len(grp), ok, late, none))
            print("     end $1a7 : %s"
                  % dict(sorted(collections.Counter(
                      r['end_k'] for r in grp).items())))
            print("     arm free-N: %s"
                  % dict(sorted(collections.Counter(
                      r['arm'] for r in grp).items(), key=lambda kv: str(kv[0]))))
            print("     arm $1a7  : %s"
                  % dict(sorted(collections.Counter(
                      r['arm_k'] for r in grp).items(), key=lambda kv: str(kv[0]))))
            print("     arm kaisuu: %s"
                  % dict(sorted(collections.Counter(
                      r['arms'] for r in grp).items())))
            print("     delay     : %s"
                  % dict(sorted(collections.Counter(
                      r['delay'] for r in grp).items(), key=lambda kv: str(kv[0]))))
            # THE decisive cross-tabs. Success is delay == 0 here, not
            # delay <= REVERSAL_WINDOW: a move that starts 3 ticks after the
            # character is free is a late move, and lumping it in with the
            # frame-perfect ones is what made Anakaris look 11/20 when only 2
            # of those were reversals.
            for field, label in (('btn', 'button free-N'), ('arm_k', 'arm $1a7')):
                bt = collections.defaultdict(collections.Counter)
                for r in grp:
                    bt[r[field]]['o' if r['delay'] == 0 else 'x'] += 1
                print("     %s x kekka:" % label)
                for b in sorted(bt, key=str):
                    print("        %-6s  REVERSAL %-3d  shippai %-3d"
                          % (b, bt[b]['o'], bt[b]['x']))
            shapes = collections.Counter(r['motion'] for r in grp)
            for s, c in shapes.most_common(4):
                print("     x%-3d %s" % (c, s))

        if not show:
            continue
        for r in rows:
            print("  --- %s  $07=%s end_k=%s arm=free-%s delay=%s"
                  % (r['file'], r['c07'], r['end_k'], r['arm'], r['delay']))
            can, i = r['can'], r['free']
            lo = max(0, i - 16)
            for k in range(lo, min(i + 6, len(can))):
                t = can[k]
                print("     %+4d k=%-3s c=%-3s u=%-3s n=%-2s ld=%-3s ka=%-3s "
                      "seq=%-5s lev=%-4s btn=%s  $05=%02X $06=%02X"
                      % (k - i, t.get('k'), t.get('c'), t.get('u'), t.get('n'),
                         t.get('ld'), t.get('ka'), seq_state(t), lever(t),
                         btn(t), t.get('a') or 0, t.get('b') or 0))




# ------------------------------------------------------- the on-screen column
# What vsavscriptv2.lua's scrolling input viewer will draw for P2, replayed
# from the tick trace.
#
# The viewer is a pure function of the per-tick ($122, $123, $b) samples that
# guardCancel.lua queues, and the trace already carries all three - `i` is
# $122/$123 packed and `x` is the facing byte. So the column can be checked
# offline instead of by reading it off a screenshot, which is the whole point:
# "Zabel's history is odd" has to become a statement about specific rows.
#
#   rows  1=l 2=r 3=u 4=d 5=ul 6=ur 7=dl 8=dr 9=LP 10=MP 11=HP 12=LK 13=MK 14=HK
ROW_NAME = {1: '<', 2: '>', 3: '^', 4: 'v', 5: '<^', 6: '>^', 7: '<v', 8: '>v',
            9: 'LP', 10: 'MP', 11: 'HP', 12: 'LK', 13: 'MK', 14: 'HK'}
BUTTON_ROW = {0: 9, 1: 10, 2: 11, 4: 12, 5: 13, 6: 14}


def viewer_frame(word, facing):
    """One tick's ($122,$123) -> the row set the viewer would build."""
    btn, dir_ = word // 256, word % 256
    bit0, bit1 = dir_ & 1, (dir_ >> 1) & 1
    left, right = (bit1, bit0) if facing == 0 else (bit0, bit1)
    rows = set()
    if left:
        rows.add(1)
    if right:
        rows.add(2)
    if (dir_ >> 3) & 1:
        rows.add(3)
    if (dir_ >> 2) & 1:
        rows.add(4)
    for b, row in BUTTON_ROW.items():
        if (btn >> b) & 1:
            rows.add(row)
    # compositeinput(): ul, ur, dl, dr
    for a, b, c in ((1, 3, 5), (2, 3, 6), (1, 4, 7), (2, 4, 8)):
        if a in rows and b in rows:
            rows.discard(a)
            rows.discard(b)
            rows.add(c)
    return rows


def viewer_records(ticks):
    """The records the viewer would push, newest last.

    detectchanges() only fires when a row is set that was NOT set on the
    previous sample, and only ticks whose ($122,$123) changed are queued at all.
    """
    out, last, prev_word = [], set(), None
    for t in ticks:
        word = t.get('i') or 0
        if word == prev_word:
            continue
        prev_word = word
        rows = viewer_frame(word, t.get('x') or 0)
        if any(r not in last for r in rows):
            out.append((t.get('k'), rows))
        last = rows
    return out


def show_viewer(paths):
    per = collections.defaultdict(list)
    for name, st, can, start, i in spans(paths):
        cid = can[i - 1].get('p2c')
        recs = viewer_records(can[max(0, i - 20):i])
        per[(NAMES.get(cid, cid), st)].append(recs)
    for key in sorted(per, key=str):
        print("=" * 72)
        print("%s  %s" % key)
        shapes = collections.Counter(
            ' '.join('%s' % '+'.join(ROW_NAME.get(r, str(r))
                                     for r in sorted(rows))
                     for _k, rows in r_) for r_ in per[key])
        for shape, n in shapes.most_common(6):
            print("   x%-3d %s" % (n, shape or '(nothing)'))

if __name__ == "__main__":
    main()
