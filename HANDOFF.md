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
| Game logic (recompiled 68000) | The whole game: menus, practice stage, the six stages, ending, attract loop | `verify_session.py`, work RAM after every frame against MAME, see below |
| Video (sprites, shrink, text layer, palettes, changes while the picture is drawn, 96 sprites a line) | Same range | 670 of 681 screenshots pixel-exact |
| CPU timing | 68000 timing tables, interrupt and raster timer timing | Each replay reports it: the port leaves the wait for the vertical blank on the same turn of the wait loop (146 of 202752 cycles) as MAME in about 3 frames of 4, and within one turn otherwise |
| Sound driver (Z80 + chip timers) | Runs the real driver | `compare_ym.py` over the whole game: 72319 of 72322 chip register writes match MAME in order, a median of 0.00 ms apart |
| Sound chip (FM, square waves/noise, sampled channels, stereo) | Synthesised in `Project/sound/ym2610.gd` | `compare_audio.py` on the practice session: MAME's own chip writes replayed into the model leave at most -38 dB of MAME's recording unexplained in any second; levels match. **Not checked by ear** |

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
python3 verify_session.py practice_steer --shots     # RAM + screenshots vs MAME
python3 verify_session.py practice_hold --shots
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
1. **Listen to it.** Everything above is measured against MAME, nobody has
   heard it.
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

### Machine accuracy
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

## Repository state

- Work is on `main`; `practice-stage-background` is an older state of it.
- `Godot` in the repo root is a symlink to the editor binary's folder
  (`AGENTS.md` expects it there); it is git-ignored.
