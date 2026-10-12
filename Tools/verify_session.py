"""Verify the Godot port against MAME for a scripted play session.

Usage: python3 Tools/verify_session.py <session> [--frames N] [--shots]

Runs the session's inputs in MAME (recording a machine snapshot, work RAM
after every frame, the random seeds and periodic screenshots), replays the
same inputs in Godot from the snapshot, and compares work RAM frame by
frame. With --shots it also compares screenshots pixel for pixel.

Results and recordings go to data/verify/<session>/ (not checked in).
"""
import argparse
import os
import struct
import subprocess
import sys

import compare_ram
import neogeo
import render

GODOT = os.path.join(neogeo.ROOT, "Godot", "Godot_v4.7.2-stable_linux.x86_64")
PROJECT = os.path.join(neogeo.ROOT, "Project")

# Lua port/field for each input name used in sessions.
FIELDS = {
    "coin": (":AUDIO_COIN", "Coin 1"),
    "start": (":edge:joy:START", "1 Player Start"),
    "up": (":edge:joy:JOY1", "P1 Up"),
    "down": (":edge:joy:JOY1", "P1 Down"),
    "left": (":edge:joy:JOY1", "P1 Left"),
    "right": (":edge:joy:JOY1", "P1 Right"),
    "a": (":edge:joy:JOY1", "P1 A"),
    "b": (":edge:joy:JOY1", "P1 B"),
    "c": (":edge:joy:JOY1", "P1 C"),
    "d": (":edge:joy:JOY1", "P1 D"),
}


def menu_inputs():
    """Coin up, start, and tap A through name entry and car select."""
    inputs = [("coin", 500, 505), ("start", 600, 605)]
    inputs += [("a", f, f + 5) for f in range(800, 3001, 200)]
    return inputs


# name: (snapshot frame, last frame, [(input, first frame, last frame), ...])
SESSIONS = {
    # the original recording: straight through the practice stage holding accelerate
    "practice_hold": (2600, 4400, menu_inputs() + [("a", 3100, 5100)]),
    # from attract mode through the menus, then steering and braking in the practice stage
    "practice_steer": (450, 4500, menu_inputs() + [
        ("a", 3100, 3560), ("left", 3150, 3200), ("right", 3260, 3330), ("left", 3400, 3440),
        ("right", 3500, 3520), ("b", 3600, 3640), ("a", 3660, 5200), ("left", 3700, 3760),
        ("right", 3800, 3900), ("left", 3960, 4000), ("right", 4100, 4130), ("left", 4200, 4300),
    ]),
    # the end of the practice stage, stage 1 until the time runs out, the continue
    # countdown, game over, and attract mode round to its demo of stage 1
    "stage1_hold": (4400, 14000, menu_inputs() + [("a", 3100, 14000)]),
}


def write_job(path, out, first, last, inputs, shot_step):
    lines = ["return {", '  out = "%s", stop = %d,' % (out, last),
             "  snapshot = %d, ramlog = {%d, %d}, seedlog = {%d, %d}," % (first, first, last, first - 5, last),
             "  snaps = (function() local t = {} for f = %d, %d, %d do t[#t + 1] = f end return t end)(),"
             % (first + shot_step, last, shot_step),
             "  inputs = {"]
    for name, a, b in inputs:
        port, field = FIELDS[name]
        lines.append('    {%d, %d, "%s", "%s"},' % (a, b, port, field))
    lines += ["  },", "}"]
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def replay_inputs(inputs, snapshot_frame, frames):
    """Inputs set in MAME at frame F reach the game one frame later."""
    args = []
    for name, a, b in inputs:
        first, last = a - snapshot_frame + 1, b - snapshot_frame + 1
        if last >= 0 and first < frames:
            args.append("--input=%s:%d-%d" % (name, max(first, 0), last))
    return args


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("session", choices=sorted(SESSIONS))
    parser.add_argument("--frames", type=int, help="limit the number of frames replayed")
    parser.add_argument("--shots", action="store_true", help="also compare screenshots")
    parser.add_argument("--shot-step", type=int, default=100)
    parser.add_argument("--keep-recording", action="store_true", help="reuse an existing MAME recording")
    args = parser.parse_args()

    first, last, inputs = SESSIONS[args.session]
    out = os.path.join(neogeo.ROOT, "data", "verify", args.session)
    os.makedirs(out, exist_ok=True)
    snapshot = os.path.join(out, "snapshot.bin")

    if not (args.keep_recording and os.path.exists(snapshot)):
        job = os.path.join(out, "job.lua")
        write_job(job, out, first, last, inputs, args.shot_step)
        subprocess.run([os.path.join(neogeo.ROOT, "Tools", "mame", "run.sh"), job,
                        "-seconds_to_run", str(last // 55 + 20)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(snapshot, "rb") as f:
        snapshot_frame = struct.unpack(">I", f.read(8)[4:])[0]
    frames = last - snapshot_frame
    if args.frames:
        frames = min(frames, args.frames)
    print("%s: snapshot at frame %d, replaying %d frames" % (args.session, snapshot_frame, frames))

    godot_log = os.path.join(out, "godot_ram.bin")
    common = ["--snapshot=" + snapshot, "--seedlog=" + os.path.join(out, "seedlog.bin")] \
        + replay_inputs(inputs, snapshot_frame, frames)
    result = subprocess.run([GODOT, "--headless", "--path", PROJECT, "--script", "res://tools/replay.gd", "--",
                             "--frames=%d" % frames, "--out=" + godot_log] + common,
                            capture_output=True, text=True)
    for line in result.stdout.splitlines():
        if line.startswith(("ran ", "missing ", "timing")):
            print("godot:", line)
    sys.argv = ["compare_ram", os.path.join(out, "ramlog.bin"), godot_log, str(snapshot_frame - first + 1)]
    compare_ram.main()

    if args.shots:
        shot_frames = [f for f in range(first + args.shot_step, last + 1, args.shot_step)
                       if 0 < f - snapshot_frame <= frames]
        pattern = os.path.join(out, "godot_%d.png")
        subprocess.run([GODOT, "--path", PROJECT, "--", "--shot=" + pattern,
                        "--shot-frame=" + ",".join(str(f - snapshot_frame) for f in shot_frames)] + common,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        exact = 0
        for f in shot_frames:
            _, _, a = render.read_png(os.path.join(out, "f%06d.png" % f))
            _, _, b = render.read_png(pattern % (f - snapshot_frame))
            diff = sum(1 for p, q in zip(a, b) if p != q)
            if diff == 0:
                exact += 1
            else:
                print("  frame %d: %d pixels differ" % (f, diff))
        print("%d of %d screenshots pixel-exact" % (exact, len(shot_frames)))


if __name__ == "__main__":
    main()
