extends RefCounted
## Courses made by mods: a mod.cfg's `[course]` section makes a course from
## one of the game's, with what the mod's `course` folder and the section
## change (MODDING.md has it all):
##
##     [course]
##     base = 1              ; the course it is made from: 0 (practice) to 6
##     name = "Hill climb"   ; as Freeplay lists it
##     arcade = false        ; true: driven in place of `base` in Arcade too
##     start = [384, 16000]  ; where the car starts, in course pixels
##     facing = 341.0        ; which way it faces then, in degrees
##     time = [40.0, 23.0]   ; seconds at the start, then gained at each checkpoint
##     progress = [16000, 8832, 1152]  ; y of the start, the checkpoints, the finish
##     rivals_from = [2, 5, 6, 15]     ; the waypoints the other cars start at
##     music = 3             ; the course whose music plays
##
## A course is a map of cells of 256 by 256 pixels: 16 across (the course
## goes round and round across) and 128 down, each cell one of up to 256
## numbered cells, each with its picture, its ground codes and its
## scenery. In the folder:
##
## - `map.txt`: the cell number of each place, a line for each row.
## - `cells/NUMBER.png`: a cell's picture, 256 pixels square (times the
##   mod's [graphics] scale), in full colour.
## - `codes/NUMBER.png`: a cell's ground codes, 32 by 32, one pixel for
##   each 8 by 8 of the course, the code in the pixel's red (see
##   `code_colour`).
## - `signs.txt`: the map of the signs that come up (the turns ahead),
##   a number for each place, a line for each row.
## - `waypoints.txt`: the way the other cars drive, a line for each point:
##   x, y, width and height of the box that counts as reaching it, and the
##   speed to slow down to on the way.
##
## tools/export_course.gd makes such a mod of a course of the game, to
## start from.

const COURSES := 0x200000
const COURSE_COUNT := 7
## The record of a course: the addresses of its map (for the ground), its
## ground's blocks, its map (for the codes), its cells' codes, its map (for
## the scenery), its cells' scenery and its map of signs.
const RECORD_WORDS := 14
const GROUND_MAP := 0
const GROUND_BLOCKS := 4
const CODE_MAP := 8
const CODE_CELLS := 0xC
const SCENERY_MAP := 0x10
const SIGNS := 0x18
## By course: the player's car's start ($19 words from OWN_SURFACE, see
## car.gd), and the other cars' ($16 words each, three).
const COURSE_FIELDS := 0x23702
const START_WORDS := 0x19
const RIVAL_FIELDS := 0x209EE
const RIVAL_WORDS := 0x16
const RIVALS := 3
## By difficulty, then by machine, the clock: a frame's time and the
## address of the times by course (seven 16.16 values: at the start and
## gained at each checkpoint).
const CLOCKS := 0x2DEB4
## The difficulty is the board's setting, 16 levels (pairs of which share).
const DIFFICULTIES := 16
const MACHINES := 3
const TIME_WORDS := 14
const FRAMES_PER_SECOND := 60
const CHECKPOINTS := 0x2240E
const WAYPOINTS := 0x2101E
const WAYPOINT_COUNTS := 0x2103A
const FIRST_WAYPOINTS := 0x21048
const FIRST_WAYPOINT_BYTES := 8
const COURSE_MUSIC := 0xF8C2
## Packed codes: a byte below $80 is a code, $80 ends, any other byte is a
## count of the code after it (game/ground.gd).
const PACKED_END := 0x80
const CELL_SIZE := 256
const CODES_ACROSS := 32
## The tile numbers a course's own pictures are given: past the game's.
const FIRST_NEW_TILE := 0x10000
const LAST_NEW_TILE := 0xFEFFF


static func is_course(mod: Mods.Mod) -> bool:
	return mod.config.has_section("course")


static func base_of(mod: Mods.Mod) -> int:
	return clampi(int(mod.config.get_value("course", "base", 1)), 0, COURSE_COUNT - 1)


static func in_arcade(mod: Mods.Mod) -> bool:
	return bool(mod.config.get_value("course", "arcade", false))


static func name_of(mod: Mods.Mod) -> String:
	return str(mod.config.get_value("course", "name", mod.name))


