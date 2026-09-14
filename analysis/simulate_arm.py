"""Replay the arming logic against recorded logs, before shipping a build.

Between v99 and v102 the same mistake was made four times: a change was reasoned
about, shipped, and only then measured - and each round cost a full test session
to discover it had armed in the wrong place. Every input that decision needs is
already in the logs, one row per game tick, so the decision can be replayed
offline instead.

    python simulate_arm.py                     # current logs
    python simulate_arm.py <log_dir>           # an archived batch

For each knockdown span it reports where the rule would arm, measured in ticks
before the actionable tick. Anything that never arms, or arms outside the
delivery band, is a build that will fail - and it costs nothing to find out.

The tick trace carries:
    ld  ticks_to_landing()      r   $140 recovery variant
    u   $21 animation cel       c   $07 sub-state
    k   $1a7 wake-up tally      p2c P2 character id

Caveat worth keeping in mind: the real arming runs once per DISPLAYED frame in
service_held_reversal(), this replays it once per TICK. With run-ahead off those
are the same rate, which is the only configuration being shipped. It cannot
model the controller's delivery latency either - it answers "where does the rule
fire", not "does the reversal come out".
"""
import collections
import glob
import json
import os
import sys

from explain_leads import canonical

NAMES = {0x00: 'Bulleta', 0x01: 'Demitri', 0x02: 'Gallon', 0x03: 'Victor',
         0x04: 'Zabel', 0x05: 'Morrigan', 0x06: 'Anakaris', 0x07: 'Felicia',
         0x08: 'Bishamon', 0x09: 'Aulbath', 0x0A: 'Sasquatch', 0x0B: 'Zabel2',
         0x0C: 'Q-Bee', 0x0D: 'Lei-Lei', 0x0E: 'Lilith', 0x0F: 'Jedah',
         # 0x0B is a second Zabel slot - charMoves.lua returns "Zabel" for
         # it too. The suffix here is only to tell the two ids apart in a
         # report; it is not a character name.
         0x12: 'Dark Gallon', 0x18: 'Oboro'}

KD_LAND_ARM = 4
BAND = (3, 15)          # ticks before free that a delivery can still make


# ---------------------------------------------------------------- the rules
def rule_v102(t, st):
    """ld >= 2 gates the landing branch; only a landing latch is releasable."""
    ld, u, c, r = t.get('ld'), t.get('u'), t.get('c'), t.get('r')
    land_ok = (ld is not None and 2 <= ld <= KD_LAND_ARM)
    if st['by_land'] and not land_ok and r == 0x0A:
        st['armed'] = False
        st['by_land'] = False
    edge = ((not st['armed']) and r == 0x0A
            and (land_ok or (not land_ok and u == 0x40 and c == 0x02)))
    if edge:
        st['armed'] = True
        st['by_land'] = land_ok
    return edge


def rule_v101(t, st):
    """What shipped as v101: no ld >= 2 floor, latch keyed on ld being non-nil."""
    ld, u, c, r = t.get('ld'), t.get('u'), t.get('c'), t.get('r')
    if ld is not None and ld > KD_LAND_ARM and r == 0x0A:
        st['armed'] = False
    edge = ((not st['armed']) and r == 0x0A
            and ((ld is not None and ld <= KD_LAND_ARM)
                 or (ld is None and u == 0x40 and c == 0x02)))
    if edge:
        st['armed'] = True
    return edge


def rule_v92(t, st):
    """Animation only - the rule Morrigan and Lilith were measured on."""
    u, c, r = t.get('u'), t.get('c'), t.get('r')
    edge = (not st['armed']) and r == 0x0A and u == 0x40 and c == 0x02
    if edge:
        st['armed'] = True
    return edge


RULES = {'v92': rule_v92, 'v101': rule_v101, 'v102': rule_v102}

