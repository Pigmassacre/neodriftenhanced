# Hand-off notes

State of the Neo Drift Out Godot port, for whoever continues it. Read
`README.md` first for setup and the one-paragraph architecture.

## The goal and the approach

**The goal is the enhanced game, not an emulator.** The owner's plan is in
`TODO.md`: finish the static recompilation (done), then decompile the game
into readable code (under way, see "Decompilation" below), then the
enhancements: widescreen, minimap, real translucency, reworked menus and
HUD, a CRT shader, and later a level editor and mods.

The translated program and the comparison with MAME are the means: they say
exactly what the game does, so that every hand-written routine can be
checked. Spend time on machine accuracy only where an enhancement or the
decompilation needs it.

1. Machine-translate the original 68000 program to GDScript at build time
   (`Tools/recomp/` → `data/game/code/`, never committed). **Done**: the
   whole game runs.
2. Keep rendering, input and audio native Godot.
3. Hand-write the game routine by routine in `Project/game/`, each checked
   against its translated original. **Started**: 40 routines (895 of about 16700
   instructions), the car's driving.

Nothing derived from the ROMs may be committed: `data/`, `neodrift/` and
`neogeo/` are git-ignored on purpose. The hand-written code in
`Project/game/` is committed; the tables it reads stay in the ROM and are
referred to by address.

## Decompilation

`python3 Tools/routines.py` shows what there is to do: in the nine recorded
sessions about 970 routines of the game ran, some 16700 instructions (the
rest of the 2 MB program is data or never runs). It lists them in
`data/game/routines.txt` with size, call counts, share of CPU time, callers
and callees, and marks those already hand-written.

How a hand-written routine lives among translated ones:

- A script in `Project/game/` extends `GameRoutines` and lists its routines
  by address in `routines()`; `Decomp.GROUPS` lists the scripts.
  `NeoGeoMachine.replace_routine` puts each in place of the translated block
  at that address.
- The routine takes its arguments where the original did (registers of the
  machine `m`, work RAM through `u16`/`set16`/..., ROM tables through
  `rom_u16`/...), and must leave RAM and the registers its callers read as
  the original would. `scratch()` names the registers it leaves different.
- It calls routines that are still translated with `m.call_routine(address)`,
  and hand-written ones as ordinary methods.
- Hand-written code takes no CPU time.

Workflow for a routine:

```sh
python3 Tools/routines.py --routine E8BA        # listing, from the recompiler's decoder
# write it in Project/game/, add it to routines()
python3 Tools/verify_session.py practice_steer --keep-recording --check-routines
```

`--check-routines` (`Project/tools/routine_check.gd`) runs every call of
every hand-written routine twice from the same state, original first, and
reports any difference in work RAM, video RAM, palettes, sound commands or
registers, with the registers the call started from. The run then goes on
from the hand-written outcome at the original's time, so the usual
comparison of the whole session with MAME still holds, and a caller that
depends on a "scratch" register shows up there. **State: all 40 routines
agree on every call of all nine sessions (1.3 million calls), and the
sessions match MAME exactly as far as the translation alone does.**
Branches that no session takes are unchecked, though: the listing marks
them "ran 0 times" (driving backwards through a gate, for one). A session
that takes them is the way to check them.

Other switches: `--translated` leaves the hand-written routines out;
`--only-routines=E8BA,EAA8` uses just those; `--profile` rewrites the
block profile `routines.py` reads; `replay.gd --watch=OFFSET` reports every
change of a work RAM word with the block and raster line.

What is known so far is in the code: `Project/game/car.gd` names the car
object's fields (the player's car is at `$101508`, in A6) and the ROM
tables it uses. Where to go next, in the car: `$EDF4` (scrolling the
course under the camera), `$EEA6`/`$EEBC` (drawing the car, on the ground
and in the air), `$F696` (sparks off a wall), then the caller `$D956` and
the other eleven driving states (table at `$DA72`; `$DDA4` is close to
`$DAAC`). `$15256` queues a sound; it waits for the interrupt handler when
the queue is full, so it needs the handler's side decompiled with it. `$13E74` is the terrain lookup (a cache of four
decoded 128x128 blocks; `$13EF4` decodes one). The sprite list builder
around `$12036-$13330` takes most of the CPU time and is what a native
renderer would replace.

Two things to know:

- **Without `--check-routines`, a run with hand-written routines drifts
  from MAME** where the original needs more than a frame for a frame's work
  (first in the menus, frame 2005 of `practice_steer`): the original drops
  a frame there and hand-written code, taking no time, does not. The game
  plays the same; it just does not slow down. So `--shots`, which runs the
  real game, is only pixel-exact with `--translated`.
- While being checked, a routine runs to its end before an interrupt is
  taken. That has made no difference so far, but it will once hand-written
  routines cover most of a frame; by then the interrupt handlers need
  decompiling too, and the comparison becomes work RAM at the end of each
  frame against the recordings.

