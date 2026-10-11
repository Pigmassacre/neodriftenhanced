"""Neo Geo ROM loading and graphics decoding for the neodrift set.

Dependency-free (stdlib only). ROMs are read from the neodrift/ folder at the
repo root; nothing from them is checked into the repository.
"""
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM_DIR = os.path.join(ROOT, "neodrift")


def _read(name):
    with open(os.path.join(ROM_DIR, name), "rb") as f:
        return f.read()


def load_program():
    """68000 program as it appears on the bus (big-endian, address 0 first).

    The P1 file stores 16-bit words byte-swapped, with the second megabyte of
    the file mapped at address 0 and the first megabyte at 0x100000.
    """
    raw = bytearray(_read("213-p1.p1"))
    raw[0::2], raw[1::2] = raw[1::2], raw[0::2]
    return bytes(raw[0x100000:] + raw[:0x100000])


def rom_offset(addr):
    """Offset in the load_program() image for a 68000 bus address.

    The first megabyte is mapped at 0x000000, the second at 0x200000.
    """
    if addr < 0x100000:
        return addr
    assert 0x200000 <= addr < 0x300000, hex(addr)
    return addr - 0x100000


def load_fix():
    return _read("213-s1.s1")


def load_sprites():
    return _read("213-c1.c1"), _read("213-c2.c2")


def load_z80():
    return _read("213-m1.m1")


def load_samples():
    return _read("213-v1.v1"), _read("213-v2.v2")


# For every byte value, the 8 pixels it contributes to one bitplane, with
# bit 0 as the leftmost pixel.
_SPREAD = [bytes((v >> i) & 1 for i in range(8)) for v in range(256)]


def sprite_tile_count(c1):
    return len(c1) // 64


def decode_sprite_tile(c1, c2, tile):
    """Return a 16x16 tile as 256 bytes of 4-bit colour indices, row-major."""
    base = tile * 64
    out = bytearray(256)
    for half, xoff in ((0x20, 0), (0x00, 8)):
        for y in range(16):
            o = base + half + y * 2
            p0, p1 = _SPREAD[c1[o]], _SPREAD[c1[o + 1]]
            p2, p3 = _SPREAD[c2[o]], _SPREAD[c2[o + 1]]
            row = y * 16 + xoff
            for x in range(8):
                out[row + x] = p0[x] | (p1[x] << 1) | (p2[x] << 2) | (p3[x] << 3)
    return out


# Fix tiles are stored column pair by column pair, in this order.
_FIX_COLUMNS = (0x10, 0x18, 0x00, 0x08)


def decode_fix_tile(s1, tile):
    """Return an 8x8 fix-layer tile as 64 bytes of 4-bit indices, row-major."""
    base = tile * 32
    out = bytearray(64)
    for col, off in enumerate(_FIX_COLUMNS):
        for y in range(8):
            b = s1[base + off + y]
            out[y * 8 + col * 2] = b & 15
            out[y * 8 + col * 2 + 1] = b >> 4
    return out


def write_png(path, width, height, pixels, palette=None):
    """Write an 8-bit indexed PNG. `palette` is a list of (r, g, b[, a])."""
    if palette is None:
        palette = [(i * 17, i * 17, i * 17) for i in range(16)]

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y * width:(y + 1) * width]
    plte = b"".join(bytes(c[:3]) for c in palette)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0))
    png += chunk(b"PLTE", plte)
    if any(len(c) > 3 for c in palette):
        png += chunk(b"tRNS", bytes(c[3] if len(c) > 3 else 255 for c in palette))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def tile_sheet(tiles, size, columns):
    """Lay decoded tiles out on a grid; returns (width, height, pixels)."""
    rows = (len(tiles) + columns - 1) // columns
    width, height = columns * size, rows * size
    pixels = bytearray(width * height)
    for i, tile in enumerate(tiles):
        ox, oy = (i % columns) * size, (i // columns) * size
        for y in range(size):
            dst = (oy + y) * width + ox
            pixels[dst:dst + size] = tile[y * size:(y + 1) * size]
    return width, height, pixels