def make_land_rule(arm_at):
    """v102 with KD_LAND_ARM as a parameter, so the value can be chosen from
    the logs instead of by guessing. Measured delivery latency is about 4 ticks
    from arm to the first direction appearing, so arm_at sets where the motion
    STARTS, not where it finishes."""
    def rule(t, st):
        ld, u, c, r = t.get('ld'), t.get('u'), t.get('c'), t.get('r')
        land_ok = (ld is not None and 2 <= ld <= arm_at)
        if st['by_land'] and not land_ok and r == 0x0A:
            st['armed'] = False
            st['by_land'] = False
        edge = ((not st['armed']) and r == 0x0A
                and (land_ok or (not land_ok and u == 0x40 and c == 0x02)))
        if edge:
            st['armed'] = True
            st['by_land'] = land_ok
        return edge
    return rule


for _n in (4, 5, 6, 7, 8, 9, 10):
    RULES['land%d' % _n] = make_land_rule(_n)

def make_strict_rule(arm_at):
    """Animation branch ONLY when the character is grounded.

    v102 let the animation branch fire whenever the landing branch was not
    ready, which put Bishamon's $07 == 2 wake-up on $21 == 0x40 at free-8 -
    measured 0/9. He is airborne there and his ld counts down normally, so the
    landing branch should own him; it just had not reached its threshold yet.

    Grounded is ld == nil or ld == 1: a character standing on the floor sits one
    tick above it with gravity applied, so the simulation says "lands next tick"
    forever (section 8.6.121). That is the only case the animation timer is the
    real authority for.
    """
    def rule(t, st):
        ld, u, c, r = t.get('ld'), t.get('u'), t.get('c'), t.get('r')
        grounded = (ld is None or ld == 1)
        land_ok = (not grounded) and ld <= arm_at
        anim_ok = grounded and u == 0x40 and c == 0x02
        if st['by_land'] and not land_ok and r == 0x0A:
            st['armed'] = False
            st['by_land'] = False
        edge = (not st['armed']) and r == 0x0A and (land_ok or anim_ok)
        if edge:
            st['armed'] = True
            st['by_land'] = land_ok
        return edge
    return rule


for _n in (3, 4, 5, 6):
    RULES['strict%d' % _n] = make_strict_rule(_n)

def make_cel_rule(arm_at, cel_at):
    """Animation branch gated on $20, the frame counter INSIDE the cel.

    $21 == 0x40 only says "final cel has started", and cels are different
    lengths per character, so that edge sits at free-6 for Morrigan but free-8
    for Bishamon. Measured, arming at free-8 is 0/9 - the whole command
    completes while the character is still in recovery and the recogniser
    consumes it before it can come out.

    $20 counts down inside the cel, so ($21 == 0x40 and $20 <= 3) lands at
    free-5..-6 for every character measured, which is where the outcome data is
    best (free-5: 47/8, free-6: 41/1).
    """
    def rule(t, st):
        ld, u, c, r, n = (t.get('ld'), t.get('u'), t.get('c'), t.get('r'),
                          t.get('n'))
        grounded = (ld is None or ld == 1)
        land_ok = (not grounded) and ld <= arm_at
        anim_ok = (grounded and u == 0x40 and c == 0x02
                   and n is not None and n <= cel_at)
        if st['by_land'] and not land_ok and r == 0x0A:
            st['armed'] = False
            st['by_land'] = False
        edge = (not st['armed']) and r == 0x0A and (land_ok or anim_ok)
        if edge:
            st['armed'] = True
            st['by_land'] = land_ok
        return edge
    return rule


for _c in (2, 3, 4):
    RULES['cel%d' % _c] = make_cel_rule(4, _c)