## The colour a ground code is painted in, in a `codes` picture: the code
## twice over in red (only that is read back), and green and blue to tell
## walls (dark), edges (orange) and open ground (by kind) apart.
static func code_colour(code: int) -> Color:
	if code < 0x20:
		return Color8(code * 2, 0, 40)
	if code < 0x40:
		return Color8(code * 2, 110, 0)
	return Color8(code * 2, 120 + (code & 0xF) * 8, ((code >> 4) & 3) * 80)


static func code_of(colour: Color) -> int:
	return clampi(colour.r8 >> 1, 0, 0x7F)


## Makes the machine drive the mod's course in place of its base. New
## pictures of cells get tile numbers of their own, which are added to
## `new_tiles` (tile number: [picture, scale]) for mods/mod_graphics.gd.
static func apply(machine: NeoGeoMachine, mod: Mods.Mod, extra: Mods.Extra, new_tiles: Dictionary) -> void:
	var base := base_of(mod)
	var config := mod.config
	var folder := mod.path.path_join("course")
	var record := machine.r32(COURSES + base * 4)
	var pointers: Array[int] = []
	for index in RECORD_WORDS / 2:
		pointers.append(machine.r32(record + index * 4))

	var map := _read_grid(mod, folder.path_join("map.txt"))
	if not map.is_empty():
		var address := extra.add_words(_grid_words(map))
		pointers[GROUND_MAP / 4] = address
		pointers[CODE_MAP / 4] = address
		pointers[SCENERY_MAP / 4] = address
		machine.extra_rom = extra.bytes
	var scale := clampi(int(config.get_value("graphics", "scale", 1)), 1, 4)
	pointers[GROUND_BLOCKS / 4] = _cells(machine, mod, folder.path_join("cells"), pointers[GROUND_BLOCKS / 4],
			extra, new_tiles, scale)
	pointers[CODE_CELLS / 4] = _codes(machine, mod, folder.path_join("codes"), pointers[CODE_CELLS / 4], extra)
	var signs := _read_grid(mod, folder.path_join("signs.txt"))
	if not signs.is_empty():
		pointers[SIGNS / 4] = extra.add(_grid_bytes(signs))
	var words: Array[int] = []
	for pointer in pointers:
		words.append_array([pointer >> 16, pointer & 0xFFFF])
	Mods.write_long(machine, COURSES + base * 4, extra.add_words(words))
	machine.extra_rom = extra.bytes

	if config.has_section_key("course", "start") or config.has_section_key("course", "facing"):
		_start(machine, mod, base, extra)
	if config.has_section_key("course", "time"):
		_time(machine, config.get_value("course", "time"), base, extra)
	if config.has_section_key("course", "progress"):
		var ys: Array = config.get_value("course", "progress")
		var list: Array[int] = [ys.size()]
		for y: Variant in ys:
			list.append(int(y) & 0xFFFF)
		Mods.write_long(machine, CHECKPOINTS + base * 4, extra.add_words(list))
	var waypoints := _read_rows(mod, folder.path_join("waypoints.txt"))
	if not waypoints.is_empty():
		var list: Array[int] = []
		for point in waypoints:
			if point.size() != 5:
				push_warning("Mod %s: waypoints.txt: a line without five numbers" % mod.id)
				return
			for value in point:
				list.append(value & 0xFFFF)
		Mods.write_long(machine, WAYPOINTS + base * 4, extra.add_words(list))
		Mods.write_words(machine, WAYPOINT_COUNTS + base * 2, [waypoints.size()])
	if config.has_section_key("course", "rivals_from"):
		var first := PackedByteArray()
		for value: Variant in config.get_value("course", "rivals_from"):
			first.append(int(value) & 0xFF)
		while first.size() < FIRST_WAYPOINT_BYTES:
			first.append(first[first.size() - 4] if first.size() >= 4 else 0)
		Mods.write_long(machine, FIRST_WAYPOINTS + base * 4, extra.add(first))
	if config.has_section_key("course", "music"):
		var music := clampi(int(config.get_value("course", "music")), 0, COURSE_COUNT - 1)
		Mods.write_words(machine, COURSE_MUSIC + base * 2, [machine.r16(COURSE_MUSIC + music * 2)])
	machine.extra_rom = extra.bytes


## Numbers in lines, as map.txt has them.
static func _read_rows(mod: Mods.Mod, path: String) -> Array[PackedInt32Array]:
	var rows: Array[PackedInt32Array] = []
	if not FileAccess.file_exists(path):
		return rows
	for line in FileAccess.get_file_as_string(path).split("\n"):
		line = line.get_slice("#", 0).replace(",", " ").strip_edges()
		if line.is_empty():
			continue
		var row := PackedInt32Array()
		for value in line.split(" ", false):
			row.append(value.to_int())
		rows.append(row)
	if rows.is_empty():
		push_warning("Mod %s: %s is empty" % [mod.id, path.get_file()])
	return rows


