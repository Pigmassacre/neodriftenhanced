"""Compare the video state of two dumps: Tools/compare_video.py <mame.bin> <godot.bin>"""
import sys

import render


def region(addr):
    if addr < 0x7000:
        return "sprite %d tile word %d" % (addr >> 6, addr & 63)
    if addr < 0x7500:
        return "text layer"
    if addr < 0x8000:
        return "unused"
    return "sprite %d %s" % (addr & 0x1ff, ("shrink", "y/size", "x", "list")[(addr >> 9) & 3])


def main():
    a, b = render.Dump(sys.argv[1]), render.Dump(sys.argv[2])
    vd = [i for i in range(render.VRAM_WORDS) if a.vram[i] != b.vram[i]]
    pd = [i for i in range(4096) if a.palette[i] != b.palette[i]]
    print("video RAM words differing: %d, palette words differing: %d" % (len(vd), len(pd)))
    for i in vd[:16]:
        print("  %04X %-28s mame %04X godot %04X" % (i, region(i), a.vram[i], b.vram[i]))
    for i in pd[:8]:
        print("  palette %03X mame %04X godot %04X" % (i, a.palette[i], b.palette[i]))


if __name__ == "__main__":
    main()
