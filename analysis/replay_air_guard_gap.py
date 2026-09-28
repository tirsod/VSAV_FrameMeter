"""Replay airGuardLog.lua's recordings through scripts/airGuardGap.lua.

Both subscribe to the same tick, so the bytes in an airg_sNN.json are exactly
what airGuardGap.lua's on_tick read on the machine. This feeds them back in
and prints the lines it would have drawn - the screen, reproduced offline.

    python replay_air_guard_gap.py            # every airg_s*.json
    python replay_air_guard_gap.py 26 19      # just these slots
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from air_guard_report import LOG_DIR, files, load  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# Everything airGuardGap.lua reads, on both objects.
OFFS = [0x05, 0x06, 0x07, 0x38, 0x54, 0x101, 0x102, 0x105, 0x126, 0x1B8, 0x1B9]


def lua_for(path):
    d, fr = load(path)
    out = ["local T = {"]
    # The attack box id is ROM (the cel $1C points at, +0x0A), so the log
    # carries it per row as ab; logs from before 2026-09-27 have none and
    # replay without startups. Each side gets a fake cel holding its id.
    for (_, p1, p2), row in zip(fr, d["rows"]):
        ab = row.get("ab") or [0, 0]
        cells = []
        for i, (base, o) in enumerate(((0xFF8400, p1), (0xFF8800, p2))):
            for off in OFFS:
                cells.append("[%d]=%d" % (base + off, o[off]))
            cel = 0x100000 + i * 0x100
            cells.append("[%d]=%d" % (base + 0x1C, cel))
            cells.append("[%d]=%d" % (cel + 0x0A, ab[i]))
        out.append("{" + ",".join(cells) + "},")
    out.append("}")
    return "\n".join(out)


HARNESS = r"""
local ram = {}
memory = {
	readbyte = function(a) return ram[a] or 0 end,
	readword = function(a) return (ram[a] or 0) * 256 + (ram[a + 1] or 0) end,
	-- $1C is written whole by the replay; only the fake cel is ever read.
	readdword = function(a) return ram[a] or 0 end,
}
globals = { options = { display_air_guard_gap = true } }
local M = dofile("scripts/airGuardGap.lua")
for _, t in ipairs(T) do
	for a, v in pairs(t) do ram[a] = v end
	M.on_tick()
end
for _, l in ipairs(M.text()) do print(l) end
"""


def main():
    lua = shutil.which("lua5.1") or shutil.which("lua")
    want = set(int(a) for a in sys.argv[1:])
    for p in files():
        slot = int(os.path.basename(p)[6:8])
        if want and slot not in want:
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as fh:
            fh.write(lua_for(p) + HARNESS)
            tmp = fh.name
        try:
            r = subprocess.run([lua, tmp], cwd=ROOT, capture_output=True, text=True,
                               encoding="utf-8", errors="replace")
        finally:
            os.unlink(tmp)
        print("== %s" % os.path.basename(p))
        print(r.stdout.rstrip() or r.stderr.strip())


if __name__ == "__main__":
    main()
