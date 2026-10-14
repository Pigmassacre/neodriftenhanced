# Modding Neo Drift Out Enhanced

A mod is a folder with a `mod.cfg` in it. Put it in `mods/` beside the game
(at the top of the repository when you run it from there) or in `mods/` in
the game's user folder (on Linux `~/.local/share/godot/app_userdata/Neo Drift
Out/mods`). The **Mods** page of the main menu lists every mod it finds and
turns each on and off. A mod you add is on until you turn it off.
Changes show once you leave that page.

A mod can:

- **replace pictures**: any sprite, ground, letter or HUD digit, in full
  colour and up to four times as fine as the game's pixels;
- **change a car or add one**: speed, acceleration, braking, grip,
  turning, and its looks;
- **make a course**: from one of the game's, with its map of cells
  rearranged, cells repainted, the ground changed, scenery of its own, a
  new start, other times, checkpoints and the other cars' route. It is
  listed in Freeplay. The **Course editor** of the main menu makes and
  changes courses with the mouse;
- **replace sounds and music**;
- **change anything else** in the program ROM's tables, byte by byte.

Mods are applied in the order of their folder names. Where two change the
same thing, the later one wins: name a folder `zz_...` to put it last.
The best times are kept apart while a mod that changes the play (a car, a
course, `[rom]`) is on.

`mod_examples/` has small mods to copy into `mods/`:

- `hd_go_sign` replaces a picture.
- `tuned_cars` changes a car.
- `extra_car` adds a car.
- `relaxed_stage` makes a course.

## mod.cfg

```ini
[mod]
name="My mod"
author="Me"
version="1.0"
description="One line about it, shown on the Mods page."
```

The other sections are below. Values use Godot's ConfigFile syntax:
numbers, `"text"`, `true`/`false`, `[lists, of, values]`. Lines starting with
`;` are comments.

## Pictures

Everything the game draws is made of tiles: 16 by 16 pixels for sprites and
the ground, 8 by 8 for the text layer (letters, the original HUD). A mod
replaces tiles, but you paint whole pictures.

1. Save the game's pictures as it shows them:

   ```sh
   Godot/Godot_v4.7.2-stable_linux.x86_64 --path Project -- --dump-graphics=/some/folder
   ```

   Play to where the pictures you want are shown, then quit. Every picture
   shown is saved once, again if it is later shown brighter, so that what
   is kept is not one caught halfway through a fade:

   - `pictures/ADDRESS.png`: a sprite's picture, named by where its tiles
     are in the program ROM.
   - `ground/ADDRESS.png`: a block of a course's ground, 256 pixels square.
   - `fix/NUMBER.png`: a tile of the text layer.

   Each comes with a `.colours` file: the colours it was painted with.

2. Paint over them. Keep the size, or make the picture 2, 3 or 4 times as
   large, and say so in the mod:

   ```ini
   [graphics]
   scale=4
   ```

   Pixels may be partly see-through, and the edges can be smooth.

3. Put them in the mod's `graphics/` folder under the same names, in
   `pictures/`, `ground/` or `fix/`. `graphics/tiles/NUMBER.png` replaces a
   single sprite tile by its number. Copy the `.colours` file along. With
   it, your picture follows the game's colours as they change: fades, and
   the other cars, which are the same pictures in other colours. Without
   it, the picture is drawn exactly as painted.

The picture is then drawn as many times finer as the window allows, up to
the mod's scale.

Things to know:

- **A tile is replaced wherever it is used.** Pictures share tiles: the
  wheels of a car may be in many of its pictures. If two of your pictures
  paint a shared tile differently, the later one wins.
- **Tiles that are empty in the game are never replaced.** Many pictures
  share them, and painting one would paint them all. The game lists those
  you painted anyway in its log.
- The pictures you save come from your copy of the game. Share mods made
  from them with that in mind.

## Cars

```ini
[car]
replaces=1        ; which car: 0, 1 or 2, in the order of the car choice
top_speed=1.1     ; each a number of times the original's
acceleration=1.2
braking=1.0
drag=1.0          ; how fast it slows down by itself
grip=0.9          ; how well it goes where it points
turning=1.1       ; how fast it turns
```

Leave out what you do not change. The other cars of that make change with
it. The game's tables by speed end not far above the fastest car, so the
top speed stops at about 1.18 times the first car's.

For its looks, add the car's pictures to the mod's graphics as above. The
car choice, the car on the course, and its name are all pictures.

Two car mods for the same car: the later one wins. Turn one off on the
Mods page.

### Adding a car

With `adds=true` the car is one more, and the game's own stays:

```ini
[car]
replaces=0                 ; the car it is made from
adds=true
name="Celica GT-Four RC"   ; as the car choice names it
top_speed=1.15
acceleration=1.4
```

On the car choice, up and down go through the game's car and those added
in its place; the name of the one chosen shows over the car. Any number
may be added to each of the three. An added car's `[rom]` section, if it
has one, is changed only while that car is chosen. It looks like the car
it is made from: pictures replace tiles everywhere, so they cannot tell
the two apart.

## Courses

The easiest way is the **Course editor** on the main menu: choose a course
of the game to start from, or a course to change. It keeps what you make
as a mod in the game's user folder (`mods/course_...`), and **Test drive**
saves it and drives it, then comes back. Its tools, picked with the
buttons along the top or the keys 1 to 6:

- **Cells**: put cells on the map (each comes with its scenery). Right
  click takes the cell under the mouse. **Give the place a cell of its
  own** makes a copy only that place shows, to paint its ground alone or
  its picture in a paint program (`course/cells/NUMBER.png`).
- **Ground**: paint the ground codes (G shows them on any tool). A cell's
  codes are the same wherever the cell is.
- **Scenery**: put things beside the road, drag them, right click or
  Delete takes them away.
- **Route**: the boxes the other cars drive for. Click to choose, drag to
  move, drag the corner to size; clicking off a box adds one after the
  chosen.
- **Start**: click puts the start, Shift and click faces the car; drag
  the lines of the bar that shows how far along the car is.
- **Signs**: the signs of the turns ahead, by place.

The wheel zooms, the middle button (or Space and the left) drags the
view, Ctrl and the wheel goes through the palette, Ctrl+Z and Ctrl+Y undo
and redo, Ctrl+S saves. Name, times, music and Arcade are at the side.

What the editor writes is what follows: a course can be made or changed
by hand just as well.

A course is a map of cells. Each cell is 256 by 256 pixels, and has its
picture, its ground codes (what a car finds there) and its scenery. The
map is 16 cells across and 128 down. A course goes round and round across
it, so the road leaving it at the right comes back at the left.

Start from one of the game's courses:

```sh
Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path Project -s res://tools/export_course.gd -- --course=1 --to=mods/my_course
```

That makes a mod of course 1 (0 is the practice course) that plays just
like it, as an extra entry in Freeplay. Then change what you want:

```ini
[course]
base=1                 ; the course it is made from
name="Stage 1, my way" ; as Freeplay lists it
arcade=false           ; true: also driven in place of course 1 in Arcade
start=[384, 16000]     ; where the car starts, in pixels of the course
facing=341.37          ; which way it faces, in degrees: 0 right, 90 down, 270 up
time=[40.0, 23.0]      ; seconds at the start, then gained at each checkpoint
progress=[16000, 8832, 1152]  ; y of the start, each checkpoint and the finish,
                              ; for the bar at the right
