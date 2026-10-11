"""Capture the machine state the Godot game starts from.

Usage: python3 Tools/make_start_snapshot.py

Boots the game in MAME (headless) and saves the machine state shortly after
the BIOS has handed over to the game, during the attract sequence, as
data/game/start.snapshot. Starting from a snapshot avoids having to model
the BIOS's power-on hardware tests.
"""
import os
import shutil
import subprocess

import neogeo

BOOT_FRAME = 450


def main():
    out = os.path.join(neogeo.ROOT, "data", "verify", "boot")
    os.makedirs(out, exist_ok=True)
    job = os.path.join(out, "job.lua")
    with open(job, "w") as f:
        f.write('return { out = "%s", stop = %d, snapshot = %d }\n' % (out, BOOT_FRAME + 60, BOOT_FRAME))
    subprocess.run([os.path.join(neogeo.ROOT, "Tools", "mame", "run.sh"), job, "-seconds_to_run", "30"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    target = os.path.join(neogeo.ROOT, "data", "game", "start.snapshot")
    shutil.copyfile(os.path.join(out, "snapshot.bin"), target)
    print("wrote", target)


if __name__ == "__main__":
    main()
