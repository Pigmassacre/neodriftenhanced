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
- **change a car**: speed, acceleration, braking, grip, turning, and its
  looks;
- **make a course**: from one of the game's, with its map of cells
  rearranged, cells repainted, the ground changed, a new start, other
  times, checkpoints and the other cars' route. It is listed in Freeplay;
- **change anything else** in the program ROM's tables, byte by byte.

Mods are applied in the order of their folder names. Where two change the
same thing, the later one wins: name a folder `zz_...` to put it last.
The best times are kept apart while a mod that changes the play (a car, a
course, `[rom]`) is on.

`mod_examples/` has three small mods to copy into `mods/`:

- `hd_go_sign` replaces a picture.
- `tuned_cars` changes a car.
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

## Courses

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
facing=341.37          ; which way it faces then, in degrees
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
  aim for: x, y, width, height, and the speed to slow down to on the way
  there.

A cell's scenery (trees, spectators, barrels) goes with it wherever the
map puts it. Scenery of your own is for the level editor still to come.

Driving a mod's course from the command line:

```sh
Godot/Godot_v4.7.2-stable_linux.x86_64 --path Project -- --stage=1 --mods=my_course --course-mod=my_course
```

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