## What works, and how it was verified

| Area | State | Evidence |
|---|---|---|
| Game logic (recompiled 68000) | The whole game: menus, practice stage, the six stages, ending, attract loop | `verify_session.py`, work RAM after every frame against MAME, see below |
| Video (sprites, shrink, text layer, palettes, changes while the picture is drawn, 96 sprites a line) | Same range | 670 of 681 screenshots pixel-exact |
| CPU timing | 68000 timing tables, interrupt and raster timer timing | Each replay reports it: the port leaves the wait for the vertical blank on the same turn of the wait loop (146 of 202752 cycles) as MAME in about 3 frames of 4, and within one turn otherwise |
| Sound driver (Z80 + chip timers) | Runs the real driver | `compare_ym.py` over the whole game: 72319 of 72322 chip register writes match MAME in order, a median of 0.00 ms apart |
| Sound chip (FM, square waves/noise, sampled channels, stereo) | Synthesised in `Project/sound/ym2610.gd` | `compare_audio.py` on the practice session: MAME's own chip writes replayed into the model leave at most -38 dB of MAME's recording unexplained in any second; levels match. The owner has listened to it |

| Session | Work RAM identical | Screenshots pixel-exact |
|---|---|---|
| `practice_steer` (menus, steering and braking in the practice stage) | 4045 of 4045 frames | 40 of 40 |
| `practice_hold` | 1796 of 1797 | 18 of 18 |
| `stage1_hold` (Stage 1, continue, game over, attract) | 9599 of 9600 | 95 of 96 |
| `stage2_hold` | 6697 of 6700 | 66 of 67 |
| `stage3_hold` | 7499 of 7500 | 74 of 75 |
| `stage4_hold` | 8498 of 8499 | 83 of 85 |
| `stage5_hold` | 7998 of 8000 | 78 of 80 |
| `stage6_hold` | 7999 of 7999 | 76 of 80 |
| `ending` (end of Stage 6, totals, ending, attract loop) | 8733 of 14000 | 140 of 140 |

- The stray non-identical RAM frames are single frames that re-converge.
- `ending` is identical up to frame 56736, where the attract loop hands
  control to the BIOS, which reads the calendar chip (item 11 below).
- The screenshots that differ do so by 2 to 4 pixels: one row of a digit of
  the running time, which the game rewrites while the picture is being drawn.
  The port splits such a text cell at the raster line of the write
  (`midframe_text`); the row is wrong when the write lands within a few
  cycles of a line's start (item 9).
- Stages 2 to 6 are played with a cheat, see below.

## Verification workflow — use it for every change

```sh
cd Tools
python3 verify_session.py practice_steer --keep-recording --check-routines   # hand-written routines
python3 verify_session.py practice_steer --translated --shots   # the machine: RAM + screenshots vs MAME
```

- Sessions (scripted inputs) are defined at the top of `verify_session.py`.
  Add one per new area of the game. Together they cover the whole game once:
  `practice_steer`, `practice_hold`, `stage1_hold`, `stage2_hold` to
  `stage6_hold` and `ending`. `--keep-recording` reuses MAME's recording.
- **The sessions from Stage 2 on cheat**: holding the accelerator finishes a
  stage about 11 seconds too late to go on, so both MAME and the port top the
  stage timer up when it runs low (`topup` in `harness.lua`,
  `NeoGeoMachine.top_up`, `TIMER_TOPUP` in `verify_session.py`). The timer is
  the whole part of the 16.16 value at `$103334`; `$1016C4` is a copy.
- CPU timing: a harness job with `cputrace` (run MAME with `-debug -debugger
  none`) logs every instruction with the CPU's cycle count.
  `Tools/compare_cycles.py` checks the recompiler's timing tables against it,
  and with `--port` and a block trace from `replay.gd --cycles` compares when
  the interrupts and the main loop happen within each frame.
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
1. Listened to by the owner (2026-10-12).
2. **ADPCM-B** (the seventh sampled channel) is not synthesised, and the
   game does not seem to use it: in a run of the whole game (`ymlog` over
   frames 100 to 61990) the driver only ever resets it.
   `YM2610.unvoiced_adpcm_b` counts writes to it.
3. **FM vibrato/tremolo** is written from memory of MAME's chip model and
   never exercised: in that same run the driver never turns the chip's
   low-frequency oscillator on. Channel 3's special modes and the SSG-style
   envelope shapes are not modelled for the same reason (see the header of
   `ym_fm_channel.gd`).
4. The sound board starts the cartridge driver from reset; on hardware the
   BIOS's own driver runs first. No effect seen, but it is a difference.
5. Sound is rendered one video frame behind and queued about 50 ms ahead
   (`SoundBoard.QUEUE_TARGET`).

