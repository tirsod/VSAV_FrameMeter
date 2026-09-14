# WHAT THE ATTACKER'S STATE BYTES READ ON THE TICK A HIT LANDS.
#
# ISSUE-CONTACT-ATTACKER-STATE-001 asks what $04/$05/$06/$07/$38/$105 are on the
# first tick a contact is observed. routeProbe.lua already logged four of those
# ($05 $06 $38 $105) across ordinary training sessions, so the answer is partly
# in analysis/dash_probe.log already - this pulls it out.
#
#   python analysis/contact_state_report.py
#
# A contact tick is the tick the DEFENDER's hitstop ($5C) goes from 0 to
# nonzero. That is the same signal the tool itself uses, and unlike the
# $05 -> 0x02 stun edge it also fires on a hit into an already-reeling
# opponent. Only "route probe" sessions are read; the older "dash probe"
# format has no $38 and no defender columns.
#
# The probe writes a line only when a watched byte changed, so a value that is
# absent was held - the reader carries it forward.
#
# CAVEAT, and it is the reason the result is provisional: routeProbe runs on
# emu.registerbefore, which sees DRAWN frames only. At turbo 3 the game runs
# 4 ticks per 3 drawn frames, so roughly one tick in four is never sampled. A
# contact whose hitstop rises and is consumed inside a missed tick is invisible
# here, and a contact seen here may be recorded one tick late.
import re
import sys
import hashlib
import collections

LOG = "analysis/dash_probe.log"

KV = re.compile(r"([A-Za-z0-9_]+)=([0-9A-Fa-f]+)")


def sessions(path):
    """Yield (header, [row]) per route-probe session, values carried forward."""
    cur = None
    held = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "=== route probe" in line:
                if cur is not None:
                    yield cur
                cur = (line.strip(), [])
                held = {}
                continue
            if "=== dash probe" in line:
                if cur is not None:
                    yield cur
                cur = None
                continue
            if cur is None or not line.startswith("t="):
                continue
            m = re.match(r"^t=\s*(\d+)\s+(.*)$", line)
            if not m:
                continue
            held = dict(held)
            held["t"] = int(m.group(1))
            for k, v in KV.findall(m.group(2)):
                if k == "t":
                    continue
                held[k] = int(v, 16)
            cur[1].append(held)
    if cur is not None:
        yield cur



# The same rows in the shape V16.1 asks runtime logs to take
# (runtime/RUNTIME_OBSERVATION_SCHEMA.csv). Columns this probe never watched are
# NOT_LOGGED; environment columns the acceptance gate requires but that were
# never recorded for these sessions are UNVERIFIED. Both are left visible on
# purpose - the gate is supposed to reject this log, and it can only do that if
# the gaps are in the file.
SCHEMA = ("schema_version,run_id,test_id,case_id,timestamp_utc,emulator_name,"
          "emulator_version,emulator_binary_sha256,romset,parent_rom_sha256,"
          "target_rom_sha256,savestate_sha256,sequence,frame,hook_semantics,pc,"
          "event,active_player,p1_base,p2_base,p1_04,p1_05,p1_06,p1_07,p1_38,"
          "p1_54,p1_5c,p1_105,p1_140,p1_141,p1_1a4,p2_04,p2_05,p2_06,p2_07,"
          "p2_38,p2_54,p2_5c,p2_105,p2_140,p2_141,p2_1a4,indirect_target,"
          "expected_class,observed_class,case_result,notes").split(",")

NOT_LOGGED = "NOT_LOGGED"
UNVERIFIED = "UNVERIFIED"


def hx(v):
    return NOT_LOGGED if v is None else "0x%02X" % v