# ------------------------------------------------------------------ v131
# The $1a7 character table, with the arm decoupled from the delivery.
#
# v130 armed at `end - #sequence` and started the motion there, one entry per
# displayed frame. Two things were wrong with that and the v130 batch shows
# both: a frame is about 1.6 ticks during a wake-up so the arm cannot land on a
# chosen tick (Zabel armed on $1a7 18/19/20 against a window opening at 19), and
# one entry per frame is too slow to walk a 3-entry motion through in the 3-5
# ticks that are left (Anakaris, Gallon and Victor delivered 2 of 3).
#
# In v131 the tick hook delivers entry k on $1a7 == end - #seq + k, so all the
# arm has to do is queue the sequence before entry 1 is due. This models that:
# the rule may only fire on a tick the FRAME side actually saw, and it must fire
# at or before `end - #seq + 1`.
KD_END_1A7 = {
    0x02: {2: 29, 4: 31}, 0x03: {2: 30, 6: 30}, 0x04: {2: 22, 4: 38},
    0x05: {2: 27, 4: 47}, 0x06: {2: 27, 4: 46}, 0x08: {2: 23, 4: 30},
    0x09: {2: 28, 4: 33}, 0x0A: {2: 23, 4: 47}, 0x0B: {2: 22, 4: 38},
    0x0D: {2: 29, 4: 30}, 0x0E: {2: 27, 4: 47}, 0x0F: {2: 24, 4: 39},
}
# $07 == 6 is the same wake-up as 4; see the note in guardCancel.lua.
for _v in KD_END_1A7.values():
    if 6 not in _v and 4 in _v:
        _v[6] = _v[4]
SEQ_LEN = {'QCF': 3, 'QCB': 3, 'DPF': 3, 'DPB': 3, 'HCF': 4, 'HCB': 4,
           '360': 4, '720': 8, 'HCharge': 2, 'VCharge': 2}
KD_ARM_LEAD = 5


def make_v131_rule(lead=KD_ARM_LEAD):
    def rule(t, st):
        if st.get('seen') is False:          # a tick the frame side skipped
            return False
        end, n = st.get('end'), st.get('n')
        if end is None:
            return False
        k = t.get('k')
        if k is None or t.get('r') != 0x0A:
            return False
        grounded = (t.get('ld') is None or t.get('ld') == 1)
        if not grounded:
            return False
        edge = (not st['armed']) and (end - n + 1 - lead) <= k <= end
        if edge:
            st['armed'] = True
        return edge
    return rule


RULES['v131'] = make_v131_rule()


def rule_v132(t, st):
    """v131 plus the four measured rolling values, minus the grounded gate.

    Two things this has to show against the v131 logs:
      * the rolling variants that fell back to $21 (Gallon, Zabel, Anakaris,
        Sasquatch) now arm on the clock, in time;
      * dropping the grounded test does not move any arm that was already
        working - Bishamon's roll is airborne through its window and could not
        arm at all with the gate in place.
    """
    if st.get('seen') is False:
        return False
    end, n = st.get('end'), st.get('n')
    k = t.get('k')
    if end is None or k is None or t.get('r') != 0x0A:
        return False
    edge = (not st['armed']) and (end - n + 1 - 5) <= k <= end
    if edge:
        st['armed'] = True
    return edge


RULES['v132'] = rule_v132


def rule_v130(t, st):
    """What v130 shipped: arm at `end - #seq`, and START THE MOTION THERE.

    Kept so the simulator can be checked against a measured batch before its
    verdict on v131 is trusted. Under v130 the arm point IS the first entry, so
    the motion's button lands at arm + #seq - 1 and the measured rule is
    "button on free-1 or nothing" - i.e. this rule only succeeds when it fires
    exactly on `end - #seq + 1`.
    """
    if st.get('seen') is False:
        return False
    end, n = st.get('end'), st.get('n')
    k = t.get('k')
    if end is None or k is None or t.get('r') != 0x0A:
        return False
    if not (t.get('ld') is None or t.get('ld') == 1):
        return False
    edge = (not st['armed']) and (end - n) <= k <= end
    if edge:
        st['armed'] = True
    return edge