static func _read_grid(mod: Mods.Mod, path: String) -> Array[PackedInt32Array]:
	var rows := _read_rows(mod, path)
	for row in rows:
		if row.size() != rows[0].size():
			push_warning("Mod %s: the lines of %s are not all as long" % [mod.id, path.get_file()])
			return []
	return rows


## A map as the game has it: columns, rows, and a word for each place.
static func _grid_words(rows: Array[PackedInt32Array]) -> Array[int]:
	var words: Array[int] = [rows[0].size(), rows.size()]
	for row in rows:
		for value in row:
			words.append(value & 0xFFFF)
	return words


## The same with a byte for each place (the map of signs).
static func _grid_bytes(rows: Array[PackedInt32Array]) -> PackedByteArray:
	var bytes := Mods.words_to_bytes([rows[0].size(), rows.size()])
	for row in rows:
		for value in row:
			bytes.append(value & 0xFF)
	return bytes


## The list of the cells' pictures with those the mod paints put in: each
## a block of 16 by 16 tiles, column by column, each a tile word and an
## attribute word (the tile's number above 16 bits in its bits 4 to 7).
static func _cells(machine: NeoGeoMachine, mod: Mods.Mod, folder: String, blocks: int,
		extra: Mods.Extra, new_tiles: Dictionary, scale: int) -> int:
	var files := _numbered_pngs(folder)
	if files.is_empty():
		return blocks
	var count := machine.r16(blocks)
	var list: Array[int] = [count]
	for cell in count:
		var block := machine.r32(blocks + 2 + cell * 4)
		list.append_array([block >> 16, block & 0xFFFF])
	var size := 16 * scale
	for cell: int in files:
		if cell >= count:
			push_warning("Mod %s: the course has no cell %d" % [mod.id, cell])
			continue
		var image := Image.load_from_file(files[cell])
		if image == null or image.get_size() != Vector2i(CELL_SIZE, CELL_SIZE) * scale:
			push_warning("Mod %s: cells/%s is not %d pixels square" % [mod.id, files[cell].get_file(), CELL_SIZE * scale])
			continue
		image.convert(Image.FORMAT_RGBA8)
		var entries: Array[int] = []
		for column in 16:
			for row in 16:
				var piece := image.get_region(Rect2i(column * size, row * size, size, size))
				var number := _tile_number(piece, extra, new_tiles, scale)
				entries.append_array([number & 0xFFFF, ((number >> 16) & 0xF) << 4])
		var address := extra.add_words(entries)
		list[1 + cell * 2] = address >> 16
		list[2 + cell * 2] = address & 0xFFFF
	return extra.add_words(list)


## The tile number of a piece of a cell's picture: the same for the same
## picture, so a cell of grass all over takes few.
static func _tile_number(piece: Image, extra: Mods.Extra, new_tiles: Dictionary, scale: int) -> int:
	var key := piece.get_data()
	if extra.tiles_by_picture.has(key):
		return extra.tiles_by_picture[key]
	var number := mini(extra.next_tile, LAST_NEW_TILE)
	extra.next_tile += 1
	extra.tiles_by_picture[key] = number
	new_tiles[number] = [piece, scale]
	return number


## The list of the cells' codes with those the mod gives put in: for each
## cell the address of the addresses of its four blocks of 16 by 16 codes
## (top left, top right, bottom left, bottom right), each packed.
static func _codes(machine: NeoGeoMachine, mod: Mods.Mod, folder: String, cells: int, extra: Mods.Extra) -> int:
	var files := _numbered_pngs(folder)
	if files.is_empty():
		return cells
	var count := machine.r16(cells)
	var list: Array[int] = [count]
	for cell in count:
		var blocks := machine.r32(cells + 2 + cell * 4)
		list.append_array([blocks >> 16, blocks & 0xFFFF])
	for cell: int in files:
		if cell >= count:
			push_warning("Mod %s: the course has no cell %d" % [mod.id, cell])
			continue
		var image := Image.load_from_file(files[cell])
		if image == null or image.get_size() != Vector2i(CODES_ACROSS, CODES_ACROSS):
			push_warning("Mod %s: codes/%s is not %d pixels square" % [mod.id, files[cell].get_file(), CODES_ACROSS])
			continue
		var quarters: Array[int] = []
		for quarter in 4:
			var codes := PackedByteArray()
			for y in 16:
				for x in 16:
					codes.append(code_of(image.get_pixel((quarter & 1) * 16 + x, (quarter >> 1) * 16 + y)))
			var packed := extra.add(pack_codes(codes))
			quarters.append_array([packed >> 16, packed & 0xFFFF])
		var address := extra.add_words(quarters)
		list[1 + cell * 2] = address >> 16
		list[2 + cell * 2] = address & 0xFFFF
	return extra.add_words(list)


