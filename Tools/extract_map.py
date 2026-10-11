"""Extract a course tilemap from the program ROM.

Usage: python3 Tools/extract_map.py <map_header_addr> <block_table_addr> <name> [palette_dump.bin]

The course is a grid of blocks, each 16x16 tiles, stored column-major as
(tile word, attribute word) pairs. Output data/maps/<name>.bin holds
width/height in tiles followed by tile and attribute words, row-major.
With a state dump for palettes, also writes a 1/8-scale preview PNG.
"""
import os
import struct
import sys

import neogeo

BLOCK = 16


def read_map(rom, header, table):
    header, table = neogeo.rom_offset(header), neogeo.rom_offset(table)
    bw, bh = struct.unpack_from(">HH", rom, header)
    index = struct.unpack_from(">%dH" % (bw * bh), rom, header + 4)
    count = struct.unpack_from(">H", rom, table)[0]
    blocks = struct.unpack_from(">%dI" % (max(index) + 1), rom, table + 2)
    w, h = bw * BLOCK, bh * BLOCK
    tiles = [0] * (w * h)
    attrs = [0] * (w * h)
    for by in range(bh):
        for bx in range(bw):
            base = neogeo.rom_offset(blocks[index[by * bw + bx]])
            cells = struct.unpack_from(">%dH" % (BLOCK * BLOCK * 2), rom, base)
            for x in range(BLOCK):
                for y in range(BLOCK):
                    o = (y + by * BLOCK) * w + bx * BLOCK + x
                    tiles[o] = cells[(x * BLOCK + y) * 2]
                    attrs[o] = cells[(x * BLOCK + y) * 2 + 1]
    return w, h, tiles, attrs, count


def main():
    header, table, name = int(sys.argv[1], 16), int(sys.argv[2], 16), sys.argv[3]
    rom = neogeo.load_program()
    w, h, tiles, attrs, count = read_map(rom, header, table)
    print("%s: %d x %d tiles, %d block types" % (name, w, h, count))
    out = os.path.join(neogeo.ROOT, "data", "maps")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, name + ".bin"), "wb") as f:
        f.write(struct.pack(">HH", w, h))
        f.write(struct.pack(">%dH" % len(tiles), *tiles))
        f.write(struct.pack(">%dH" % len(attrs), *attrs))
    if len(sys.argv) > 4:
        import render
        d = render.Dump(sys.argv[4])
        pal = [render.colour(c) for c in d.palette]
        c1, c2 = neogeo.load_sprites()
        cache = {}
        # 2x2 pixels per tile: sample the tile at (4,4), (12,4), (4,12), (12,12)
        pw, ph = w * 2, h * 2
        px = [(0, 0, 0)] * (pw * ph)
        for ty in range(h):
            for tx in range(w):
                t, a = tiles[ty * w + tx], attrs[ty * w + tx]
                code = (t | (a << 12 & 0xf0000)) & 0xffff
                if code not in cache:
                    cache[code] = neogeo.decode_sprite_tile(c1, c2, code)
                pix = cache[code]
                for sy in (0, 1):
                    for sx in (0, 1):
                        x, y = 4 + sx * 8, 4 + sy * 8
                        if a & 1:
                            x = 15 - x
                        if a & 2:
                            y = 15 - y
                        px[(ty * 2 + sy) * pw + tx * 2 + sx] = pal[(a >> 8) * 16 + pix[y * 16 + x]]
        render.write_rgb_png(os.path.join(out, name + "_preview.png"), pw, ph, px)
        print("preview %d x %d" % (pw, ph))


if __name__ == "__main__":
    main()
