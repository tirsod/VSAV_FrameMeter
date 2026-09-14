# -*- coding: utf-8 -*-
"""WHAT $06 READS ON THE TICK THE OPPONENT STOPS BEING STUNNED.

tickData decides the opponent can act again when $05 and $06 are BOTH zero
(tickData.lua, p2_can_act). Walking turned out to be $06 = 0x04 rather than
0x00, so an opponent that leaves stun straight into a walk would never satisfy
that test and the frame advantage would read long. Whether the game actually
does that is not measured yet - this reads it out of a probe log.

  python analysis/recover_state_report.py

The recovery tick is the tick the defender's $05 leaves 0x02. What matters is
$06 on that tick: 0x00 means the current test sees it, anything else means it
does not. The P2 lever is printed alongside, because the hypothesis is that a
held direction is what produces the 0x04.

Needs a log recorded after p2_06 was added to routeProbe.lua; older sessions
are skipped with a note rather than guessed at.
"""
import importlib.util
import sys
import collections

spec = importlib.util.spec_from_file_location(
    "csr", "analysis/contact_state_report.py")
csr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(csr)

LEVER = {0x00: "中立", 0x01: "bit0", 0x02: "bit1", 0x04: "下",
         0x05: "下+bit0", 0x06: "下+bit1", 0x08: "上",
         0x09: "上+bit0", 0x0A: "上+bit1"}


def main():
    seen = collections.Counter()
    rows_out = []
    skipped = 0
    for header, rows in csr.sessions(csr.LOG):
        if not any("p2_06" in r for r in rows[:8]):
            skipped += 1
            continue
        prev = None
        for i, r in enumerate(rows):
            if prev is not None and prev.get("p2_05") == 0x02 \
                    and r.get("p2_05") == 0x00:
                state = r.get("p2_06")
                seen[state] += 1
                after = [x.get("p2_06") for x in rows[i + 1:i + 4]]
                rows_out.append((
                    header.replace("=== route probe ", "").replace(" ===", ""),
                    r["t"], state, r.get("p2_lever"), r.get("p2_38"),
                    prev.get("p2_140"), after))
            prev = r

    if skipped:
        print("p2_06 の無い古いセッションを %d 個読み飛ばした" % skipped)
    if not rows_out:
        print("復帰の瞬間が 1 件も見つからなかった")
        return 0

    print("復帰ティック (防御側 $05 が 0x02 を抜けた瞬間) %d 件" % len(rows_out))
    print()
    print("  %-21s %-5s %-5s %-9s %-5s %-6s %s" % (
        "session", "t", "$06", "lever", "$38", "直前$140", "次の$06"))
    for s, t, state, lev, air, recover, after in rows_out:
        print("  %-21s %-5d %-5s %-9s %-5s %-6s %s" % (
            s, t,
            "--" if state is None else "0x%02X" % state,
            LEVER.get(lev, "?" if lev is None else "0x%02X" % lev),
            "--" if air is None else "0x%02X" % air,
            "--" if recover is None else "0x%02X" % recover,
            " ".join("--" if a is None else "0x%02X" % a for a in after)))
    print()
    total = sum(seen.values())
    for k, v in sorted(seen.items(), key=lambda kv: (kv[0] is None, kv[0])):
        label = "--" if k is None else "0x%02X" % k
        print("  $06=%s: %d 件 (%.0f%%)" % (label, v, 100.0 * v / total))
    hit = seen.get(0x00, 0)
    print()
    print("現在の p2_can_act ($05 と $06 が両方 0) が拾えるのは %d / %d 件"
          % (hit, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
