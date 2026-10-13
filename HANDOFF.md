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
   against its translated original. **Done as far as the game goes**: the
   game runs on the hand-written code alone, and that is how it is started
   (see "The game without the translated program" below). The translated
   program is loaded only to compare with the original.
4. Draw from the game's own records instead of the hardware's video RAM.
   **Done** (see "Drawing" below): the sprite builder and the ground code
   are no longer run by the game, and a race is drawn up to 640 pixels wide.

Nothing derived from the ROMs may be committed: `data/`, `neodrift/` and
`neogeo/` are git-ignored on purpose. The hand-written code in
`Project/game/` is committed; the tables it reads stay in the ROM and are
referred to by address.

## The game without the translated program

`MachineLoader.create(hand_written, translated)`: without `translated` the
machine is a plain `NeoGeoMachine` with no blocks, `Decomp.install_native`
puts every hand-written routine in its table, and `machine.native` is
`game/main_loop.gd`'s `frame`, which `run_frame` calls once a frame. That
is what `game.gd` runs unless it is asked to compare with the original
(`--original-program`, `--translated`, `--seedlog`, `--compare-views`,
`--hardware-video`, `--keep-video-ram`). It loads in under a second; the
translated program takes five.

- `main_loop.gd` is the original's start-up (`$122`, `$744`, `$B34`), its
  interrupt at the start of a frame (`$22C`) and one turn of its loop
  (`$B80`) with the twenty states under it. The original waits in the loop
  for the interrupt; here a frame is one call.
- `system.gd` is what the game needs of the board's system program,
  written anew from what that program does and not from its code: the
  players' sticks and buttons, coins and credits, the start of a game, the
  title asked for when a credit is in, and three services the game calls.
  None of the system's accounts, tests or screens.
- `native_drawing.gd` has `$120E0` and `$133FA` without what they do to the
  video hardware; the picture comes from `GameScene`, which stands in for
  `$1229E`, `$13546` and `$1348E` as before.
- `m.call_routine(address)` calls the hand-written routine at an address
  (the routines still call each other by address in many places, with the
  registers the original would have had). An address nothing is written
  for is reported once (`no routine at $...`) and skipped.
- The machine still starts from `data/game/start.snapshot`, for what the
  system had left in memory when the game was first given the screen: the
  board's settings, the lists of best times, the palettes. The registers
  and the program counter in it are not used.
- Hand-written code takes no time, so there is no clock: the random
  numbers are stepped a number of times a frame that depends on the stick
  (`main_loop.gd`, `frame`), where the original steps them for as long as
  it waits.

`Project/tools/native_probe.gd` runs it without a window as fast as it
goes and prints the states it passes through and anything missing:

```
Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path Project -s res://tools/native_probe.gd -- --frames=30000 --coin=100 --drive
```

What is not checked against the original, because it has no counterpart
that returns or because the original does more: `frame`, `begin_frame`,
`turn`, `set_going`, the two states that give the screen back (`$CC6`,
`$E6E`), `system.gd`'s `every_frame`, and `native_drawing.gd`. They were
tried by running: the attract mode through all its courses, a game from a
coin to game over and back to the attract mode, a race driven.

What was left out as never reached on an arcade board without a card
slot: the states of a home console (14-17: `$7E1C`, `$7E86`, `$72BC`,
`$7314`), the screens of a memory card (5 and 11: `$1A118`, `$1A1CA`), the
start of a game on a board for America (`$806`) and on a console (`$88A`),
and the first set-up of the best times (`$10D0`-`$1278`, done before the
snapshot).

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
- Hand-written code takes no CPU time. **The owner does not want the
  original's slowdown kept** (asked 2026-10-12), so nothing charges
  artificial time for it; see "Three things to know" below.
- Hand-written code itself cannot be interrupted part way and must never
  wait for an interrupt. The original's sound request did (`$15256`, when
  its queue of eight is full); `sound_requests.gd` keeps the overflow in a
  list instead.
