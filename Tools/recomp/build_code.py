"""Recompile the game program (and the BIOS routines it uses) to GDScript.

Usage: python3 Tools/recomp/build_code.py [cputrace.log ...]

Output goes to data/game/code/, which is not checked in: it is derived from
the ROMs. Entry points come from the vector tables, the cartridge header,
the BIOS call table, data/game/seeds.txt (one hex address per line; the
runtime reports addresses it could not find) and any instruction traces
given on the command line.
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import gen
import m68k
import neogeo

OUT = os.path.join(neogeo.ROOT, "data", "game", "code")
SEEDS = os.path.join(neogeo.ROOT, "data", "game", "seeds.txt")
BIOS_FILE = os.path.join(neogeo.ROOT, "neogeo", "sp-s2.sp1")
BASE_SCRIPT = "res://machine/neogeo_machine.gd"


def main():
    rom = neogeo.load_program()
    with open(BIOS_FILE, "rb") as f:
        bios = bytearray(f.read())
    bios[0::2], bios[1::2] = bios[1::2], bios[0::2]

    def locate(addr):
        if addr & 1:
            raise m68k.Illegal("odd address")
        if addr < 0x100000:
            return rom, addr
        if 0x200000 <= addr < 0x300000:
            return rom, addr - 0x100000
        if 0xc00000 <= addr < 0xd00000:
            return bios, addr & 0x1ffff
        raise m68k.Illegal("not code: %06X" % addr)

    def fetch16(addr):
        data, o = locate(addr)
        return (data[o] << 8) | data[o + 1]

    def const_read(addr, size):
        # the first 0x80 bytes can be swapped for the BIOS vectors at run time
        if addr < 0x80 or (addr & 1 and size > 1):
            return None
        try:
            data, o = locate(addr & ~1)
        except m68k.Illegal:
            return None
        o += addr & 1
        return int.from_bytes(data[o:o + size], "big")

    def is_ram(addr):
        return 0x100000 <= addr < 0x200000

    def long_at(addr):
        return (fetch16(addr) << 16) | fetch16(addr + 2)

    seeds = set()
    for base in (0, 0xc00000):
        for v in range(8, 0x80, 4):
            target = long_at(base + v) & 0xffffff
            try:
                fetch16(target)
                seeds.add(target)
            except m68k.Illegal:
                pass
    seeds.update((0x122, 0x128, 0x12e, 0x134))
    seeds.update(range(0xc00402, 0xc004d4, 6))
    if os.path.exists(SEEDS):
        with open(SEEDS) as f:
            seeds.update(int(line, 16) for line in f if line.strip())
    traced = set()
    for path in sys.argv[1:]:
        with open(path) as f:
            for line in f:
                m = re.match(r"^([0-9A-F]{6}):", line)
                if m:
                    traced.add(int(m.group(1), 16))

    program = gen.Program(fetch16, const_read, is_ram)
    program.explore(sorted(seeds))
    # Handlers reached only through pointer tables: take every longword in the
    # program ROM that points at something that decodes like code.
    pointed = set()
    for o in range(0, len(rom) - 3, 2):
        v = int.from_bytes(rom[o:o + 4], "big")
        if 0x200 <= v < 0x100000 and not v & 1 and v not in program.instrs and v not in pointed:
            if program.plausible(v):
                pointed.add(v)
    program.explore(sorted(pointed))
    # only look for repeated runs where code has been found, not in the data beyond
    code_end = max(a for a in program.instrs if a < 0x100000)
    program.explore(sorted(program.repeated_runs(0x200, code_end)))
    while True:
        unrolled = program.unrolled_starts()
        if not unrolled:
            break
        program.explore(sorted(unrolled))
    # Traced addresses only matter where static analysis did not reach;
    # making each one a block start would cut the code into single instructions.
    for addr in sorted(traced):
        if addr not in program.instrs:
            seeds.add(addr)
            program.explore([addr])
    program.build_blocks()
    program.liveness()
    files = gen.generate(program, BASE_SCRIPT)

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    for name, source in files.items():
        with open(os.path.join(OUT, name), "w") as f:
            f.write(source)
    return program, seeds, files


def report(program, seeds, files):
    faults = sum(1 for b in program.blocks.values() if b.fault is not None)
    print("%d seeds, %d blocks (%d ending in undecodable code), %d instructions, %d files, %d KB"
          % (len(seeds), len(program.blocks), faults, len(program.instrs), len(files),
             sum(len(s) for s in files.values()) // 1024))


if __name__ == "__main__":
    report(*main())