RULES['v130'] = rule_v130





def spans(paths):
    """Every knockdown span as a list of ticks ending at the actionable one."""
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            data = json.load(fh)
        can = canonical(data.get('ticks') or [])
        stick = (data.get('settings') or {}).get('counter_attack_stick_dummy')
        for i in range(1, len(can)):
            if not (can[i - 1]['a'] == 0x02 and can[i]['a'] == 0):
                continue
            if can[i - 1].get('r') != 0x0A:
                continue
            start = i - 1
            while start > 0 and can[start - 1].get('r') == 0x0A:
                start -= 1
            yield can[i - 1].get('p2c'), can[start:i], i - start, stick


def main():
    log_dir = sys.argv[1] if len(sys.argv) > 1 else \
        r"C:\fightcade\emulator\fbneo\scripts\reversal_logs"
    paths = sorted(glob.glob(os.path.join(log_dir, "kd_*.json")))
    if not paths:
        print("kd_*.json が無い:", log_dir)
        return
    data = list(spans(paths))
    print("起き上がりスパン %d 件 / ファイル %d\n" % (len(data), len(paths)))

    for name in sys.argv[2:] or ['v92', 'v101', 'v102']:
        rule = RULES[name]
        res = collections.defaultdict(collections.Counter)
        for cid, ticks, n, stick in data:
            end = (KD_END_1A7.get(cid) or {}).get(
                next((t.get('c') for t in ticks if t.get('k') == 1), None))
            st = {'armed': False, 'by_land': False, 'end': end,
                  'n': SEQ_LEN.get(stick, 3)}
            fired = None
            fires = 0
            prev_f = None
            for j, t in enumerate(ticks):
                # ARMING IS ONCE PER DISPLAYED FRAME, NOT ONCE PER TICK.
                # `f` is globals.current_frame, so the first tick carrying a new
                # `f` is the one service_held_reversal() sees; the rest are
                # invisible to it. Measured, that hides about four ticks in ten.
                st['seen'] = (prev_f is None or t.get('f') != prev_f)
                prev_f = t.get('f')
                # the real code clears the latch when $1a7 returns to 0
                if t.get('k') == 0:
                    st.update({'armed': False, 'by_land': False})
                if rule(t, st):
                    # LAST arm, not first. The latch can be released and
                    # re-armed, and each arm queues a fresh motion that
                    # supersedes the previous one - which is why a wrong rule
                    # shows up as a column of repeated directions in the input
                    # history. What decides the outcome is the final one.
                    fired = n - j          # ticks before the actionable tick
                    fires += 1
            res[cid]['fired' if fired is not None else 'NEVER'] += 1
            res[cid]['再arm'] += (1 if fires > 1 else 0)
            if fired is not None:
                res[cid]['band' if BAND[0] <= fired <= BAND[1] else 'outside'] += 1
                res[cid][('at', fired)] += 1
                # v131 only asks that the sequence EXISTS before entry 1 is due,
                # which is free-#sequence. Where it armed inside the lead does
                # not matter - nothing is injected until the clock says so.
                res[cid]['間に合った' if fired >= st['n'] else '遅刻'] += 1
        print("=== %s ===" % name)
        for cid in sorted(res, key=str):
            c = res[cid]
            tot = c['fired'] + c['NEVER']
            at = sorted((k[1], v) for k, v in c.items()
                        if isinstance(k, tuple))
            print("   %-9s n=%-3d  arm成立 %-3d  帯内 %-3d  帯外 %-3d  未発火 %-3d"
                  % (NAMES.get(cid, cid), tot, c['fired'], c['band'],
                     c['outside'], c['NEVER']))
            print("      複数回 arm したスパン: %d   間に合った %d / 遅刻 %d"
                  % (c['再arm'], c['間に合った'], c['遅刻']))
            print("      free-N の分布: %s" % dict(at))
        print()


if __name__ == "__main__":
    main()
