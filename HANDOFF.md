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
| Game logic (recompiled 68000) | Practice stage, menus, attract mode | `verify_session.py practice_steer`: 4042 of 4045 frames of work RAM identical to MAME |
| Video (sprites, shrink, text layer, palettes, mid-frame background move) | Same range | 40 of 40 screenshots pixel-exact |
| Sound driver (Z80 + chip timers) | Runs the real driver | `compare_ym.py`: 1835 of 1859 chip register writes match MAME in order |
| Sampled sound (ADPCM-A) | Plays through Godot | Recorded output is non-silent from the title screen on; **not checked by ear or against MAME's audio** |

The few non-identical RAM frames are single frames at screen transitions that
re-converge; believed (not proven) to come from approximate CPU timing.

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
- Sound: record chip writes in MAME with a job containing `ymlog = {first, last}`
  (see `Tools/mame/harness.lua`), then
  `godot --headless --path Project --script res://tools/sound_replay.gd -- --ymlog=IN --out=OUT`
  and `python3 Tools/compare_ym.py IN OUT <frame after a "cmd 03">`.
- When a frame differs, `Tools/compare_video.py` (video RAM word by word) and
  `Tools/render.py` (reference renderer, exact on MAME dumps) tell you whether
  the machine state or the Godot drawing code is wrong.

## Remaining work, roughly in priority order

### Sound
1. **Check the sampled sound by ear and against MAME** (`mame -wavwrite`).
   Unknowns: the exact end-address rule for ADPCM-A samples (inclusive end
   block assumed), and whether one looping engine sample restarts ~50 frames
   later than in MAME (seen around MAME frame 3193 of the steering session —
   investigate the end-of-sample flag timing in `sound_board.gd`).
2. **SSG** (three square-wave channels, noise, envelope): the driver writes it
   (466 writes in the test session) but nothing is synthesised. An
   `AudioStreamGenerator` fed from the register state is the obvious route.
3. **FM** (58 writes in the test session, so little used) and **ADPCM-B**
   (21 writes): not synthesised.
4. **Panning**: the left/right bits only gate audibility; no stereo placement.
5. **Speed**: the Z80 interpreter costs about 10 ms per frame, so it runs on a
   worker thread. The driver's main loop busy-polls a command queue
   (`$013D` onwards in `data/dasm/m1.asm`); skipping that idle loop, or
   recompiling the driver like the 68000 program, would cut this a lot.
6. The sound board starts the cartridge driver from reset; on hardware the
   BIOS's own driver runs first. No effect seen, but it is a difference.

### Game coverage
7. **Stage 1 and beyond are untested.** Add sessions that play on, run them,
   and fix what turns up. If play reaches untranslated code the game stops and
   appends the address to `data/game/seeds.txt`; re-run
   `Tools/recomp/build_code.py`. If a new *pattern* of missed code shows up,
   teach `Program.explore` in `Tools/recomp/gen.py` about it rather than
   relying on the seed file (see the existing rules for jump tables, offset
   tables, pointer scans and unrolled loops).
8. Other cars, two-player, service/test mode: untested.

### Machine accuracy
9. **CPU cycle counts are rough** (`cycles()` in `gen.py`). Consequences:
   slowdown will not match hardware, free play gets different random numbers
   than MAME, and the transition blips above. A proper 68000 timing table
   would fix most of it.
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
      `bios.asm`, `m1.asm`) with MAME's debugger; `Tools/dasm.py` prints a
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
- Godot resolves relative paths from the project folder; pass absolute paths
  to the tools under `Project/tools/`.
- The program ROM file is word-swapped, with its second megabyte at bus
  address 0 and its first at `$200000`.

## Repository state

- Branch `practice-stage-background` (not merged to `main`).
- `Godot` in the repo root is a symlink to the editor binary's folder
  (`AGENTS.md` expects it there); it is git-ignored.
