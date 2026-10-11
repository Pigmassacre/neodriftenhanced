"""Compare a Godot replay RAM log with MAME's.

Usage: python3 Tools/compare_ram.py <mame_ramlog.bin> <godot_ramlog.bin> [mame_offset]

Both hold 64K of work RAM per frame. Godot's first record is the state one
frame after the snapshot, so mame_offset (default 1) is the index of the
matching MAME record.
"""
import sys

FRAME = 0x10000
# The random seed is stepped in the idle loop, so its end-of-frame value
# depends on exact CPU timing; replays sync it from MAME instead.
# Also ignored: the area below the main loop's stack pointer ($10F300). It
# only holds dead leftovers of calls and interrupts, which land at different
# moments here than in MAME.
IGNORE = (0x430, 0x431) + tuple(range(0xf000, 0xf300))


def main():
    mame = open(sys.argv[1], "rb").read()
    godot = open(sys.argv[2], "rb").read()
    offset = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    frames = min(len(godot) // FRAME, len(mame) // FRAME - offset)
    exact = 0
    first = None
    for i in range(frames):
        a = bytearray(mame[(i + offset) * FRAME:(i + offset + 1) * FRAME])
        b = bytearray(godot[i * FRAME:(i + 1) * FRAME])
        for o in IGNORE:
            a[o] = b[o] = 0
        if a == b:
            exact += 1
            continue
        if first is None:
            first = i
            diff = [o for o in range(FRAME) if a[o] != b[o]]
            print("first difference at replay frame %d: %d bytes differ" % (i, len(diff)))
            for o in diff[:24]:
                print("  %04X: mame %02X godot %02X" % (o, a[o], b[o]))
    print("%d of %d frames identical" % (exact, frames))


if __name__ == "__main__":
    main()