### Game coverage
7. **Every stage has only been driven with the accelerator held.** All six
   stages, the ending and the attract loop run without reaching untranslated
   code, but real steering is only covered in the practice stage, and the
   later stages only with the timer topped up. A driving bot (search over
   inputs in the port, which runs a frame in about 3.5 ms, then replay the
   result in MAME) would remove the cheat. If play reaches untranslated code
   the game stops and appends the address to `data/game/seeds.txt`; re-run
   `Tools/recomp/build_code.py`. If a new *pattern* of missed code shows up,
   teach `Program.explore` in `Tools/recomp/gen.py` or the scans in
   `build_code.py` about it rather than relying on the seed file (existing
   rules: jump tables, offset tables, pointer scans, long routines in pointer
   tables, unrolled loops).
8. Other cars, two-player, continuing after a coin, service/test mode:
   untested. (The attract demos do show the other cars.)

### Machine accuracy (low priority: the goal is not an emulator)
9. **CPU timing is exact except when the raster interrupt lands in the
   middle of the frame's work**, because interrupts are only taken between
   translated blocks (the wait loop is one block per instruction, so there
   they arrive on the right instruction). The interrupt handler then waits
   for a raster line, which hides most of it: what is left is a frame's work
   ending 10 to 20 cycles off. Running instruction by instruction close to a
   known event time would fix it; that needs a single-step function for
   every instruction (`Emitter.step` makes them for some already). Free play
   still gets different random numbers than MAME unless the seed is synced.
   What the timing now models, all found with `compare_cycles.py`:
   - the 68000's timing tables (`cycles()` in `gen.py`), with the cycle count
     brought up to date before every instruction that may touch hardware;
   - the vertical blank interrupt 30 cycles into line 240 and the raster
     timer reloaded 573 cycles into it (`run_frame`);
   - interrupts starting 50 to 59 cycles after an instruction, in step with
     the E clock, whose phase follows from the frame number
     (`MachineLoader.E_CLOCK_PHASE`);
   - the wait loop's `rol`, which is too late to notice an interrupt in its
     last 6 cycles.
10. **Cold boot**: the game starts from a MAME snapshot
    (`Tools/make_start_snapshot.py`) because the BIOS power-on tests (clock
    chip, backup RAM, sound CPU handshake) are not modelled. So setup needs
    MAME. Modelling those, or building the post-boot state directly, would
    remove that dependency.
11. **The calendar chip is not modelled.** When the attract loop hands
    control back to the BIOS (frame 56736 of `ending`), the BIOS reads it,
    and from there on the BIOS's own work RAM differs from MAME's. The
    picture stays the same. MAME sets the chip from the host's clock, so a
    comparison needs that time recorded in the snapshot.
12. Not modelled: the screen-darkening ("shadow") latch, memory card, coin
    counters, the second palette bank in snapshots (only the active bank is
    captured), palette writes while the picture is being drawn (they apply
    to the whole frame).

### Decompilation and the "enhanced" part
13. Decompile, see "Decompilation" above. Useful facts beyond what
    `Project/game/car.gd` records:
    - Per-frame car update at `$D956`; driving states through the table at
      `$DA72` (normal driving `$DAAC` is hand-written).
    - Terrain lookup `$13E74` (x, y → ground code; `< $20` wall with angle,
      `$20-$3F` edge types, `>= $40` open ground, table at `$232E2`).
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
14. The enhancements of `TODO.md` come after the decompilation, but the
    wide view can be prepared: the course viewer above draws the background
    from map data at any size, and the car code now names the camera and
    zoom fields it needs.
15. Generated code load time is about 5 s (6 MB of GDScript). Fine for now.

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
- **Changes while the picture is being drawn follow different rules for text
  and sprites.** A text cell written on raster line L shows from line L. A
  sprite is picked for line L from the control words as they are when L
  starts, and drawn with them as they are when it ends: so a strip that is
  moved changes on L, one that is cleared goes from L+1 (and is drawn on L
  at full height). See `refresh()` in `neogeo_video.gd`.
- **MAME's clock inside a Lua tap on the main CPU is not exact** (it was up
  to 100 cycles off); the debugger's `totalcycles` in an instruction trace is.
  The sound CPU's taps are fine.
- **A script error in the game does not end a screenshot run**: the window
  stays open and idle. `verify_session.py` gives up after a while and prints
  the error.
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

- **A new `class_name` is unknown to a headless run** until Godot has scanned
  the project: `Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path
  Project --import` once after adding one.
- **Callables do not keep a RefCounted object alive.** The routine groups
  are stored on the machine for that reason (`Decomp.groups`).

## Repository state

- Work is on `main`; `practice-stage-background` is an older state of it.
- `Godot` in the repo root is a symlink to the editor binary's folder
  (`AGENTS.md` expects it there); it is git-ignored.