rivals_from=[2, 5, 6, 15]     ; the waypoint each of the other cars starts at
music=1                ; the course whose music plays
```

The car's y gets smaller as it drives up the course. Moving the start also
moves the other cars' start. In the `course/` folder:

- `map.txt` has the number of the cell at each place: 128 lines of 16
  numbers. Rearrange cells to change the course's shape.
- `cells/NUMBER.png` is a cell's picture, 256 pixels square, or 512, 768 or
  1024 with the mod's `[graphics] scale`. The exporter puts the game's
  pictures of all cells in `cells_from_game/`, where they are not used.
  Copy those you paint to `cells/`; a picture there becomes new tiles of
  its own, so it changes that cell alone.
- `codes/NUMBER.png` holds a cell's ground codes: 32 by 32 pixels, one for
  each 8 by 8 pixels of the cell. The code is the pixel's red divided by
  two; green and blue only make the picture readable. `codes.txt` lists
  every code with its colour and what it is on that course. In short:
  - **0 to 31** are walls, by the way they face.
  - **32 to 63** are edges (kerbs, banks), by their direction.
  - **64 to 127** are open ground, each a surface of the course. Among
    them are the finish line and the two strips of each gate: driving
    through a gate's first strip and then its second passes a checkpoint.
  - Paint with the exact colours `codes.txt` gives.
- `signs.txt` is the map of the signs that come up (the turns ahead): a
  number for each place, 0 for none.
- `waypoints.txt` is the way the other cars drive. Each line is a box they
  aim for: its middle (x, y), width, height, and the speed to slow down to
  on the way there.
- `scenery.txt` is the things beside the road (trees, spectators,
  barrels), a line for each: x, y and kind, where x and y are the foot of
  the thing. Without it, each cell's scenery goes with it wherever the
  map puts it, as in the game. The exporter writes it with `--scenery`.

A cell number past the course's last (255) is a new cell. It needs its
picture in `cells/` and its codes in `codes/`.

Driving a mod's course from the command line:

```sh
Godot/Godot_v4.7.2-stable_linux.x86_64 --path Project -- --stage=1 --mods=my_course --course-mod=my_course
```

## Sounds and music

Put files named by the sound's number in the mod's `sounds/` folder, as
`.ogg`, `.wav` or `.mp3`:

```
sounds/24.ogg    ; the music of stage 1
sounds/D4.wav    ; a sound of the race
```

The numbers are hexadecimal, as the game prints the sounds it asks for
when run with `--log-sounds`:

```sh
Godot/Godot_v4.7.2-stable_linux.x86_64 --path Project -- --log-sounds
```

The music of the courses is `21` (practice) and `24` to `29` (stages 1 to
6). `20` to `3F` are music, which plays round and round until other music
is asked for or the music stops; everything else plays once. The music
and effects volumes of the options apply to them.

## Anything else: [rom]

The program ROM's tables can be changed directly. Each key is a bus address
in hexadecimal, and each value is either the bytes from there on as hex
digits, or the words from there on as numbers:

```ini
[rom]
0x22462="0100 0200"     ; bytes
0x2DEF4=[1, 0]          ; words
```

The hand-written game in `Project/game/` names the tables it reads by
address (the `const` at the top of each file), with what they hold.

## For testing

- `--mods=ID,ID` uses just those mods, also in automated runs.
- `--no-mods` uses none.
- `--mod-folder=PATH` looks in another folder too.
- `--course-mod=ID` with `--stage=N` drives a mod's course.
- `--editor=N` opens the course editor on a new course made from course
  N, and `--editor=FOLDER` on the course of that mod.
- `--log-sounds` prints every sound the game asks for.
