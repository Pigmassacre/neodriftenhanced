"""Dump raw tile sheets (grey ramp, no game palettes) into data/tiles/ for inspection.

Usage: python3 Tools/dump_tiles.py [first_page [page_count]]
Each sprite page holds 1024 tiles (32 x 32 tiles, 512 x 512 px).
"""
import os
import sys

import neogeo

OUT = os.path.join(neogeo.ROOT, "data", "tiles")
PAGE = 1024


def main():
    first = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0
    c1, c2 = neogeo.load_sprites()
    total_pages = neogeo.sprite_tile_count(c1) // PAGE
    count = int(sys.argv[2], 0) if len(sys.argv) > 2 else total_pages - first

    s1 = neogeo.load_fix()
    fix = [neogeo.decode_fix_tile(s1, t) for t in range(len(s1) // 32)]
    neogeo.write_png(os.path.join(OUT, "fix.png"), *neogeo.tile_sheet(fix, 8, 64))

    for page in range(first, min(first + count, total_pages)):
        tiles = [neogeo.decode_sprite_tile(c1, c2, page * PAGE + t) for t in range(PAGE)]
        if not any(any(t) for t in tiles):
            continue
        name = "spr_%02d_%05x.png" % (page, page * PAGE)
        neogeo.write_png(os.path.join(OUT, name), *neogeo.tile_sheet(tiles, 16, 32))
        print(name)


if __name__ == "__main__":
    main()
