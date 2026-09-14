"""
Classify reversal attempts in the FBNeo knockdown logs.

THE TEST (derived from the engine's structure, not fitted to data):

    A reversal is a move that starts on the VERY FRAME the character becomes
    free again. Concretely:

      1. status_1 (0xFF8805) transitions $02 -> $00
         This is the character leaving Hurt/Block and becoming actionable.
         The engine does it in exactly three places - 0x026D54 / 0x026D72 /
         0x026D8A - and EVERY recovery type funnels through them, so this one
         edge covers wake-up, hitstun, blockstun and air-recovery landing
         alike.
      2. On that same frame, status_2 (0xFF8806) already reads a move value.
         0x0E = special, 0x10 = ES, 0x12 = EX.
         (Use MOVE_VALUES below; add 0x0A if you want "fastest normal",
          0x06 jump, 0x14 dash, 0x16 Dark Force - see the table in
          VSAV_ENGINE.md 4.5.6.)

    Frame-exactness is the whole point. Measured on the ground-truth batch,
    the delay between the free frame and the move starting separates the two
    populations perfectly: every user-confirmed reversal had delay 0, every
    non-reversal had delay 1 or 2. A move that comes out one frame late is
    still a move - it just is not a reversal.

VALIDATION: 17/18 against user-marked ground truth (the user pressed a hotkey
whenever "REVERSAL" appeared on screen). The single disagreement is
kd_m04 @ release 4578, which this test calls a reversal and the marks do not
- but that recording contains two attempts and only one mark, so the ground
truth there is itself uncertain. See KNOCKDOWN_ONLY_CHECK below.

SUPERSEDES the earlier test ("status_2 becomes a move value while the
knockdown clock 0xFF89A7 is still nonzero"). That one also scored 18/18 on
the same batch, but it only works for KNOCKDOWN reversals - the knockdown
clock does not run during hitstun or blockstun, so it cannot see reversals
out of those states at all. It is kept here as an optional extra check
because it is what disagrees on kd_m04.

NO EXTRA INSTRUMENTATION NEEDED: 0xFF8805 / 0xFF8806 / 0xFF89A7 all sit
inside debugKnockdown.lua's existing memory sweep ({0xFF8800, 256}), so any
recording already on disk can be classified after the fact.

Usage:  python classify_reversals.py [log_dir]
"""
import json
import glob
import os
import sys

STATUS_1 = 0xFF8805   # $05  master state: $02 = Hurt or Block, $00 = free
STATUS_2 = 0xFF8806   # $06  action category
KD_CLOCK = 0xFF89A7   # $1a7 knockdown clock (only meaningful for wake-ups)

MOVE_VALUES = (0x0E, 0x10, 0x12)     # special / ES / EX
# Handy extras from VSAV_ENGINE.md 4.5.6, if you want to classify other
# "fastest X out of recovery" cases with the same edge:
ACTION_NAMES = {0x06: "jump", 0x0A: "normal", 0x0E: "special",
                0x10: "ES", 0x12: "EX", 0x14: "dash", 0x16: "dark force",
                0x1C: "action-denied"}

SEARCH_FRAMES = 60
KNOCKDOWN_ONLY_CHECK = False   # also require kd clock != 0 (wake-ups only)


def addr_to_index(addr):
    """Byte address -> (dword index, byte offset) in the swept `rows` data.

    Layout is debugKnockdown.lua's REGIONS, concatenated in order:
      {0xFF8800, 256} -> dwords   0..255
      {0xFF8400, 128} -> dwords 256..383
      {0xFF9400, 512} -> dwords 384..895
    """
    if 0xFF8800 <= addr < 0xFF8C00:
        off = addr - 0xFF8800
        return off // 4, off % 4
    if 0xFF8400 <= addr < 0xFF8800:
        off = addr - 0xFF8400
        return 256 + off // 4, off % 4
    if 0xFF9400 <= addr < 0xFF9C00:
        off = addr - 0xFF9400
        return 512 + off // 4, off % 4
    if 0xFF8000 <= addr < 0xFF8400:
        off = addr - 0xFF8000
        return 1024 + off // 4, off % 4
    return None, None


def reconstruct(rows):
    """Rebuild swept memory per frame from the delta-compressed rows.

    First row carries `base` (every dword); later rows carry `d`, a flat
    {index, value, ...} of only CHANGED dwords, with Lua 1-based indices.
    Verified: reconstructed 0xFF880B / 0xFF8810 match the independently
    recorded row['fa2'] / row['x2'] fields on 261/261 frames.
    """
    frames = {}
    base = None
    for r in rows:
        if 'base' in r:
            base = list(r['base'])
        else:
            d = r['d']
            for i in range(0, len(d), 2):
                base[d[i] - 1] = d[i + 1]
        frames[r['f']] = list(base)
    return frames


def get_byte(dwords, addr):
    idx, boff = addr_to_index(addr)
    if idx is None or idx >= len(dwords):
        return None
    return dwords[idx].to_bytes(4, 'big')[boff]


