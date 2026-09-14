"""How long the dash actually lasts, and whether the button landed inside it.

"Dash attack comes out at delay 4 and turns into a walking attack at 5" has
two possible causes and they need different fixes:

  the tool   the lever or the press is not where the menu says it is
  the game   the dash is simply over by then, and no delay can reach it

$06 == 0x14 IS the dash state, so the question is decidable from the trace:
was the character still in 0x14 on the tick the button went down? This walks
every dash episode in every recording and answers exactly that.

    python dash_delay.py [log_dir] [--ticks]
"""
import collections
import glob
import json
import os
import sys

from explain_leads import canonical
from simulate_arm import NAMES

DASH = 0x14


def btn(t):
    return (t.get('j') or 0) // 256


def lever(t):
    v = (t.get('j') or 0) % 16
    if v == 0:
        return '.'
    return ''.join(c for b, c in ((0x08, 'U'), (0x04, 'D'),
                                  (0x02, '2'), (0x01, '1')) if v & b)


def episodes(can):
    """(start, end) index pairs where $06 stayed 0x14."""
    out, i = [], 0
    while i < len(can):
        if can[i].get('b') == DASH:
            j = i
            while j + 1 < len(can) and can[j + 1].get('b') == DASH:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out


def marks_by_lg(data):
    out = collections.defaultdict(list)
    for w in data.get('writes') or []:
        if w.get('lg') is not None:
            out[w['lg']].append("%s=%s@%s" % (w.get('addr'), w.get('val'),
                                              w.get('pc')))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    show = '--ticks' in sys.argv
    log_dir = args[0] if args else \
        r"C:\fightcade\emulator\fbneo\scripts\reversal_logs"
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("kd_*.json ga nai:", log_dir)
        return

    rows = []
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        can = canonical(data.get('ticks') or [])
        mk = marks_by_lg(data)
        cfg = data.get('settings') or {}
        delay = cfg.get('gc_delay')
        for a, b in episodes(can):
            cid = can[a].get('p2c')
            n = b - a + 1
            # The first button press at or after the dash started.
            press = None
            for k in range(a, min(b + 12, len(can))):
                if btn(can[k]) and not btn(can[k - 1] if k else {}):
                    press = k
                    break
            inside = press is not None and press <= b
            rows.append({
                'file': os.path.basename(path), 'char': NAMES.get(cid, cid),
                'delay': delay, 'len': n,
                'press': None if press is None else press - a,
                'inside': inside, 'can': can, 'a': a, 'b': b, 'mk': mk,
            })

    if not rows:
        print("dash ($06 == 0x14) no episode ga nai")
        return

    per = collections.defaultdict(list)
    for r in rows:
        per[(r['char'], r['delay'])].append(r)
    for key in sorted(per, key=str):
        grp = per[key]
        print("=" * 72)
        print("%s  delay=%s  dash episodes=%d" % (key[0], key[1], len(grp)))
        print("   dash length (ticks): %s"
              % dict(sorted(collections.Counter(r['len'] for r in grp).items())))
        print("   button at dash+N   : %s"
              % dict(sorted(collections.Counter(r['press'] for r in grp).items(),
                            key=lambda kv: str(kv[0]))))
        print("   button INSIDE dash : %d / %d"
              % (sum(1 for r in grp if r['inside']), len(grp)))
        if not show:
            continue
        for r in grp:
            print("   --- %s  len=%d press=+%s inside=%s"
                  % (r['file'], r['len'], r['press'], r['inside']))
            can, a, b = r['can'], r['a'], r['b']
            for k in range(max(0, a - 4), min(b + 8, len(can))):
                t = can[k]
                print("      %+3d g=%-3s $06=%02X $05=%02X lev=%-4s btn=%02X  %s"
                      % (k - a, t.get('g'), t.get('b') or 0, t.get('a') or 0,
                         lever(t), btn(t),
                         ' '.join(r['mk'].get(t.get('g'), []))))


if __name__ == "__main__":
    main()
