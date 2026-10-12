# Neo Drift Out — Godot port

A port of the Neo Geo game to Godot 4.7, verified against MAME, on its way
to an enhanced version (see `TODO.md`).

Nothing from the game is stored in this repository. Everything the port needs
is derived locally from your own ROM files into `data/` (ignored by git).

## Requirements

- `neodrift/` — the game ROM set (`213-*.{p1,s1,c1,c2,m1,v1,v2}`)
- `neogeo/` — the Neo Geo BIOS files, unpacked
- Godot 4.7.2 (`Godot/` here is a link to the editor binary's folder)
- Python 3 and MAME (used for setup and for verification)

## Setup and run

```sh
Tools/setup.sh
Godot/Godot_v4.7.2-stable_linux.x86_64 --path Project
```

Keys: arrows, `Z X C V` = buttons A B C D, `1` = start, `5` = insert coin.
`F2` turns a CRT look on and off, `M` the map, `F11` full screen.

Gamepad: stick or d-pad, the four face buttons = A B C D (the triggers are
A and B too), Start = start, Back = insert coin.

The picture fills the window's height and is as wide as the window (up to
640 by 224 game pixels; the original is 320 wide): a race shows more of the
course, with the HUD at the edges and a map of the course, and other screens
repeat their backdrop to the sides. Shadows are see-through instead of
flickering. `--resolution 1920x1080` sets the window size; after `--`,
`--width=320` keeps the original width, `--whole-pixels` enlarges the
picture a whole number of times only, `--crt` starts with the CRT look,
`--no-map` without the map, and `--hardware-video` draws exactly what the
hardware would.

## How it works

- `Tools/recomp/` translates the game's 68000 program into GDScript
  (`data/game/code/`), one function per basic block.
- `Project/game/` is the game hand-written in readable GDScript, routine by
  routine, each replacing its translated original and checked against it.
  So far: the race but for drawing it (the car, the other cars, scenery and
  effects, the ground lookup, the clock, the HUD) and the order of screens
  around it, about a quarter of the code that runs. Hand-written code takes
  no CPU time, so the game no longer slows down where the original did.
- `Project/machine/neogeo_machine.gd` is the machine that code runs on:
  registers, memory map, video registers, raster timer, interrupts.
- `Project/video/` draws the picture with shaders. Normally from the game's
  own records (`game_scene.gd`): the ground straight from the course's map
  and each object from its record, at any width, with the original's code
  that turned them into hardware sprites taken out. It can also draw the
  machine's video RAM as the hardware would (sprites with the hardware's
  shrink tables, text layer, palettes), which is what is compared with MAME.
- `Project/hud/` is what is drawn over the game's picture at the window's
  resolution: so far the map of the course.
- `Project/sound/` runs the game's own Z80 sound driver and synthesises what
  it plays on the sound chip (FM, square waves and noise, sampled sound).
  The chip's seventh sampled channel (ADPCM-B) makes no sound yet.
- The game starts from a machine snapshot taken in MAME just after boot
  (`Tools/make_start_snapshot.py`), so the BIOS power-on tests are not modelled.

If the game reaches code the translator has not seen, it stops, logs the
address to `data/game/seeds.txt`, and `Tools/recomp/build_code.py` will
include it on the next run.

## Verifying against MAME

```sh
cd Tools
python3 verify_session.py practice_steer --check-routines
python3 verify_session.py practice_steer --translated --shots
```

This plays a scripted session in MAME, replays the same inputs in Godot from
the same starting state, and compares work RAM after every frame and
screenshots pixel for pixel. `--check-routines` also runs every call of a
hand-written routine both ways and compares the outcomes.
`--translated --compare-views` draws every frame both from the game's records
and from video RAM and counts the frames that differ. Sessions are
defined at the top of `verify_session.py`; `Tools/routines.py` lists the
game's routines and how far the hand-writing has come.

See `HANDOFF.md` for the current state, remaining work and known traps.

`Project/main.tscn` is a separate standalone viewer for the practice course
(background shader only).
