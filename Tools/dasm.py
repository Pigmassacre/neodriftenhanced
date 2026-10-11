"""Print a range of the MAME-generated disassembly: Tools/dasm.py <start> <end> (hex)."""
import bisect
import os
import sys

PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "dasm", "p1.asm")


def main():
    start, end = int(sys.argv[1], 16), int(sys.argv[2], 16)
    with open(PATH) as f:
        lines = f.readlines()
    addrs = [int(l[:6], 16) for l in lines]
    for l in lines[bisect.bisect_left(addrs, start):bisect.bisect_left(addrs, end)]:
        sys.stdout.write(l[:8] + l[33:])


if __name__ == "__main__":
    main()
