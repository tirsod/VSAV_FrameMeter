"""
Static-analysis toolkit for the Vampire Savior (vsavj) 68000 program ROM.

Input: the MAME `dasm` dumps in mame_code/ (real, CPS2-decrypted opcodes -
a plain byte read of the ROM will NOT decode correctly, so these dumps are
the only usable source).

Provides:
  * a byte-accurate image of 0x000000-0x3FFFFF rebuilt from the dumps
  * the disassembly text keyed by address
  * a resolver for the engine's universal PC-relative jump-table dispatch
  * helpers to list which code touches a given player-object field

THE DISPATCH IDIOM (used everywhere for state machines):

    move.b  ($NN,A6), D0        ; NN = state field, usually $6 or $7
    move.w  ($6,PC,D0.w), D1    ; table lookup, base = addr_of_movew + 8
    jmp     ($2,PC,D1.w)        ; target = addr_of_jmp + 4 + D1

State values step in 2s (the engine advances them with `addq.b #2`), so a
table entry sits at base + state_value.
"""
import os
import re
import glob

CODE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mame_code")

_LINE = re.compile(r'^([0-9A-F]{6}):\s+((?:[0-9A-F]{4}\s)+)\s*(.*)$')


ROM_ZIP = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "mame_roms", "vsavj.zip")
PRG_PARTS = ["vm3j.03d", "vm3j.04d", "vm3j.05a", "vm3j.06b",
             "vm3j.07b", "vm3j.08a", "vm3j.09b", "vm3j.10b"]


