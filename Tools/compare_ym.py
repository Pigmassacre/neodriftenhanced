"""Compare sound chip register writes.

Usage: Tools/compare_ym.py <mame_ymlog.txt> <godot_ymlog.txt> [first_frame]

Give first_frame to start after a driver reset (command 03), so that both
sides start from the same state.

Timer control writes (port A register 27) are left out: how many of them
fall between two other writes depends on timer phase. Everything else is
compared in order. When both logs carry times (fifth column, seconds), the
script also reports how far apart in time the matching writes are.
"""
import difflib
import sys


def load(path, first):
    out = []
    for line in open(path):
        p = line.split()
        if len(p) >= 4 and int(p[0]) >= first and p[1] in "AB" and not (p[1] == "A" and p[2] == "27"):
            out.append((int(p[0]), p[1], p[2], p[3], float(p[4]) if len(p) > 4 else None))
    return out


def main():
    first = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    a, b = load(sys.argv[1], first), load(sys.argv[2], first)
    # The two sides can differ by a driver tick between commands, which
    # repeats or drops a group of writes; align the streams and report
    # what is left unmatched on either side.
    left = [x[1:4] for x in a]
    right = [x[1:4] for x in b]
    matcher = difflib.SequenceMatcher(None, left, right, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    print("mame %d writes, godot %d; %d match in order" % (len(a), len(b), matched))
    apart = sorted(abs(a[block.a + k][4] - b[block.b + k][4]) for block in matcher.get_matching_blocks()
                   for k in range(block.size) if a[block.a + k][4] is not None and b[block.b + k][4] is not None)
    if apart:
        print("matching writes are %.2f ms apart at the median, %.2f ms at most"
              % (apart[len(apart) // 2] * 1000, apart[-1] * 1000))
    shown = 0
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            continue
        shown += 1
        if shown > 12:
            print("  ...")
            break
        only_mame = " ".join("%s:%s=%s" % x for x in left[i1:i2][:6])
        only_godot = " ".join("%s:%s=%s" % x for x in right[j1:j2][:6])
        frame = a[i1][0] if i1 < len(a) else b[j1][0] if j1 < len(b) else -1
        print("  frame %5d  only mame [%s]  only godot [%s]" % (frame, only_mame, only_godot))


if __name__ == "__main__":
    main()