## Codes packed as the game unpacks them (game/ground.gd).
static func pack_codes(codes: PackedByteArray) -> PackedByteArray:
	var packed := PackedByteArray()
	var at := 0
	while at < codes.size():
		var run := 1
		while at + run < codes.size() and codes[at + run] == codes[at] and run < 0x7F:
			run += 1
		if run >= 3:
			packed.append(0x80 | run)
			packed.append(codes[at])
		else:
			for index in run:
				packed.append(codes[at])
		at += run
	packed.append(PACKED_END)
	return packed


static func _numbered_pngs(folder: String) -> Dictionary:
	var found := {}
	if not DirAccess.dir_exists_absolute(folder):
		return found
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "png" and file.get_basename().is_valid_int():
			found[file.get_basename().to_int()] = folder.path_join(file)
	return found


## Moves the start of the player's car, and the other cars' with it.
static func _start(machine: NeoGeoMachine, mod: Mods.Mod, base: int, extra: Mods.Extra) -> void:
	var config := mod.config
	var fields := machine.r32(machine.r32(COURSE_FIELDS) + base * 4)
	var words: Array[int] = []
	for index in START_WORDS:
		words.append(machine.r16(fields + index * 2))
	var start: Array = config.get_value("course", "start", [words[7], words[9]])
	var moved := Vector2i(int(start[0]) - words[7], int(start[1]) - words[9])
	var facing := words[0x16]
	if config.has_section_key("course", "facing"):
		facing = roundi(float(config.get_value("course", "facing")) / 360.0 * 0x10000) & 0xFFFF
	# where it was and is (the whole part of 16.16), the camera, its travel
	# and its facing
	for at: int in [3, 7, 0x13]:
		words[at] = (words[at] + moved.x) & 0xFFFF
	for at: int in [5, 9, 0x14]:
		words[at] = (words[at] + moved.y) & 0xFFFF
	words[0x15] = facing
	words[0x16] = facing
	Mods.write_long(machine, machine.r32(COURSE_FIELDS) + base * 4, extra.add_words(words))
	var rivals := machine.r32(machine.r32(RIVAL_FIELDS) + base * 4)
	var all: Array[int] = []
	for rival in RIVALS:
		var own: Array[int] = []
		for index in RIVAL_WORDS:
			own.append(machine.r16(rivals + (rival * RIVAL_WORDS + index) * 2))
		for at: int in [2, 6, 0x12]:
			own[at] = (own[at] + moved.x) & 0xFFFF
		for at: int in [4, 8, 0x13]:
			own[at] = (own[at] + moved.y) & 0xFFFF
		own[0x14] = facing
		own[0x15] = facing
		all.append_array(own)
	Mods.write_long(machine, machine.r32(RIVAL_FIELDS) + base * 4, extra.add_words(all))


## The time at the start and gained at each checkpoint, in seconds, for
## every difficulty.
static func _time(machine: NeoGeoMachine, seconds: Variant, base: int, extra: Mods.Extra) -> void:
	if not seconds is Array:
		seconds = [seconds]
	var words: Array[int] = []
	for index in TIME_WORDS / 2:
		var frames := 0
		if index < seconds.size():
			frames = roundi(float(seconds[index]) * FRAMES_PER_SECOND * 0x10000)
		words.append_array([(frames >> 16) & 0xFFFF, frames & 0xFFFF])
	var address := extra.add_words(words)
	var done := {}
	for difficulty in DIFFICULTIES:
		for kind in MACHINES:
			var clock := machine.r32(machine.r32(CLOCKS + difficulty * 4) + kind * 4)
			var by_course := machine.r32(clock + 4)
			if not done.has(by_course):
				done[by_course] = true
				Mods.write_long(machine, by_course + base * 4, address)
