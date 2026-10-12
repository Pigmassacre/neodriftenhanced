# Hand-off notes

State of the Neo Drift Out Godot port, for whoever continues it. Read
`README.md` first for setup and the one-paragraph architecture.

## The agreed approach

The owner chose **"translate, then rewrite"**:

1. Machine-translate the original 68000 program to GDScript at build time
   (`Tools/recomp/` → `data/game/code/`, never committed).
2. Keep rendering, input and audio native Godot.
3. Later, hand-rewrite individual routines into readable GDScript where
   enhancements are wanted, verified against the translated version.

Step 3 has not started. Nothing derived from the ROMs may be committed:
`data/`, `neodrift/` and `neogeo/` are git-ignored on purpose.

The owner agreed to target the **Practice Stage first**, then Stage 1.

## What works, and how it was verified

| Area | State | Evidence |
|---|---|---|
| Game logic (recompiled 68000) | Practice stage, menus, attract mode | `verify_session.py practice_steer`: 4041 of 4045 frames of work RAM identical to MAME |
| Video (sprites, shrink, text layer, palettes, mid-frame background move) | Same range | 40 of 40 screenshots pixel-exact |
| Stage 1, continue, game over, attract mode | Runs | `verify_session.py stage1_hold`: 9595 of 9600 frames of work RAM identical, 46 of 48 screenshots pixel-exact |
| CPU timing | 68000 timing tables in `cycles()` in `gen.py` | Each replay reports it: a frame's work ends within about one turn of the game's wait loop (146 of 202752 cycles) of MAME's at the median, nine frames in ten within 8 turns, always slightly early |
| Sound driver (Z80 + chip timers) | Runs the real driver | `compare_ym.py`: 3318 of 3318 chip register writes match MAME in order, a median of 0.00 ms apart (0.57 ms at most) |
| Sound chip (FM, square waves/noise, sampled channels, stereo) | Synthesised in `Project/sound/ym2610.gd` | `compare_audio.py`: MAME's own chip writes replayed into the model leave at most -38 dB of MAME's recording unexplained in any second; levels match. **Not checked by ear** |

The few non-identical RAM frames are single frames that re-converge. The two
screenshots that still differ (2 and 21 pixels, frames 7000 and 13600 of
`stage1_hold`) are text the game rewrites while the picture is being drawn:
the port splits such a text cell at the raster line of the write
(`midframe_text`), and its timing is a line or so early there.

## Verification workflow — use it for every change

```sh
cd Tools
python3 verify_session.py practice_steer --shots     # RAM + screenshots vs MAME
python3 verify_session.py practice_hold --shots
```

- Sessions (scripted inputs) are defined at the top of `verify_session.py`.
  Add one per new area of the game.
- The comparison ignores the random seed word (`$100430`) and dead stack
  (`$10F000-$10F2FF`); see the comments in `compare_ram.py`. The replay takes
  the seed from MAME each time the main loop leaves its vblank wait (`$B80`),
  because the game steps the seed while idling and that depends on exact
  CPU timing.
