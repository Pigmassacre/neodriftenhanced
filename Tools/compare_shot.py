"""Pixel-compare two 320x224 screenshots: Tools/compare_shot.py <a.png> <b.png>"""
import sys

import render


def main():
    wa, ha, a = render.read_png(sys.argv[1])
    wb, hb, b = render.read_png(sys.argv[2])
    assert (wa, ha) == (wb, hb), ((wa, ha), (wb, hb))
    rows = [sum(1 for x in range(wa) if a[y * wa + x] != b[y * wa + x]) for y in range(ha)]
    bad = [y for y, n in enumerate(rows) if n]
    print("%d of %d pixels differ" % (sum(rows), wa * ha)
          + (" (rows %d-%d)" % (bad[0], bad[-1]) if bad else ""))


if __name__ == "__main__":
    main()
