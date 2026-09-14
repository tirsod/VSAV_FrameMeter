"""Find locals used before they are declared.

Lua turns an undeclared name into a global read, so a helper placed above the
table it needs compiles cleanly and then fails at runtime:

    guardCancel.lua:694: attempt to index global 'SEQ_LEN' (a nil value)

`luac -p` cannot catch this - the reference is legal syntax. It has now bitten
this project four times (_recovery, _recovery_now, hit_count, SEQ_LEN), every
time costing a test session, so it gets a check of its own.

    python check_lua_scope.py                  # all scripts
    python check_lua_scope.py guardCancel.lua

Run it after every edit that adds or moves a top-level local. It reports the
first use that precedes the declaration; there may be more behind it.

Heuristics, and their limits: names shorter than four characters are skipped
because short identifiers collide with substrings too often, comment lines are
ignored, and a name declared inside a function body is treated as if it were
top level. That makes this a lint, not a proof - a clean run means "nothing
obvious", not "correct".
"""
import glob
import os
import re
import sys

SCRIPTS = r"C:\fightcade\emulator\fbneo\scripts"
DECL = re.compile(r'^\s*local\s+(?:function\s+)?([A-Za-z_]\w*)')
MIN_LEN = 4


def check(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().splitlines()
    first_decl = {}
    for i, line in enumerate(lines):
        m = DECL.match(line)
        if m:
            first_decl.setdefault(m.group(1), i)
    bad = []
    for name, dline in first_decl.items():
        if len(name) < MIN_LEN:
            continue
        pat = re.compile(r'\b%s\b' % re.escape(name))
        for i in range(dline):
            stripped = lines[i].strip()
            if stripped.startswith('--'):
                continue
            if pat.search(lines[i]):
                bad.append((name, i + 1, dline + 1, stripped[:70]))
                break
    return bad


def main():
    targets = sys.argv[1:]
    if not targets:
        targets = sorted(glob.glob(os.path.join(SCRIPTS, "*.lua")))
    else:
        targets = [t if os.path.isabs(t) else os.path.join(SCRIPTS, t)
                   for t in targets]
    total = 0
    for path in targets:
        bad = check(path)
        if not bad:
            continue
        total += len(bad)
        print("\n%s" % os.path.basename(path))
        for name, use, decl, text in bad:
            print("   %-24s %d gyou de shiyou / %d gyou de sengen"
                  % (name, use, decl))
            print("      %s" % text)
    print("\n%s" % ("mondai nashi" if total == 0 else "%d ken" % total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
