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

It starts with a menu, over a still frame of the game: **Arcade** is the whole game, **Freeplay** any one
stage, and **Options** has the picture (full screen, window size, wide
picture, CRT look, see-through shadows), the sound (volume, music, effects),
the controls and the game (new or original HUD, map, free continues). Options are kept in
Godot's user folder for the project (`settings.cfg`).

Keys, until changed in the options: arrows, `Z X C V` = buttons A B C D,
`1` = start, `5` = insert coin, `Esc` = pause. `F2` turns the CRT look on
and off, `F3` changes the HUD, `M` the map, `F11` full screen.

Gamepad: stick or d-pad, the four face buttons = A B C D (the triggers are
A and B too), Start = start (and pause in a race), Back = insert coin.

The picture fills the window's height and is as wide as the window (up to
640 by 224 game pixels; the original is 320 wide): a race shows more of the
course, with the HUD at the edges and a map of the course, and other screens
repeat their backdrop to the sides. Shadows are see-through instead of
flickering. `--resolution 1920x1080` sets the window size; after `--`,
`--no-menu` starts the original's own attract mode without menus or stored
options, `--arcade` and `--stage=3` go straight to a game, `--width=320`
keeps the original width, and `--hardware-video` draws exactly what the
hardware would. The rest are listed at the top of `Project/game.gd`.

## How it works

- `Project/game/` is the game, hand-written in readable GDScript from the
  original's 68000 program, routine by routine. It is all the game runs:
  its main loop, its screens, the race, and a small stand-in for the arcade
  board's system program (coins, credits, start buttons). It takes its
  tables and pictures from the ROM by address, and takes no time to speak
  of, so the game no longer slows down where the original did.
- `Tools/recomp/` translates the original program into GDScript
  (`data/game/code/`), one function per basic block. The game does not load
  it; it is there to check the hand-written routines against, each put in
  place of its translated original (`--original-program`, and the
  verification below).
- `Project/machine/neogeo_machine.gd` is the machine both run on: memory
  map and video registers, and for the translated program the processor's
  registers, raster timer and interrupts.
- `Project/video/` draws the picture with shaders. Normally from the game's
  own records (`game_scene.gd`): the ground straight from the course's map
  and each object from its record, at any width, with the original's code
  that turned them into hardware sprites taken out. It can also draw the
  machine's video RAM as the hardware would (sprites with the hardware's
  shrink tables, text layer, palettes), which is what is compared with MAME.
- `Project/hud/` and `Project/menu/` are what is drawn over the game's
  picture at the window's resolution: a race's HUD, the map of the course
  and the menus.
  `Project/settings.gd` keeps the player's options.
- `Project/sound/` runs the game's own Z80 sound driver and synthesises what
  it plays on the sound chip (FM, square waves and noise, sampled sound).
  The chip's seventh sampled channel (ADPCM-B) makes no sound yet.
- The game starts as an arcade board just switched on, and keeps its best
  times in the user folder as the board keeps them on its battery. Only
  the translated program starts from a machine snapshot taken in MAME just
  after boot (`Tools/make_start_snapshot.py`).

If the translated program reaches code the translator has not seen, it stops,
logs the address to `data/game/seeds.txt`, and `Tools/recomp/build_code.py`
will include it on the next run.

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
