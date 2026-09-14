"""Read raw ROM bytes out of the MAME disassembly listings.

The ROM itself is only on disk as an encrypted CPS2 zip, so the bytes cannot be
read from it directly. The listings in mame_code/ are post-decryption and carry
the hex for every word alongside the mnemonic, so they are usable as a ROM
image even where the disassembler guessed wrong and printed nonsense - a data
table shows up as garbage instructions, but its HEX is still correct.

    from rom import ROM
    r = ROM()
    r.word(0x0BD47A)          # one 16-bit word
    r.long(0x0BD47A)          # one 32-bit long
    r.bytes(0x0BD47A, 64)     # raw bytes

Ranges are loaded lazily per listing file and cached, because the full set is
74 MB and a single question usually touches one bank.
"""
import glob
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CODE = os.path.join(HERE, "mame_code")

# "0283C4: 7488                moveq   #-$78, D2"  ->  addr, "7488"
# "024E44: 2D7C 0202 0400 0004 move.l  ..."        ->  addr, "2D7C 0202 0400 0004"
_LINE = re.compile(r'^([0-9A-F]{6}):\s+((?:[0-9A-F]{4} )*[0-9A-F]{4})\s')


class ROM(object):
    def __init__(self, code_dir=CODE):
        self._files = sorted(glob.glob(os.path.join(code_dir, "*.txt")))
        self._ranges = []      # (lo, hi, path), filled on first use
        self._loaded = {}      # path -> {addr: byte}
        self._index()

    def _index(self):
        """Cheap first/last address per file so a lookup knows what to load."""
        for path in self._files:
            lo = hi = None
            with open(path, encoding='utf-8', errors='replace') as fh:
                for ln in fh:
                    m = _LINE.match(ln)
                    if not m:
                        continue
                    a = int(m.group(1), 16)
                    if lo is None:
                        lo = a
                    hi = a
            if lo is not None:
                self._ranges.append((lo, hi, path))

    def _load(self, path):
        if path in self._loaded:
            return self._loaded[path]
        mem = {}
        with open(path, encoding='utf-8', errors='replace') as fh:
            for ln in fh:
                m = _LINE.match(ln)
                if not m:
                    continue
                a = int(m.group(1), 16)
                for w in m.group(2).split():
                    v = int(w, 16)
                    mem[a] = (v >> 8) & 0xFF
                    mem[a + 1] = v & 0xFF
                    a += 2
        self._loaded[path] = mem
        return mem

    def _mem_for(self, addr):
        for lo, hi, path in self._ranges:
            if lo <= addr <= hi + 2:
                return self._load(path)
        raise KeyError("0x%06X はどの逆アセンブルにも含まれない" % addr)

    def byte(self, addr):
        return self._mem_for(addr)[addr]

    def bytes(self, addr, n):
        mem = self._mem_for(addr)
        return bytes(bytearray(mem[addr + i] for i in range(n)))

    def word(self, addr):
        b = self.bytes(addr, 2)
        return (b[0] << 8) | b[1]

    def sword(self, addr):
        v = self.word(addr)
        return v - 0x10000 if v >= 0x8000 else v

    def long(self, addr):
        b = self.bytes(addr, 4)
        return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]

    def hexdump(self, addr, n, width=16):
        out = []
        data = self.bytes(addr, n)
        for i in range(0, n, width):
            chunk = data[i:i + width]
            out.append("%06X: %s" % (addr + i,
                       " ".join("%02X" % c for c in bytearray(chunk))))
        return "\n".join(out)