- Sound, three checks (the job in `data/verify/sound/job.lua` is the steering
  session with `ymlog = {1, last}`; add `-wavwrite` for MAME's own recording):
  ```sh
  Tools/mame/run.sh data/verify/sound/job.lua -wavwrite $PWD/data/verify/sound/mame.wav -seconds_to_run 100
  G="Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path Project --script"
  # chip model alone: MAME's timed writes in, sound out
  $G res://tools/synth_replay.gd -- --ymlog=$PWD/data/verify/sound/ymlog.txt --wav=$PWD/data/verify/sound/godot.wav
  python3 Tools/compare_audio.py data/verify/sound/mame.wav data/verify/sound/godot.wav
  # driver: MAME's timed sound commands in, chip writes (and sound) out
  $G res://tools/sound_replay.gd -- --ymlog=$PWD/data/verify/sound/ymlog.txt --out=$PWD/data/verify/sound/godot_ym.txt
  python3 Tools/compare_ym.py data/verify/sound/ymlog.txt data/verify/sound/godot_ym.txt 520
  ```
  Driver plus chip together (`sound_replay.gd --wav`, `compare_audio.py
  --true-rate`) matches MAME in level every second but not sample for sample:
  a write landing one chip sample (18 us) away shifts a waveform.
- When a frame differs, `Tools/compare_video.py` (video RAM word by word) and
  `Tools/render.py` (reference renderer, exact on MAME dumps) tell you whether
  the machine state or the Godot drawing code is wrong.

## Remaining work, roughly in priority order

### Sound
1. **Listen to it.** Everything above is measured against MAME, nobody has
   heard it.
2. **ADPCM-B** (the seventh sampled channel) is not synthesised. The driver
   only resets it in the sessions recorded so far; `YM2610.unvoiced_adpcm_b`
   counts writes to it.
3. **FM vibrato/tremolo** is written from memory of MAME's chip model and
   never exercised: the driver has not enabled it yet. Channel 3's special
   modes and the SSG-style envelope shapes are not modelled for the same
   reason (see the header of `ym_fm_channel.gd`).
4. The sound board starts the cartridge driver from reset; on hardware the
   BIOS's own driver runs first. No effect seen, but it is a difference.
5. Sound is rendered one video frame behind and queued about 50 ms ahead
   (`SoundBoard.QUEUE_TARGET`).

### Game coverage
7. **Stage 2 and beyond are untested**, and Stage 1 only with the accelerator
   held (`stage1_hold`). Add sessions that play on, run them, and fix what
   turns up. If play reaches untranslated code the game stops and
   appends the address to `data/game/seeds.txt`; re-run
   `Tools/recomp/build_code.py`. If a new *pattern* of missed code shows up,
   teach `Program.explore` in `Tools/recomp/gen.py` or the scans in
   `build_code.py` about it rather than relying on the seed file (existing
   rules: jump tables, offset tables, pointer scans, long routines in pointer
   tables, unrolled loops).
8. Other cars, two-player, service/test mode: untested.

### Machine accuracy
9. **CPU timing is close but not exact** (see the table). What is left is
   probably the handful of 68000 timing details the tables do not cover
   (interrupts only being taken between translated blocks, item 12, is one).
   Free play still gets different random numbers than MAME unless the seed
   is synced, because the seed counts the turns of the wait loop exactly.
10. **Cold boot**: the game starts from a MAME snapshot
    (`Tools/make_start_snapshot.py`) because the BIOS power-on tests (clock
    chip, backup RAM, sound CPU handshake) are not modelled. So setup needs
    MAME. Modelling those, or building the post-boot state directly, would
    remove that dependency.
11. Not modelled: the 96-sprites-per-scanline limit, the screen-darkening
    ("shadow") latch, memory card, coin counters, the second palette bank in
    snapshots (only the active bank is captured).
12. Interrupts are only taken between translated blocks, not between
    instructions.

### The "enhanced" part (not started)
13. Hand-rewrite routines, starting with the car. Useful facts already found:
    - Car object at `$101500` (A6). `+$14` speed, `+$C0/+$C4` position 16.16,
      `+$DC` travel direction, `+$DE` facing, `+$0A` zoom (8.8), `+$D8/+$DA`
      camera, `+$E4` driving state (12 states, table at `$DA72`).
    - Per-frame car update at `$D956`; normal driving state at `$DAAC`.
    - Terrain lookup `$13E74` (x, y → surface code; `< $20` wall with angle,
      `$20-$3F` edge types, `>= $40` surface table at `$232E2`).
    - Course maps: 16x16-tile blocks; practice map header `$2B464E`, block
      table `$2B5E56` (`Tools/extract_map.py`). Background scroll/zoom logic
      at `$1348E-$13E12`.
    - `Project/main.tscn` + `background.gdshader` is a standalone course
      viewer that reproduces the background from the map data alone,
      pixel-exact including zoom. It is the starting point for rendering
      beyond the original 320x224 view.
    - Full disassemblies are generated into `data/dasm/` (`p1.asm`,
      `bios.asm`, `m1.asm`) with MAME's debugger. **`m1.asm` is the BIOS's
      sound driver, not the cartridge's** (the cartridge driver has no
      listing yet; its idle loop is at `$0133`, see `sound_board.gd`); `Tools/dasm.py` prints a
      range of the program listing. MAME's linear listing is misaligned in
      places — the recompiler's own decoder (`Tools/recomp/m68k.py`) is the
      authority.
14. Generated code load time is about 5 s (6 MB of GDScript). Fine for now.

## Traps that cost time

- **MAME's 68000 core can pause mid-instruction.** A snapshot is only valid at
  an instruction boundary; `harness.lua` waits for one (`IR` equals the opcode
  at `rPC-2`, and that is not `CURPC`).
- **Scripted inputs reach the game one frame after they are set** in Lua.
  `verify_session.replay_inputs` accounts for it.
- **Headless MAME still reads the real keyboard and gamepads.** A stray key
  press corrupted one recording. `Tools/mame/run.sh` disables host input.
- **Lua tap and notifier handles must be kept in globals**, errors inside tap
  callbacks are silent, and taps on work RAM must be installed after reset.
- **A sprite's "rows" is its height on screen, not its tile count**: a
  vertically shrunk sprite reads further down its tile strip.
- **MAME runs its sound chip stream at 55555 samples a second**, not the
  chip's true 55555.56, and its square-wave tones start high. Both matter
  only when comparing sample for sample (`synth_replay.gd`, `ym_ssg.gd`).
- **Log times with enough digits.** Microsecond timestamps put some chip
  writes on the wrong chip sample and looked like a decoder bug.
- **awk under a Swedish locale reads `8.5` as 8.** Use `LC_ALL=C`.
- Godot resolves relative paths from the project folder; pass absolute paths
  to the tools under `Project/tools/`.
- The program ROM file is word-swapped, with its second megabyte at bus
  address 0 and its first at `$200000`.

## Repository state

- Work is on `main`; `practice-stage-background` is an older state of it.
- `Godot` in the repo root is a symlink to the editor binary's folder
  (`AGENTS.md` expects it there); it is git-ignored.
