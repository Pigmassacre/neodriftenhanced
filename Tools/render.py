"""Reference Neo Geo frame renderer working from harness state dumps.

Usage: python3 Tools/render.py <dump.bin> <out.png> [reference.png]
With a reference screenshot, prints the number of differing pixels.
"""
import os
import struct
import sys
import zipfile
import zlib

import neogeo

WIDTH, HEIGHT = 320, 224
VRAM_WORDS = 0x8800

ZOOM_X = [
    (0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0),
    (0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0),
    (0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0),
    (0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0),
    (0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0),
    (0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0),
    (1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0),
    (1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0),
    (1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 0),
    (1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1),
    (1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 1),
    (1, 0, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1),
    (1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1),
    (1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
    (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
]


class Dump:
    def __init__(self, path):
        with open(path, "rb") as f:
            data = f.read()
        magic, self.frame, self.lspc_mode, self.shadow, self.fix_bank, self.pal_bank, self.timer_writes = \
            struct.unpack(">4sIHBBBB", data[:14])
        assert magic == b"NDF1"
        o = 14
        self.vram = struct.unpack(">%dH" % VRAM_WORDS, data[o:o + VRAM_WORDS * 2])
        o += VRAM_WORDS * 2
        self.palette = struct.unpack(">4096H", data[o:o + 0x2000])
        o += 0x2000
        self.ram = data[o:o + 0x10000]


def load_bios_file(name):
    """Read a BIOS file from the neogeo/ folder (or neogeo.zip) at the repo root."""
    folder = os.path.join(neogeo.ROOT, "neogeo")
    if os.path.isdir(folder):
        with open(os.path.join(folder, name), "rb") as f:
            return f.read()
    with zipfile.ZipFile(os.path.join(neogeo.ROOT, "neogeo.zip")) as z:
        return z.read(name)


# The video DAC is a 5-bit resistor ladder per channel (3k9, 2k2, 1k, 470, 220);
# the "dark" bit adds an 8k2 pull-down.
_CONDUCTANCE = [1 / 3900, 1 / 2200, 1 / 1000, 1 / 470, 1 / 220]
_LEVELS = [
    [int(255 * sum(g for i, g in enumerate(_CONDUCTANCE) if v >> i & 1)
         / (sum(_CONDUCTANCE) + pull) + 0.5) for v in range(32)]
    for pull in (0, 1 / 8200)
]


def colour(word):
    """Palette word to 8-bit RGB."""
    levels = _LEVELS[word >> 15]
    r = ((word >> 7) & 0x1e) | ((word >> 14) & 1)
    g = ((word >> 3) & 0x1e) | ((word >> 13) & 1)
    b = ((word << 1) & 0x1e) | ((word >> 12) & 1)
    return (levels[r], levels[g], levels[b])


class Renderer:
    def __init__(self):
        self.c1, self.c2 = neogeo.load_sprites()
        self.s1 = neogeo.load_fix()
        self.sfix = load_bios_file("sfix.sfix")
        self.zoomy = load_bios_file("000-lo.lo")
        self.tile_mask = neogeo.sprite_tile_count(self.c1) - 1
        self._tiles = {}
        self._fix = {}

    def tile(self, n):
        t = self._tiles.get(n)
        if t is None:
            t = self._tiles[n] = neogeo.decode_sprite_tile(self.c1, self.c2, n)
        return t

    def fix_tile(self, n, bank):
        key = (n, bank)
        t = self._fix.get(key)
        if t is None:
            t = self._fix[key] = neogeo.decode_fix_tile(self.s1 if bank else self.sfix, n)
        return t

    def sprite_lines(self, d):
        """Yield (scanline, x, zoom_x, tile, attr, row_in_tile) in draw order."""
        vram = d.vram
        for line in range(16, 16 + HEIGHT):
            active = []
            y = rows = zoom_y = x = zoom_x = 0
            for s in range(1, 381):
                yc = vram[0x8200 + s]
                zc = vram[0x8000 + s]
                if yc & 0x40:
                    x = (x + zoom_x + 1) & 0x1ff
                    zoom_x = (zc >> 8) & 15
                else:
                    y = 0x200 - (yc >> 7)
                    rows = yc & 0x3f
                    zoom_y = zc & 0xff
                    x = vram[0x8400 + s] >> 7
                    zoom_x = (zc >> 8) & 15
                if rows == 0:
                    continue
                sprite_line = (line - y) & 0x1ff
                if rows < 0x21 and sprite_line >= rows * 16:
                    continue
                active.append((s, x, zoom_x, zoom_y, rows, sprite_line))
                if len(active) == 96:
                    break
            for s, x, zoom_x, zoom_y, rows, sprite_line in active:
                zoom_line = sprite_line & 0xff
                invert = sprite_line & 0x100
                if invert:
                    zoom_line ^= 0xff
                if rows > 0x20:
                    zoom_line %= (zoom_y + 1) << 1
                    if zoom_line >= zoom_y + 1:
                        zoom_line = ((zoom_y + 1) << 1) - 1 - zoom_line
                        invert = not invert
                entry = self.zoomy[(zoom_y << 8) + zoom_line]
                t, row = entry >> 4, entry & 15
                if invert:
                    t ^= 0x1f
                    row ^= 15
                code = vram[s * 64 + t * 2]
                attr = vram[s * 64 + t * 2 + 1]
                yield line - 16, x, zoom_x, code, attr, row

    def render(self, d, auto_anim=0, fix=True):
        pal = [colour(w) for w in d.palette]
        out = [pal[4095]] * (WIDTH * HEIGHT)
        for sy, x, zoom_x, code, attr, row in self.sprite_lines(d):
            code |= (attr << 12) & 0xf0000
            if not d.lspc_mode & 8:
                if attr & 8:
                    code = (code & ~7) | (auto_anim & 7)
                elif attr & 4:
                    code = (code & ~3) | (auto_anim & 3)
            pix = self.tile(code & self.tile_mask)
            if attr & 2:
                row ^= 15
            base = row * 16
            colours = (attr >> 8) * 16
            zx = ZOOM_X[zoom_x]
            line = sy * WIDTH
            for i in range(16):
                if not zx[i]:
                    continue
                c = pix[base + (15 - i if attr & 1 else i)]
                if c and x < WIDTH:
                    out[line + x] = pal[colours + c]
                x = (x + 1) & 0x1ff
        vram = d.vram
        for col in range(40 if fix else 0):
            for r in range(2, 30):
                w = vram[0x7000 + col * 32 + r]
                pix = self.fix_tile(w & 0xfff, d.fix_bank)
                colours = (w >> 12) * 16
                for py in range(8):
                    line = ((r - 2) * 8 + py) * WIDTH + col * 8
                    for px in range(8):
                        c = pix[py * 8 + px]
                        if c:
                            out[line + px] = pal[colours + c]
        return out


def write_rgb_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for p in pixels[y * width:(y + 1) * width]:
            raw += bytes(p)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))


