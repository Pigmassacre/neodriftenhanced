"""List the game program's routines, for planning the decompilation.

Usage: python3 Tools/routines.py [--top N] [--routine ADDR]

Combines the recompiler's static analysis with the block profiles that
`verify_session.py <session> --profile` writes (data/verify/*/profile.txt):
a routine starts wherever a call landed, and consists of the blocks reached
from there without calling or entering another routine.

Writes data/game/routines.txt, one line per routine that ran:
  address, instructions, calls, share of all CPU time spent in its own code,
  routines it calls, routines that call it, and "hand" if Project/game/
  already replaces it.
--routine prints one routine's blocks and its listing instead.
"""
import argparse
import glob
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "recomp"))

import build_code
import gen
import neogeo

OUT = os.path.join(neogeo.ROOT, "data", "game", "routines.txt")
HAND = os.path.join(neogeo.ROOT, "Project", "game")


def load_profiles():
    blocks, edges = {}, {}
    for path in glob.glob(os.path.join(neogeo.ROOT, "data", "verify", "*", "profile.txt")):
        with open(path) as f:
            for line in f:
                parts = line.split()
                if parts[0] == "B":
                    a = int(parts[1], 16)
                    blocks[a] = blocks.get(a, 0) + int(parts[2])
                else:
                    e = (int(parts[1], 16), int(parts[2], 16))
                    edges[e] = edges.get(e, 0) + int(parts[3])
    return blocks, edges


def hand_written():
    """Addresses that Project/game/ replaces: `0xADDR: name,` entries of its routine tables."""
    found = {}
    for path in glob.glob(os.path.join(HAND, "*.gd")):
        with open(path) as f:
            for m in re.finditer(r"^\t\t0x([0-9A-Fa-f]+): (\w+),", f.read(), re.M):
                found[int(m.group(1), 16)] = m.group(2)
    return found


def operand(ea):
    if ea is None:
        return None
    kind = ea[0]
    if kind in ("d", "a"):
        return "%s%d" % (kind.upper(), ea[1])
    if kind == "ind":
        return "(A%d)" % ea[1]
    if kind == "pi":
        return "(A%d)+" % ea[1]
    if kind == "pd":
        return "-(A%d)" % ea[1]
    if kind == "disp":
        return "(%s$%X,A%d)" % ("-" if ea[2] < 0 else "", abs(ea[2]), ea[1])
    if kind == "idx":
        return "(%d,A%d,%s%d.%s)" % (ea[2], ea[1], ea[3].upper(), ea[4], "l" if ea[5] else "w")
    if kind == "pcidx":
        return "($%X,PC,%s%d.%s)" % (ea[1] + ea[2], ea[3].upper(), ea[4], "l" if ea[5] else "w")
    if kind == "abs":
        return "$%X" % ea[1]
    if kind == "imm":
        return "#$%X" % ea[1]
    return repr(ea)


def listing(ins):
    """One instruction as text, from the recompiler's own decoder."""
    name = ins.name
    if name == "bcc":
        name = "b" + ins.aux
    elif name in ("dbcc", "scc"):
        name = name[:-2] + str(ins.aux)
    elif ins.size:
        name += "." + {1: "b", 2: "w", 4: "l"}[ins.size]
    parts = [operand(ins.src), operand(ins.dst)]
    if ins.name.startswith("movem"):
        parts.append("mask $%04X" % ins.aux)
    elif ins.aux is not None and ins.name not in ("bcc", "dbcc", "scc"):
        parts.append(repr(ins.aux))
    if ins.target is not None and ins.flow != "call" and ins.flow != "jump":
        parts.append("$%X" % ins.target)
    return "%06X: %-8s %s" % (ins.addr, name, ", ".join(p for p in parts if p))


class Routine:
    def __init__(self, entry):
        self.entry = entry
        self.blocks = []
        self.calls = 0
        self.callees = set()
        self.callers = set()
        self.tail = set()
        self.cycles = 0
        self.instructions = 0