class Rom:
    """Two views of the same 4MB program ROM, because CPS2 needs both.

    self.mem  - DECRYPTED OPCODES, rebuilt from MAME's `dasm` output. Correct
                for instructions. Meaningless for data.
    self.data - RAW ROM as the 68000 sees it on a DATA read: the eight 512KB
                parts concatenated in load order, then byte-swapped. Correct
                for tables. Meaningless as instructions.

    CPS2 decrypts on the opcode-fetch path only, so tables stored in the same
    ROM are plaintext while the code around them is not. Reading a table out
    of the decrypted image silently yields garbage - that mistake is why the
    character handler table looked like nonsense at first.

    Verified: data[0xBD47A + 4*4] == 0x00024EA4, which is the knockdown
    wake-up dispatcher independently derived from the disassembly.
    """

    def __init__(self, code_dir=CODE_DIR, rom_zip=ROM_ZIP):
        self.mem = bytearray(0x400000)
        self.have = bytearray(0x400000)   # 1 where we actually have data
        self.text = {}                    # addr -> mnemonic text
        self.data = b""                   # raw (data-view) image
        self._load(code_dir)
        self._load_raw(rom_zip)

    def _load_raw(self, rom_zip):
        try:
            import zipfile
            with zipfile.ZipFile(rom_zip) as z:
                have = set(z.namelist())
                if not all(n in have for n in PRG_PARTS):
                    return
                cat = b"".join(z.read(n) for n in PRG_PARTS)
            self.data = bytes(b for pair in zip(cat[1::2], cat[0::2]) for b in pair)
        except Exception:
            self.data = b""

    # ---- data-view reads (tables) ---------------------------------------
    def d8(self, a):
        return self.data[a]

    def d16(self, a):
        return (self.data[a] << 8) | self.data[a + 1]

    def ds16(self, a):
        v = self.d16(a)
        return v - 0x10000 if v & 0x8000 else v

    def d32(self, a):
        return (self.d16(a) << 16) | self.d16(a + 2)

    def _load(self, code_dir):
        for path in sorted(glob.glob(os.path.join(code_dir, "*.txt"))):
            with open(path, encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    m = _LINE.match(line.rstrip('\n'))
                    if not m:
                        continue
                    addr = int(m.group(1), 16)
                    words = m.group(2).split()
                    if addr >= len(self.mem):
                        continue
                    for i, w in enumerate(words):
                        v = int(w, 16)
                        off = addr + i * 2
                        if off + 1 < len(self.mem):
                            self.mem[off] = (v >> 8) & 0xFF
                            self.mem[off + 1] = v & 0xFF
                            self.have[off] = 1
                            self.have[off + 1] = 1
                    self.text[addr] = m.group(3).strip()

    # ---- primitive reads -------------------------------------------------
    def u8(self, a):
        return self.mem[a]

    def u16(self, a):
        return (self.mem[a] << 8) | self.mem[a + 1]

    def s16(self, a):
        v = self.u16(a)
        return v - 0x10000 if v & 0x8000 else v

    def u32(self, a):
        return (self.u16(a) << 16) | self.u16(a + 2)

    def coverage(self):
        return sum(self.have) // 2, len(self.have) // 2


# --------------------------------------------------------------------------
# Dispatch-table resolution
# --------------------------------------------------------------------------

# move.b ($NN,A6), D0   =  102E 00NN
_MOVEB_A6_D0 = 0x102E
# move.w ($6,PC,D0.w), D1  =  323B 0006
_MOVEW_PCD0_D1 = (0x323B, 0x0006)
# jmp ($2,PC,D1.w)  =  4EFB 1002
_JMP_PCD1 = (0x4EFB, 0x1002)


def find_dispatchers(rom):
    """Locate every `state-field -> jump table` dispatcher in the image.

    Returns a list of dicts: {at, field, table, jmp_at}
    """
    out = []
    a = 0
    end = len(rom.mem) - 16
    while a < end:
        if rom.u16(a) == _MOVEB_A6_D0:
            field = rom.u16(a + 2)
            b = a + 4
            if (rom.u16(b), rom.u16(b + 2)) == _MOVEW_PCD0_D1:
                c = b + 4
                if (rom.u16(c), rom.u16(c + 2)) == _JMP_PCD1:
                    out.append({
                        'at': a,
                        'field': field,
                        'table': b + 8,     # base for the word lookup
                        'jmp_at': c,
                        'target_base': c + 4,
                    })
                    a = c + 4
                    continue
        a += 2
    return out


def resolve_states(rom, disp, max_states=24):
    """Walk a dispatcher's table and return [(state_value, target_addr), ...].

    The table sits immediately after the dispatch code, so the first table
    entry's own target tells us where the table ends: entries stop once a
    computed target would fall inside the table itself, or once the target
    leaves the plausible code range.
    """
    entries = []
    base = disp['table']
    tbase = disp['target_base']
    limit = None
    for i in range(max_states):
        ea = base + i * 2
        d1 = rom.u16(ea)
        target = (tbase + d1) & 0xFFFFFF
        if limit is not None and ea >= limit:
            break
        if target <= base or target >= 0x400000 or not rom.have[target]:
            break
        # first resolved target bounds the table
        if limit is None:
            limit = target
        entries.append((i * 2, target))
    return entries


# --------------------------------------------------------------------------
# Field cross-reference
# --------------------------------------------------------------------------

def xref_field(rom, offset, regs=('A6',)):
    """Every disassembled line that touches ($offset,Areg)."""
    pats = [f'(${offset:x},{r})' for r in regs]
    hits = []
    for addr, txt in rom.text.items():
        for p in pats:
            if p in txt:
                hits.append((addr, txt))
                break
    hits.sort()
    return hits


def listing(rom, start, count):
    """Linear listing helper."""
    out = []
    a = start
    while a < start + count:
        t = rom.text.get(a)
        if t is None:
            a += 2
            continue
        out.append((a, t))
        a += 2
    return out


if __name__ == "__main__":
    rom = Rom()
    have, total = rom.coverage()
    print(f"image: {have}/{total} words present ({100.0*have/total:.1f}%)")
    d = find_dispatchers(rom)
    print(f"dispatchers found: {len(d)}")
    from collections import Counter
    c = Counter(x['field'] for x in d)
    print("dispatch field frequency:")
    for f, n in c.most_common(12):
        print(f"   (${f:03x},A6): {n}")
