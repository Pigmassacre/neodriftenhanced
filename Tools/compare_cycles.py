"""Compare MAME's time for each instruction with the recompiler's timing tables.

Usage: python3 Tools/compare_cycles.py <cputrace.log> [name ...]

The trace comes from a harness job with `cputrace` (see mame/harness.lua):
each line starts with the CPU's cycle count. For every kind of instruction
(name, size, operand kinds) this prints how many cycles MAME took beyond
`cycles()` in recomp/gen.py, with counts. Kinds whose time depends on run
time values (taken branches, shifts by a register, multiply, divide) show
the extra the generated code adds itself; anything else that is not zero is
a mistake in the tables. With names, every such instruction is listed.

       python3 Tools/compare_cycles.py <cputrace.log> --port <cycles.txt> <snapshot frame>

compares when things happen within each frame instead: `cycles.txt` is the
port's block trace for the same frames (`--cycles` of Project/tools/replay.gd),
and the times printed are cycles since the frame began. MAME's count is 3
ahead of the port's.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "recomp"))

import gen
import m68k
import neogeo

LINE = re.compile(r"^(\d+) ([0-9A-F]{6}): (.*)")


FRAME_CYCLES = 202752
# Where the two interrupt handlers start and end, the main loop leaves its wait
# for the vertical blank, and the raster interrupt has waited for its line.
EVENTS = (("vblank irq", 0x22c), ("its end", 0x2a4), ("wait left", 0xb80), ("raster irq", 0x2aa),
          ("line reached", 0x136ea), ("its end", 0x2bc))


def frame_events(entries, first_frame):
    """{frame: {event: (cycles into the frame, previous address, cycles since it)}}"""
    frames = {}
    for i, (pc, now) in enumerate(entries):
        events = frames.setdefault(first_frame + now // FRAME_CYCLES, {})
        for name, address in EVENTS:
            if pc == address and (name, address) not in events:
                events[(name, address)] = (now % FRAME_CYCLES, entries[i - 1][0], now - entries[i - 1][1])
    return frames


def compare_events(trace_path, port_path, snapshot_frame):
    mame = []
    with open(trace_path) as f:
        for line in f:
            match = LINE.match(line)
            if match:
                mame.append((int(match.group(2), 16), int(match.group(1))))
    with open(port_path) as f:
        port = [(int(pc, 16), int(now)) for pc, now in (line.split() for line in f)]
    ours = frame_events(port, snapshot_frame)
    theirs = frame_events(mame, 0)
    for frame in sorted(set(ours) & set(theirs)):
        print("frame %d" % frame)
        for key in EVENTS:
            a, b = theirs[frame].get(key), ours[frame].get(key)
            if a and b:
                print("  %-12s mame %6d after %06X+%-3d  port %6d after %06X+%-3d  %+d"
                      % (key[0], a[0], a[1], a[2], b[0], b[1], b[2], b[0] - a[0]))


def main():
    if len(sys.argv) > 2 and sys.argv[2] == "--port":
        compare_events(sys.argv[1], sys.argv[3], int(sys.argv[4]))
        return
    rom = neogeo.load_program()
    with open(os.path.join(neogeo.ROOT, "neogeo", "sp-s2.sp1"), "rb") as f:
        bios = bytearray(f.read())
    bios[0::2], bios[1::2] = bios[1::2], bios[0::2]

    def fetch16(addr):
        if addr < 0x100000:
            data, o = rom, addr
        elif 0x200000 <= addr < 0x300000:
            data, o = rom, addr - 0x100000
        else:
            data, o = bios, addr & 0x1ffff
        return (data[o] << 8) | data[o + 1]

    wanted = set(sys.argv[2:])
    kinds = collections.defaultdict(collections.Counter)
    previous = None
    with open(sys.argv[1]) as f:
        for line in f:
            match = LINE.match(line)
            if not match:
                if "interrupted" in line:
                    previous = None
                continue
            now, pc = int(match.group(1)), int(match.group(2), 16)
            if previous is not None:
                then, at, text = previous
                ins = m68k.decode(fetch16, at)
                kind = "%s.%d %s,%s" % (ins.name, ins.size, ins.src[0] if ins.src else "-",
                                        ins.dst[0] if ins.dst else "-")
                extra = now - then - gen.cycles(ins)
                kinds[kind][extra] += 1
                if ins.name in wanted and extra:
                    print("%06X %-40s %+d" % (at, text, extra))
            previous = (now, pc, match.group(3))
    for kind in sorted(kinds):
        if set(kinds[kind]) != {0}:
            print("%-32s %s" % (kind, "  ".join("%+d: %d" % item for item in sorted(kinds[kind].items()))))


if __name__ == "__main__":
    main()