- Translated code called from hand-written code does take interrupts
  (`call_routine` handles the frame's events as `run_frame` does). Some of
  it waits for the vertical blank: the sprite builder `$1229E` and the
  ground scroll `$13546` wait until the interrupt has taken their last
  output. If that runs past the end of the frame, the next frame begins
  inside the call and that `run_frame` lasts two frames, which is the
  original dropping a frame.

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
depends on a "scratch" register shows up there. A call that an interrupt
arrives in is not compared: it is left to the original alone, block by
block as usual (the report says how many; the routines it calls are still
checked), and a routine called by a hand-written routine that is itself
being checked is not checked a second time. What depends on time (cycle
count, raster timer, logged times) is taken from the original's run.
**State: all 210 routines agree on every call of all nine sessions, and the
sessions match MAME exactly as far as the translation alone does.**

Branches that no session takes are checked through **variations**: a group
may give, per routine, ways to alter the state the routine is entered with
(`variations()` in `game_routines.gd`; `rival.gd` and `hud.gd` have
examples). On every fourth call of such a routine the check also compares
original and hand-written from one of those states and then throws the
outcome away, so the session itself is not affected. Routines the original
calls during a varied call are checked as usual, which pins a difference
to the routine it is in. The report counts the varied calls, and those the
original could not run from that state ("more not run": it ran into
untranslated code or an interrupt was due). This is how the other cars
were checked on screen, in the air, spinning and touching the player's
car: no recorded session has any of that. Branches without a variation
are still unchecked; the listing marks them "ran 0 times".

Never compared so far, though simple: in `game_flow.gd` the states that set
up a long screen (an interrupt always arrives in them: car choice, course
introduction, result, continue, ending, name entry) and those no session
reaches (name entry for one of the three best times, choosing a car after
continuing, pausing on a home console); `wait` in `rival.gd`.

Checking all nine sessions takes about ten minutes with the sessions run
side by side (one `verify_session.py <session> --keep-recording
--check-routines` each, in the background); never run the same session
twice at once, they share their output files.

Other switches: `--translated` leaves the hand-written routines out;
`--only-routines=E8BA,EAA8` uses just those; `--profile` rewrites the
block profile `routines.py` reads; `replay.gd --watch=OFFSET` reports every
change of a work RAM word with the block and raster line.

What is known so far is in the code, `Project/game/`:

| File | What it is | Routines |
|---|---|---|
| `game_flow.gd` | The three state machines above a race: the game (car choice, courses, ending, name entry), the courses of a game (introduction, race, result, continue) and the race (start, driving, finish, pause) | 38 |
| `race.gd` | The order of a race's frame (`$B844`) | 2 |
| `car.gd` | The player's car (object at `$101508`, in A6): one frame of it (`$D956`), normal driving (`$DAAC`), spinning (`$DBF0`, `$DDA4`), flying (`$DFC8`), drawing it, the camera, damage, dust, skid marks, sparks, backfire, and its sounds | 72 |
| `rival.gd` | The three other cars (`$10126C`, `$D8` bytes each): steering along waypoints, the same grip and sliding as the player's car, spinning, flying, touching the player's car, drawing, dust and sparks | 48 |
| `engine_sound.gd` | Gears by speed and the notes they ask for | 7 |
| `race_clock.gd` | Time left, time gained at checkpoints, times taken | 5 |
| `hud.gd` | Time taken, time left (with the voice counting down), speed, the bar to the next checkpoint, the slow-ground warning | 7 |
| `course_signs.gd` | Signs the course brings up where the car drives into a marked cell | 3 |
| `course_objects.gd` | Scenery and effects on the course: 24 slots, kept for a window around the camera | 15 |
| `sprite_object.gd` | The setters of the records things are drawn from | 5 |
| `text.gd` | The text layer: drawing a block of cells and writing characters | 3 |
| `ground.gd` | The ground code under a point (`$13E74`), with the packed block format | 1 |
| `angles.gd` | The direction of a vector (`$1014C`) | 1 |
| `sound_requests.gd` | Asking for a sound and sending it on from the interrupt | 2 |
| `random.gd` | The random number step | 1 |

Things learnt that the enhancements will need:

- **How things get on screen.** Everything but the ground and the text
  layer is a "sprite object": one of 64 records of `$16` bytes at `$101B20`
  (`sprite_object.gd` names the fields: shown, depth, x, y, zoom, picture).
  A picture is two words (columns, tiles per column) followed by a tile
  word and an attribute word for each tile, column by column. Once a frame
  `$1229E` gathers the shown ones (`$13330`), sorts them by depth into the
  list at `$1020A4` (count at `$1020A2`; six bytes each: depth, address) and
  writes hardware sprites from them until 128 are used, into one of two
  sprite ranges that the vertical blank swaps (`$12188`). A native renderer
  can draw from that list instead of from video RAM.
- **The ground** is 32 hardware sprites of 32 tiles used as a scrolling
  tile map (`$1348E` redraws all, `$13546` scrolls a column or row in as the
  camera crosses 16 pixels, `$13646` sets positions in the vertical blank,
  and the raster interrupt `$136BA` wraps it vertically). It is drawn from
  `GROUND_CAMERA` and `GROUND_ZOOM` (`car.gd`), which is all the standalone
  course viewer (`Project/main.tscn`) needs. The game no longer runs this
  code; see "Drawing" below.
- **A wider view needs a wider window for scenery**: `course_objects.gd`
  keeps things only within 512 by 512 course pixels around the camera
  (`WINDOW_LEFT`, `WINDOW_ABOVE`, `WINDOW_SPAN`), and there are only 24
  slots and 64 sprite objects. The car's `is_on_screen` and the camera's
  look-ahead (`aim_camera`) also assume 320 by 224.
- **The shadow is faked translucency**: `draw_shadow` shows it every other
  frame (`SHADOW_FLICKER`). The scene draws it on every frame at half
  strength instead, see "Translucency" under "Drawing".
- **The other cars are never near in the recorded sessions.** They only
  look at the ground while within 800 by 384 course pixels of the camera
  (`NEAR` in `rival.gd`), are only drawn while `ON_SCREEN` (a test against
  320 by 224 with a margin), and far away they drive on plain road. A wider
  view needs both tests widened. Their shadows are drawn on the frames on
  which the player's car has none.
- **The HUD is text-layer cells at fixed addresses** (`hud.gd` has them as
  constants) plus three sprite objects for the checkpoint bar. Times are
  counts of frames in 16.16 fixed point (`race_clock.gd`); the speed shown
  comes from a table by sixteenths of the car's speed. A reworked HUD can
  read the same values and leave these routines out.
- **A home console pauses with the start button** (`race_pause` in
  `game_flow.gd`); an arcade board does not, and continues with credits.
- Rules found on the way: when the time runs out (`TIME_UP`) the race goes
  on to the next gate; scraping walls wears the car down in four stages
  that lower its top speed (`wear_down`); `leave_skid_marks` in one case
  uses whatever register D7 happens to hold (kept as it is, marked in the
  code).

Where to go next, roughly in this order:

1. Finish the wide view, see "Left to do" under "Drawing" below.
2. What `game_flow.gd` still calls by address: the screens around a race
   (car choice `$15C20`/`$15C9C`, course introduction `$1BE56`/`$1C374`,
   start `$B978`/`$B98C`, finish `$BE50`/`$BE90`, result `$4150`/`$4248`,
   continue `$15282`/`$15354`, ending `$4B8A`/`$4CB4`, game over, name
   entry, best times). These are what "reworked menus" will replace or
   rewrite.
3. Left in the race: the remaining kinds of scenery (`$16BF2` is the one a
   car knocks over, `$16E62` moves across; their set-up stubs from `$16FEA`
   on all end in `$16B04`), what plays a course sign (`$14804`, `$1485C`),
   the driving states of the table at `$DA72` that no session reaches, and
   what the car-touching test calls (`$1A962`, `$1A9A6`). Write variations
   for what no session reaches.
4. The main loop and the attract mode.

Three things to know:

- **Without `--check-routines`, a run with hand-written routines drifts
  from MAME** where the original needs more than a frame for a frame's work
  (first in the menus, frame 2005 of `practice_steer`): the original drops
  a frame there and hand-written code, taking no time, does not. The game
  plays the same; it just does not slow down, which is wanted. So
  `--shots`, which runs the real game, is only pixel-exact with
  `--translated`.
- **Registers passed on to translated code.** A hand-written routine that
  calls a translated one sets the registers the original would have had at
  that point, as far as anything can read them (`add` in
  `course_objects.gd` is the example). A set-up routine of a kind of
  scenery that no session meets could still read one that is not set.
- A new script in `Project/game/` goes into `Decomp.GROUPS`. `routines.py`
  finds hand-written routines by lines of the form `<tab><tab>0xADDR: name,`
  in `routines()`.

## Drawing

`Project/video/game_scene.gd` (`GameScene`) takes what the game wants drawn
at the moments it hands it to the hardware, and `NeoGeoVideo` draws that
instead of video RAM while the game has the screen (bit 7 of `$10FD80`; the
system ROM's own screens are still drawn from video RAM):

- **Objects.** At the sprite builder's entry (`$1229E`) the shown records
  are sorted as the original sorts them and turned into "strips", one for
  each column of each picture, with the original's arithmetic for zoom
  (`_gather`). A strip is what a hardware sprite was, so the same shader
  draws both, but there can be any number of them, anywhere.
- **The ground.** At `$13546` the camera, the zoom and the course's map are
  noted. `NeoGeoVideo._look_up_ground` works out, for every pixel across
  and every line down, which tile of the map and which pixel of it is
  there, exactly as the original's 32 hardware sprites and the hardware's
  shrink tables would show it, and carries on the same way to the sides.
  `ground.gdshader` then draws from the map itself (`_load_map` makes
  textures of it when the course changes).
- **Text** is still the hardware's text layer, read from video RAM.
- **Colours**: the game queues colour changes for the vertical blank;
  `colours_to_come` applies those not yet taken, as they belong to the
  picture just built.

Two ways of running it:

- The game (`game.gd`) calls `replace_hardware_drawing`: the original's
  `$1229E`, `$1348E` and `$13546` are replaced by code that only notes the
  scene. Video RAM then has no game picture at all, a frame takes about
  half the time (1.5 ms instead of 3.2), and the picture is shown as soon
  as it is built, a frame earlier than the hardware would. Work RAM is then
  not what MAME has (the builder's buffers stay empty), so this is not
  used when verifying. `--keep-video-ram` leaves the original code in too;
  `--hardware-video` draws video RAM only.
- For checking, `verify_session.py <session> --translated --compare-views`
  runs the game with both pictures drawn every frame, the scene with the
  hardware's timing and limits (`hardware_timing`: taken at the vertical
  blank after it is built; `hardware_limits`: 128 columns), and compares
  them pixel for pixel. It needs a display. **State: over all nine sessions
  (67,000 frames) the two are identical but for about 60 frames**, all of
  three kinds: the frame of a screen change, where the hardware picture is
  cut part way down; the ground's bottom few lines on single frames (the
  original's raster split arriving late); and the first frames of a
  session, before the scene has been built once. Frames where the hardware
  ran out of sprites on a line (about 100) are counted apart: the scene
  has no such limit.

The wide view: `NeoGeoVideo.view_width` (the window's width in game pixels,
at most `WIDEST_VIEW` in `game.gd`). The hardware's 320 pixels are the
middle of it, so everything the game places is where it was. What is drawn
beyond them:

- **A race** (`GameScene.in_race`: the ground is on and there are HUD
  objects, which have depths from `$7000`) is drawn in full. The machine's
  `view_margin` tells the hand-written game code how much wider the picture
  is: the scenery window (`course_objects.gd`), the other cars' `ON_SCREEN`
  and the car's `is_on_screen` allow for it. With 0 they are the original,
  which is what the routine check runs.
- **Other screens** keep their objects to the middle 320 pixels (they park
  things just off the hardware's screen, and rely on positions coming
  round in nine bits), but their backdrop is repeated to both sides. A
  backdrop is one of two things. Either the objects drawn first, when they
  are a row of pictures as high as the screen that lie side by side across
  it (`GameScene._find_backdrop`; the menus' scrolling "Drift Out", the
  stage introductions). Or the ground, where what shows of it repeats
  itself tile for tile at least twice (`NeoGeoVideo._ground_period`; the
  rankings and totals). A picture that does not repeat (the title, the
  ending) has the colour behind everything at its sides.
- **The text layer** stays in the middle (`fix.gdshader`). The game fills
  its first and last column (two on some screens) with a black tile to
  hide the ground's ragged edges; those columns are left out. It also
  blacks the screen out with black tiles for the wipes between screens;
  where the next column in holds a tile of one colour, that colour is
  carried on to the picture's edge, so a wipe covers the sides too (row by
  row, not along the wipe's diagonal).
- **The HUD** of a race goes to the picture's edges: the text layer is
  drawn in three parts (columns up to 14 in the upper half and up to 12 in
  the lower go left, columns from 26 go right; a row with text across such
  a boundary is left whole), and HUD objects from x 256 on (the checkpoint
  bar) go right. This is knowledge of this HUD's layout, to be replaced by
  the reworked HUD of `TODO.md`.

More room (`NeoGeoMachine.more_room`, set by `Decomp.make_room`, which the
game calls unless run with `--translated`): the original has 24 slots for
things on the course and 64 object records, and a picture twice as wide
ran out of slots. With more room there are 40 more slots at `$108000` and
64 more records at `$109000`, in work RAM the original never touches
(`$103AF8`-`$10F1BD` stays zero through every recorded session). The
tables are not moved: the hand-written routines that walk them
(`course_objects.gd`, `sprite_object.gd`'s `take_free_record`) carry on
into the extra ones, and `room_hooks` add them where translated code sets
the originals up or clears them (`$14102`, `$1413C`, `$1217A`). A game
started from a snapshot in mid-course has no extra slots until the next
course. At 640 wide Stage 1 uses at most 29 slots.

Left to do:

- The camera still frames the car for 320 pixels (`aim_camera`).
- Screens whose backdrop is one picture 320 wide (the stage introductions)
  repeat it with a visible seam.
- Never looked at in a wide view: two players, continuing, name entry
  after a ranked game, and the other cars in a game (the attract demos'
  were).
- With the builder gone, `show_course`'s test for a camera jump and the
  two sets of ground positions are dead weight, and the picture could be
  built from the car and scenery directly instead of through the object
  records.

### Translucency

The original fakes a thing one can see through by showing it on every other
frame only: the cars' shadows (the player's on one frame, the other cars'
on the next), and scenery a car has knocked over (barrels, cones) until it
is gone. With `GameScene.translucency`, a record whose first word has gone
1, 2, 1 or 2, 1, 2 over the last three frames is drawn on every frame, at
half strength (a seventh number for each strip, bit 10 of the packed word
the sprite shader gets). It takes two frames to notice, during which the
thing flickers as it did. Nothing else in the recorded sessions is shown
and hidden in turn.

A hidden shadow is not placed by the original; with
`NeoGeoMachine.steady_shadows` the hand-written `draw_shadow`s place it on
every frame. Both are off when comparing with the hardware's picture.

### The window

`game.gd` draws the game's picture, in game pixels, into a viewport of its
own (`_screen`) and shows that in the window with `_picture`, enlarged to
the window's height: by any amount, with `video/enlarge.gdshader` keeping
game pixels sharp, or a whole number of times with `--whole-pixels`. The
project's own stretching is off, so what is drawn over the picture is at
the window's resolution. Screenshots (`--shot`) are of `_screen`, so they
are in game pixels as before; `--window-shot` takes the window.

- **`video/crt.gdshader`** (F2, `--crt`) is the picture-tube look:
  scanlines with beams wider where brighter, pixels run together across,
  a stripe mask and a little glow. Only used from three screen pixels to a
  game pixel. Its amounts are uniforms, for an options menu to set.
- **`hud/minimap.gd`** (M, `--no-map`) is the map in a race, on every
  course. The game has no picture of a course as a whole, so the road is
  found in the ground's codes (`ground.gd`: one for every 8 by 8 pixels,
  16 by 128 cells of 256 pixels on every course): from where the car
  starts, everything reachable without crossing a wall (codes below `$20`)
  or slow ground (open ground of surfaces 8 to 13, which lines every road),
  not going back behind the start, up to the first finish line met (surface
  7; the road goes on past it into repeats of itself). That takes about a
  second, so it runs on a worker thread. A course is wider than the ground
  is across (4096 pixels) and goes round it several times, so the search
  keeps for every place how many times round it was (`_turns`), and a car
  is put on the map by the road under it, or failing that from where it
  last was. Road more than `OFF_ROUTE` from the other cars' waypoints
  (`rival.gd`) is drawn in another colour: the ways they do not take. The
  practice course has no waypoints, so none there. The driven part is the
  car's own trail. It is shown while `NeoGeoVideo.hud_shown`, and is not
  behind the CRT look.
- **`hud/race_hud.gd`** (F3, the Game options, `--hud=`) is the HUD of a
  race drawn with a scalable font: time taken, time left, speed, the bar to
  the next checkpoint, the stage and "Speed down". It reads the game's own
  values (`hud.gd`, `race_clock.gd`). While it (or no HUD) is chosen,
  `NeoGeoVideo.own_hud` leaves the original's out: in a race everything on
  the text layer is HUD (credits line included), so the layer is emptied
  between its masking columns, and the three objects of the checkpoint bar
  are skipped (`GameScene.hud_hidden`). The countdown, "Check Point",
  the turn signs and the banners are other objects and stay as they are.
  An automated run keeps the original's HUD.
- **Controls** are input actions (`game_up`, `game_a`, ...) made by
  `settings.gd` from the player's choices: a key and two gamepad places
  each. Every connected pad is player 1; there is no second player.

### The menus

`menu/menu.gd` is the main menu, the options and the pause menu, drawn over
the picture at the window's resolution; `settings.gd` holds the options and
keeps them in `user://settings.cfg`. `game.gd` does what a choice means:

- **The main menu is over the original's attract mode**, the machine
  running with no inputs. Choosing a game restarts the machine from the
  start snapshot and works its inputs behind a black screen
  (`_starting_inputs`): a coin, start at the title, and for a single stage
  A through "how to play" and the name entry as well. It goes by the main
  loop's state at `$100426` (0, 1 attract; 12, 13 title with a credit; 2, 3
  how to play; 4, 18, 19 name entry; 6, 7 the game; 10, 8, 9 after it).