def find_free_frame(frames, start, end):
    """The frame status_1 goes $02 -> $00, i.e. the first actionable frame.

    Only $02. status_1 also leaves 0x0E (Intro) for 0x00 at the start of a
    round, and that transition carries the same $06/$07 signature - counting
    it made the round start look like a missed reversal.
    """
    fs = sorted(f for f in frames if start <= f <= end)
    for i in range(1, len(fs)):
        prev, cur = fs[i - 1], fs[i]
        if get_byte(frames[prev], STATUS_1) == 0x02 and \
           get_byte(frames[cur], STATUS_1) == 0x00:
            return cur
    return None


def classify(frames, release_frame):
    """Return (verdict, free_frame, status_2_at_free, kd_at_free)."""
    free = find_free_frame(frames, release_frame - 2, release_frame + SEARCH_FRAMES)
    if free is None:
        return "never-free", None, None, None
    s2 = get_byte(frames[free], STATUS_2)
    kd = get_byte(frames[free], KD_CLOCK)
    if s2 in MOVE_VALUES:
        if KNOCKDOWN_ONLY_CHECK and not kd:
            return "special-not-reversal", free, s2, kd
        return "REVERSAL", free, s2, kd
    return "no-reversal", free, s2, kd


def main():
    log_dir = sys.argv[1] if len(sys.argv) > 1 else \
        r"C:\fightcade\emulator\fbneo\scripts\reversal_logs"
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("no kd_*.json found in", log_dir)
        return

    counts = {}
    out = []
    # Run-ahead changes how the tool behaves and how the logs read, so state it
    # up front rather than leaving it to be inferred. debugKnockdown.lua records
    # it per recording, measured from 0xFF8081 (see guardcancel_runahead_state).
    ra_active, ra_pct, ra_depth = False, 0.0, 0
    versions = set()
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        versions.add(data.get('script_version'))
        ra = data.get('runahead')
        if isinstance(ra, dict):
            ra_active = ra_active or bool(ra.get('active'))
            ra_pct = max(ra_pct, ra.get('percent') or 0)
            ra_depth = max(ra_depth, ra.get('depth_max') or 0)
    if len(versions) > 1:
        print("WARNING: several script versions in this folder - do not pool them:")
        for v in sorted(versions, key=str):
            print("   ", v)
        print()
    print("run-ahead: %s" % ("ON  (%.1f%% of ticks re-run, depth up to %d)"
                             % (ra_pct, ra_depth) if ra_active else "off"))
    print()
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        frames = reconstruct(data['rows'])
        marks = data.get('marks', [])
        # ONE ATTEMPT CAN LOG SEVERAL ENTRIES. The emulator re-executes ticks
        # after a state rewind (measured: ~29% of ticks on the v33 batch), and
        # Lua state is not rewound with it, so a hook that fires on a
        # speculative pass logs again on the real one. Both entries resolve to
        # the same free frame - collapse them, or the attempt count inflates
        # and the success rate is understated.
        #
        # 'released'    = a trigger that handed the input to the controller
        # 'tick_inject' = the tick-exact hook writing the input word itself
        events = [h for h in data.get('holds', [])
                  if h.get('event') in ('released', 'tick_inject')]
        seen_free = set()
        for rel in events:
            verdict, free, s2, kd = classify(frames, rel['f'])
            key = free if free is not None else ('nofree', rel['f'])
            if key in seen_free:
                continue
            seen_free.add(key)
            counts[verdict] = counts.get(verdict, 0) + 1
            marked = any(0 <= m - rel['f'] <= 50 for m in marks)
            out.append((os.path.basename(path), rel['f'], free, s2, kd, verdict, marked))

    print(f"{'file':<15}{'release':>8}{'free':>7}{'st2':>6}{'kd':>5}  "
          f"{'verdict':<20}user_marked")
    for fn, rf, free, s2, kd, verdict, marked in out:
        s2s = f"0x{s2:02X}" if s2 is not None else "-"
        act = ACTION_NAMES.get(s2, "")
        print(f"{fn:<15}{rf:>8}{str(free):>7}{s2s:>6}{str(kd):>5}  "
              f"{verdict:<20}{'YES' if marked else ''}  {act}")

    total = sum(counts.values())
    print()
    print(f"total attempts: {total}")
    for k, v in sorted(counts.items()):
        print(f"  {k:<22} {v:>3}  ({100.0*v/total:.0f}%)")

    disagree = [r for r in out if (r[5] == "REVERSAL") != r[6]]
    if disagree:
        print()
        print(f"NOTE: {len(disagree)} attempt(s) where the test and the user's marks disagree:")
        for r in disagree:
            print(f"  {r[0]} release={r[1]} test={r[5]} marked={r[6]}")
        print("  (only meaningful for batches where the mark hotkey was actually used)")


if __name__ == "__main__":
    main()