def write_csv(path, contacts):
    fixed = {
        "schema_version": "1.0.0",
        "run_id": "RUN-ROUTEPROBE-RETRO-001",
        "test_id": "EVID-RUNTIME-001",
        "emulator_name": "FBNeo (fcadefbneo)",
        "emulator_version": UNVERIFIED,
        "emulator_binary_sha256": UNVERIFIED,
        "romset": "vsavj (970519 Japan)",
        "parent_rom_sha256": UNVERIFIED,
        "target_rom_sha256": UNVERIFIED,
        "savestate_sha256": UNVERIFIED,
        "hook_semantics": "emu.registerbefore (drawn frames only; ~1 tick in 4 unsampled at turbo 3)",
        "pc": NOT_LOGGED,
        "event": "p2_5c_rise",
        "active_player": "P1",
        "p1_base": "0xFF8400",
        "p2_base": "0xFF8800",
        "indirect_target": NOT_LOGGED,
        "case_result": "INCONCLUSIVE",
    }
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(",".join(SCHEMA) + "\n")
        for i, c in enumerate(contacts, 1):
            air = bool(c["p1_38"])
            row = dict(fixed)
            row["case_id"] = "OBS-%03d" % i
            row["timestamp_utc"] = c["session"].replace(
                "=== route probe ", "").replace(" ===", "") + " (local, TZ unrecorded)"
            row["sequence"] = str(i)
            row["frame"] = str(c["t"])
            row["expected_class"] = "AIR_NORMAL_0x0A" if air else "GROUND_NOT_IN_SCOPE"
            row["observed_class"] = "0x%02X" % c["p1_06"]
            who = ("character $382=0x%02X" % c["char"]) if c["char"] is not None                 else "character not recorded by probe"
            row["notes"] = ("attacker airborne" if air else "attacker grounded")                 + "; " + who                 + "; p2_158=" + hx(c["p2_158"])
            for k in SCHEMA:
                if k in row:
                    continue
                row[k] = NOT_LOGGED
            row["p1_04"] = hx(c["p1_04"])
            row["p1_07"] = hx(c["p1_07"])
            row["p1_05"] = hx(c["p1_05"])
            row["p1_06"] = hx(c["p1_06"])
            row["p1_38"] = hx(c["p1_38"])
            row["p1_105"] = hx(c["p1_105"])
            row["p2_05"] = hx(c["p2_05"])
            row["p2_5c"] = hx(c["p2_5C"])
            row["p2_140"] = hx(c["p2_140"])
            fh.write(",".join(
                '"%s"' % row[k] if ("," in row[k]) else row[k]
                for k in SCHEMA) + "\n")
    print("CSV -> %s" % path)


def main():
    total = collections.Counter()
    air_total = collections.Counter()
    contacts = []
    for header, rows in sessions(LOG):
        prev = None
        for r in rows:
            hs = r.get("p2_5C", 0)
            if prev is not None and prev.get("p2_5C", 0) == 0 and hs != 0:
                rec = {
                    "session": header,
                    "t": r["t"],
                    "p1_04": r.get("p1_04"),
                    "p1_07": r.get("p1_07"),
                    "char": r.get("char"),
                    "p1_05": r.get("p1_05"),
                    "p1_06": r.get("p1_06"),
                    "p1_38": r.get("air"),
                    "p1_105": r.get("105"),
                    "p2_05": r.get("p2_05"),
                    "p2_5C": hs,
                    "p2_158": r.get("p2_158"),
                    "p2_140": r.get("p2_140"),
                    "box": r.get("box"),
                }
                contacts.append(rec)
                total[rec["p1_06"]] += 1
                if rec["p1_38"]:
                    air_total[rec["p1_06"]] += 1
            prev = r

    with open(LOG, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    print("%s  sha256=%s" % (LOG, digest))
    print("接触ティック総数: %d  うち攻撃側空中 ($38!=0): %d"
          % (len(contacts), sum(air_total.values())))
    print()
    print("  %-21s %-5s %-4s %-4s %-4s %-4s %-4s %-5s %-5s %-5s %-5s %-5s" %
          ("session", "t", "char", "$04", "$05", "$06", "$07", "p1_38",
           "p1_105", "p2_5C", "p2_140", "p2_158"))
    for c in contacts:
        def h(v):
            return "--" if v is None else ("%02X" % v)
        print("  %-21s %-5d %-4s %-4s %-4s %-4s %-4s %-4s %-5s %-5s %-5s %-5s" % (
            c["session"].replace("=== route probe ", "").replace(" ===", ""),
            c["t"], h(c["char"]), h(c["p1_04"]), h(c["p1_05"]), h(c["p1_06"]),
            h(c["p1_07"]), h(c["p1_38"]), h(c["p1_105"]),
            h(c["p2_5C"]), h(c["p2_140"]), h(c["p2_158"])))
    print()
    for arg in sys.argv[1:]:
        if arg.startswith("--csv="):
            write_csv(arg[6:], contacts)

    for name, ctr in (("全接触", total), ("空中接触", air_total)):
        parts = ", ".join("$06=0x%02X: %d" % (k, v)
                          for k, v in sorted(ctr.items()))
        print("%s の $06 分布 -> %s" % (name, parts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