def read_png(path):
    """Minimal PNG reader for 8-bit RGB/RGBA/palette screenshots. Returns (w, h, [(r,g,b)])."""
    with open(path, "rb") as f:
        data = f.read()
    o, idat, plte = 8, b"", None
    while o < len(data):
        n, tag = struct.unpack(">I4s", data[o:o + 8])
        body = data[o + 8:o + 8 + n]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
        elif tag == b"PLTE":
            plte = body
        elif tag == b"IDAT":
            idat += body
        o += 12 + n
    assert depth == 8
    bpp = {2: 3, 6: 4, 3: 1}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    pixels = []
    for y in range(h):
        ft = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                cur[i] = (cur[i] + a) & 255
            elif ft == 2:
                cur[i] = (cur[i] + b) & 255
            elif ft == 3:
                cur[i] = (cur[i] + (a + b) // 2) & 255
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                cur[i] = (cur[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        for x in range(w):
            if ctype == 3:
                i = cur[x] * 3
                pixels.append(tuple(plte[i:i + 3]))
            else:
                pixels.append(tuple(cur[x * bpp:x * bpp + 3]))
        prev = cur
    return w, h, pixels


def compare(a, b, tolerance=0):
    return sum(1 for p, q in zip(a, b) if max(abs(p[i] - q[i]) for i in range(3)) > tolerance)


def main():
    d = Dump(sys.argv[1])
    r = Renderer()
    out = r.render(d)
    write_rgb_png(sys.argv[2], WIDTH, HEIGHT, out)
    print("frame %d mode %04x shadow %d fixbank %d palbank %d timer writes %d"
          % (d.frame, d.lspc_mode, d.shadow, d.fix_bank, d.pal_bank, d.timer_writes))
    if len(sys.argv) > 3:
        w, h, ref = read_png(sys.argv[3])
        assert (w, h) == (WIDTH, HEIGHT), (w, h)
        best = min((compare(r.render(d, a), ref), a) for a in range(8))
        print("differing pixels: %d of %d (auto-anim frame %d)" % (best[0], w * h, best[1]))


if __name__ == "__main__":
    main()