- **Freeplay** is a game of one stage: `NeoGeoMachine.first_course` is the
  course `start_game` (`game_flow.gd`) starts with, and `_follow_game`
  goes back to the menu when the course changes, the game asks to be
  continued or is over.
- **Back to the menu** always restarts the machine (a credit left in would
  start a game by itself at the title), and sends the sound driver its
  reset command (3). So best times do not outlast a game.
- **Free continues**: a coin is put in when the continue screen appears.
- **Pause** is the machine not being stepped. A button that is both pause
  and start (Start on a gamepad) pauses only while driving.
- **Music and effects volumes**: the driver plays music as long samples on
  the first sampled channel and effects on the last three (measured over
  6000 frames; the FM part made no sound at all there), so the two gains
  are per sampled channel (`SoundBoard.set_volumes`).
- An automated run (`--input`, `--shot-frame`, `--frames`, `--snapshot`,
  `--seedlog`, `--compare-views`, `--no-menu`) has no menus and reads no
  stored options: the verification tools are unaffected.
- To try the menus without hands: `--press=TICK:KEY,...` presses keys,
  `--shot=PATH --shot-tick=N` takes a window screenshot,
  `--settings=PATH` keeps the options elsewhere, `--menu=PAGE`,
  `--arcade` and `--stage=N` start where the menu would lead.

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
python3 verify_session.py practice_steer --translated --compare-views   # the scene against video RAM
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
14. Of the enhancements of `TODO.md`, these are in (see "Drawing" above):
    the wide view, menus included; real translucency; the minimap; gamepads;
    a CRT shader; the reworked menus with stored options; the reworked HUD.
    The menus were only tried with scripted key presses: no gamepad, no
    mouse, not by hand.
15. Generated code load time is about 5 s (6 MB of GDScript). The game
    itself no longer loads it.

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
