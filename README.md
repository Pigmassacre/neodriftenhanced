# Neo Drift Out — Godot port

A port of the Neo Geo game to Godot 4.7, verified against MAME.

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

## How it works

- `Tools/recomp/` translates the game's 68000 program into GDScript
  (`data/game/code/`), one function per basic block.
- `Project/machine/neogeo_machine.gd` is the machine that code runs on:
  registers, memory map, video registers, raster timer, interrupts.
- `Project/video/` draws the machine's video RAM (sprites with the hardware's
  shrink tables, text layer, palettes) with shaders.
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
python3 verify_session.py practice_steer --shots
```

This plays a scripted session in MAME, replays the same inputs in Godot from
the same starting state, and compares work RAM after every frame and
screenshots pixel for pixel. Sessions are defined at the top of
`verify_session.py`.

See `HANDOFF.md` for the current state, remaining work and known traps.

`Project/main.tscn` is a separate standalone viewer for the practice course
(background shader only).
