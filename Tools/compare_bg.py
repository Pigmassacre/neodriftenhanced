"""Compare the Godot background against MAME's background layer.

Usage: python3 Tools/compare_bg.py <state_dump.bin> <godot_binary> <out_dir> [ramlog.bin first_frame]

The picture on screen lags the game's scroll variables, so with a per-frame
RAM log the scroll state of the preceding frames is tried as well.

Renders the same camera position in Godot and compares it with MAME's own
screenshot of that frame (<dump>.png next to the dump), ignoring pixels that
are covered by other sprites or the text layer. The dump alone cannot serve
as the reference: the game repositions the background mid-frame, and the
dump only holds the end-of-frame state.
"""
import os
import struct
import subprocess
import sys

import neogeo
import render


def foreground_mask(r, d):
    """True for pixels covered by anything other than the background columns."""
    vram = list(d.vram)
    for s in range(32, 64):
        vram[0x8200 + s] = 0
    d.vram = vram
    pal = list(d.palette)
    pal[4095] = 0x0000
    d.palette = pal
    dark = r.render(d)
    pal[4095] = 0x7fff
    d.palette = pal
    light = r.render(d)
    return [a == b for a, b in zip(dark, light)]


def main():
    dump_path, godot, out = sys.argv[1:4]
    d = render.Dump(dump_path)
    states = [d.ram]
    if len(sys.argv) > 5:
        first = int(sys.argv[5])
        with open(sys.argv[4], "rb") as f:
            for back in (1, 2, 3):
                f.seek((d.frame - back - first) * 0x10000)
                states.append(f.read(0x10000))
    r = render.Renderer()
    _, _, ref = render.read_png(dump_path[:-4] + ".png")
    mask = foreground_mask(r, d)
    visible = mask.count(False)
    shot = os.path.join(out, "bg_godot.png")
    for back, ram in enumerate(states):
        cam = struct.unpack_from(">HH", ram, 0x2534)
        zoom = struct.unpack_from(">HH", ram, 0x2538)
        subprocess.run([godot, "--path", os.path.join(neogeo.ROOT, "Project"), "--",
                        "--camera=%d,%d" % cam, "--zoom=%d,%d" % zoom, "--shot=" + shot],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        _, _, got = render.read_png(shot)
        diff = sum(1 for g, m, covered in zip(got, ref, mask) if not covered and g != m)
        print("state %d frame(s) back: camera %s zoom %s -> %d of %d background pixels differ"
              % (back, cam, [hex(z) for z in zoom], diff, visible))
        if diff == 0:
            break


if __name__ == "__main__":
    main()
