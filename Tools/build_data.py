"""Build the runtime data cache in data/ that the Godot project loads.

Usage: python3 Tools/build_data.py <state_dump.bin>

Everything is derived from the ROMs in neodrift/ (and, for now, palettes from
a MAME state dump taken during the practice race). data/ is not checked in.
"""
import os
import struct
import sys

import extract_map
import neogeo
import render

OUT = os.path.join(neogeo.ROOT, "data", "game")

# Practice course: map header and block table (bus addresses).
PRACTICE_MAP = (0x2B464E, 0x2B5E56)


def build_tiles():
    """All sprite tiles as one 4096x4096 8-bit image (256 tiles per row)."""
    c1, c2 = neogeo.load_sprites()
    count = neogeo.sprite_tile_count(c1)
    side = 4096
    sheet = bytearray(side * side)
    for t in range(count):
        pix = neogeo.decode_sprite_tile(c1, c2, t)
        ox, oy = (t & 255) * 16, (t >> 8) * 16
        for y in range(16):
            dst = (oy + y) * side + ox
            sheet[dst:dst + 16] = pix[y * 16:y * 16 + 16]
    with open(os.path.join(OUT, "tiles.bin"), "wb") as f:
        f.write(sheet)


def build_map(name, header, table):
    """Course tilemap as RGBA8: tile low, tile high, flip bits, palette."""
    rom = neogeo.load_program()
    w, h, tiles, attrs, _ = extract_map.read_map(rom, header, table)
    out = bytearray(w * h * 4)
    for i in range(w * h):
        t, a = tiles[i], attrs[i]
        out[i * 4] = t & 255
        out[i * 4 + 1] = t >> 8
        out[i * 4 + 2] = a & 3
        out[i * 4 + 3] = a >> 8
    with open(os.path.join(OUT, name + ".map"), "wb") as f:
        f.write(struct.pack("<II", w, h))
        f.write(out)


def build_palette(name, dump_path):
    """4096 colours as RGBA8 (256 palettes of 16)."""
    d = render.Dump(dump_path)
    out = bytearray()
    for w in d.palette:
        out += bytes(render.colour(w)) + b"\xff"
    with open(os.path.join(OUT, name + ".pal"), "wb") as f:
        f.write(out)


# Background zoom: raster parameters, then per-column shrink and position
# step tables, 32 entries for each of the 16 zoom fractions.
BG_RASTER, BG_SHRINK_STEPS, BG_X_STEPS = 0x296E2, 0x296F2, 0x29AF2


def build_zoom():
    """Vertical shrink table (BIOS LO ROM) and the background zoom tables."""
    with open(os.path.join(OUT, "zoom_y.bin"), "wb") as f:
        f.write(render.load_bios_file("000-lo.lo")[:0x10000])
    rom = neogeo.load_program()
    words = struct.unpack_from(">4h", rom, BG_RASTER) \
        + struct.unpack_from(">512h", rom, BG_SHRINK_STEPS) \
        + struct.unpack_from(">512h", rom, BG_X_STEPS)
    with open(os.path.join(OUT, "bg_zoom.bin"), "wb") as f:
        f.write(struct.pack("<%dh" % len(words), *words))


def main():
    os.makedirs(OUT, exist_ok=True)
    build_tiles()
    build_zoom()
    build_map("practice", *PRACTICE_MAP)
    build_palette("practice", sys.argv[1])
    for n in sorted(os.listdir(OUT)):
        print(n, os.path.getsize(os.path.join(OUT, n)))


if __name__ == "__main__":
    main()