def find_routines(program, counts, edges):
    last = {a: (b.instrs[-1] if b.instrs else None) for a, b in program.blocks.items()}
    entries = {}
    jumps = {}
    for (src, dst), n in edges.items():
        ins = last.get(src)
        if ins is None:
            continue
        if ins.flow == "call" and (ins.target is None or ins.target == dst):
            entries.setdefault(dst, {})[src] = n
        elif ins.flow != "return":
            jumps.setdefault(src, set()).add(dst)
    owner = {}
    routines = {}
    for entry in sorted(entries):
        r = routines[entry] = Routine(entry)
        r.calls = sum(entries[entry].values())
        work, seen = [entry], {entry}
        while work:
            a = work.pop()
            b = program.blocks.get(a)
            if b is None or not b.instrs:
                continue
            r.blocks.append(a)
            owner.setdefault(a, entry)
            r.instructions += len(b.instrs)
            r.cycles += counts.get(a, 0) * sum(gen.cycles(i) or 0 for i in b.instrs)
            ins = last[a]
            # where the code can go, whether or not it ever did
            nxt = set(jumps.get(a, ()))
            if ins.flow == "call":
                nxt = {b.next}
            elif ins.flow in ("next", "cbranch", "branch", "jump"):
                nxt.update(t for t in b.succ if t in program.blocks)
            for d in nxt:
                if d in entries and d != entry:
                    r.tail.add(d)
                elif d not in seen:
                    seen.add(d)
                    work.append(d)
        r.blocks.sort()
    calls_from = {}
    for dst, sources in entries.items():
        for src in sources:
            calls_from.setdefault(src, set()).add(dst)
    for r in routines.values():
        for a in r.blocks:
            r.callees.update(calls_from.get(a, ()))
        r.callees.update(r.tail)
    for r in routines.values():
        for c in r.callees:
            if c in routines:
                routines[c].callers.add(r.entry)
    return routines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=30)
    parser.add_argument("--routine")
    args = parser.parse_args()
    counts, edges = load_profiles()
    if not counts:
        sys.exit("no profiles: run verify_session.py <session> --keep-recording --profile")
    program, _ = build_code.analyse()
    routines = find_routines(program, counts, edges)
    if args.routine:
        r = routines[int(args.routine, 16)]
        print("%06X: %d instructions, called %d times" % (r.entry, r.instructions, r.calls))
        print("calls:", " ".join("%06X" % c for c in sorted(r.callees)))
        print("called by:", " ".join("%06X" % c for c in sorted(r.callers)))
        for a in r.blocks:
            print("; ran %d times" % counts.get(a, 0))
            for ins in program.blocks[a].instrs:
                print(listing(ins))
        return
    hand = hand_written()
    total = sum(r.cycles for r in routines.values()) or 1
    with open(OUT, "w") as f:
        f.write("# address instructions calls time%% | calls | called by\n")
        for r in sorted(routines.values(), key=lambda r: r.entry):
            f.write("%06X %5d %9d %5.2f%s | %s | %s\n" % (
                r.entry, r.instructions, r.calls, 100.0 * r.cycles / total,
                " hand " + hand[r.entry] if r.entry in hand else "",
                " ".join("%06X" % c for c in sorted(r.callees)),
                " ".join("%06X" % c for c in sorted(r.callers))))
    game = [r for r in routines.values() if r.entry < 0x100000]
    done = [r for r in game if r.entry in hand]
    print("%d routines ran (%d in the BIOS), %d instructions in the game's"
          % (len(routines), len(routines) - len(game), sum(r.instructions for r in game)))
    print("hand-written: %d routines, %d instructions, %.1f%% of the CPU time"
          % (len(done), sum(r.instructions for r in done), 100.0 * sum(r.cycles for r in done) / total))
    print("the %d that take the most time:" % args.top)
    for r in sorted(routines.values(), key=lambda r: -r.cycles)[:args.top]:
        print("  %06X %5d instr %9d calls %5.1f%% %s%s" % (
            r.entry, r.instructions, r.calls, 100.0 * r.cycles / total,
            "leaf" if not r.callees else "%d callees" % len(r.callees),
            "  hand" if r.entry in hand else ""))
    print("written to", OUT)


if __name__ == "__main__":
    main()
