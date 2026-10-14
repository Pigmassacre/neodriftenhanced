class_name CourseData
extends RefCounted
## A course as a mod has it (mods/mod_courses.gd, MODDING.md): read from
## the game's program ROM, then from a mod's folder over it, and written
## back to a mod's folder. tools/export_course.gd and the course editor
## (editor/) work through it.
##
## Positions are in pixels of the course. A place is a cell of the map:
## `row * across + column`.

const ModCourses := preload("res://mods/mod_courses.gd")
const Car := preload("res://game/car.gd")
const Palettes := preload("res://game/palettes.gd")
const CourseObjects := preload("res://game/course_objects.gd")

const CELL := ModCourses.CELL_SIZE
const CODES := ModCourses.CODES_ACROSS
## Tiles across and down a cell, and pixels across a tile.
const CELL_TILES := 16
const TILE := 16
## The kinds of scenery: a count, then the address of each kind's routines.
const SCENERY_KINDS := 0x2E794

var base := 1
var name := ""
var arcade := false
var start := Vector2i()
## In degrees, as mod.cfg has it.
var facing := 0.0
var time: Array = []
var progress: Array = []
var rivals_from: Array = []
var music := 1

var across := 16
var down := 128
## The cell number of each place.
var map := PackedInt32Array()
## The sign number of each place, 0 for none.
var signs := PackedInt32Array()
## The other cars' way: each [x, y, width, height, speed].
var waypoints: Array[PackedInt32Array] = []
## By cell number, its ground codes: 32 by 32, a row after another.
var codes := {}
## Each thing: x, y, kind.
var scenery: Array[Vector3i] = []
## How many cells the game's course has; numbers from there on are new.
var game_cells := 0
## The pictures of the cells the mod paints (`cells/`), by number.
var painted := {}
## The cells `make_own_cell` has made.
var made := {}
## The mod's `[graphics] scale`: how much larger its pictures are.
var scale := 1
## The mod.cfg read, so that what it has besides is kept.
var config := ConfigFile.new()

var _machine: NeoGeoMachine
## The course's name as it was read, for the mod's.
var _name_at_load := ""
var _record := 0
## The game's scenery of each cell, by number: [Vector3i(x, y, kind)] within it.
var _cell_scenery := {}
var _tiles := PackedByteArray()
var _colours := PackedByteArray()
var _game_pictures := {}


## The game's course `course`, as the machine's (unchanged) program ROM has it.
static func from_game(machine: NeoGeoMachine, course: int) -> CourseData:
	var data := CourseData.new()
	data._read_game(machine, course)
	return data


## The course of the mod at `folder`: the game's course it is made from,
## with what the mod changes.
static func from_mod(machine: NeoGeoMachine, folder: String) -> CourseData:
	var config := ConfigFile.new()
	config.load(folder.path_join(Mods.FILE))
	var data := from_game(machine, clampi(int(config.get_value("course", "base", 1)), 0, ModCourses.COURSE_COUNT - 1))
	data._read_mod(folder, config)
	return data


func _read_game(machine: NeoGeoMachine, course: int) -> void:
	_machine = machine
	base = course
	name = "Stage %d, changed" % course if course > 0 else "Practice, changed"
	music = course
	_name_at_load = name
	_record = machine.r32(ModCourses.COURSES + course * 4)
	var ground_map := machine.r32(_record + ModCourses.GROUND_MAP)
	across = machine.r16(ground_map)
	down = machine.r16(ground_map + 2)
	map.resize(across * down)
	for place in map.size():
		map[place] = machine.r16(ground_map + 4 + place * 2)

	var sign_map := machine.r32(_record + ModCourses.SIGNS)
	signs.resize(across * down)
	if machine.r16(sign_map) == across and machine.r16(sign_map + 2) == down:
		for place in signs.size():
			signs[place] = machine.r8(sign_map + 4 + place)

	var route := machine.r32(ModCourses.WAYPOINTS + course * 4)
	for index in machine.r16(ModCourses.WAYPOINT_COUNTS + course * 2):
		var point := PackedInt32Array()
		for word in 5:
			point.append(GameRoutines.wrap16(machine.r16(route + index * 10 + word * 2)))
		waypoints.append(point)

	var blocks := machine.r32(_record + ModCourses.GROUND_BLOCKS)
	game_cells = machine.r16(blocks)
	var cells := machine.r32(_record + ModCourses.CODE_CELLS)
	for cell in mini(machine.r16(cells), game_cells):
		codes[cell] = _game_codes(machine.r32(cells + 2 + cell * 4))

	var lists := machine.r32(_record + 0x14)
	for cell in machine.r16(lists):
		var things: Array[Vector3i] = []
		var entry := machine.r32(lists + 2 + cell * 4)
		while machine.r16(entry) != 0:
			things.append(Vector3i(machine.r8(entry + 2), machine.r8(entry + 3), machine.r16(entry)))
			entry += 4
		_cell_scenery[cell] = things
	scenery = scenery_of_cells()

	var fields := machine.r32(machine.r32(ModCourses.COURSE_FIELDS) + course * 4)
	start = Vector2i(machine.r16(fields + 7 * 2), machine.r16(fields + 9 * 2))
	facing = snappedf(machine.r16(fields + 0x16 * 2) / 65536.0 * 360.0, 0.01)
	var clock := machine.r32(machine.r32(ModCourses.CLOCKS))
	var times := machine.r32(machine.r32(clock + 4) + course * 4)
	for index in ModCourses.TIME_WORDS / 2:
		var frames := machine.r32(times + index * 4)
		if frames == 0 and index > 0:
			break
		time.append(snappedf(frames / 65536.0 / ModCourses.FRAMES_PER_SECOND, 0.01))
	var checkpoints := machine.r32(ModCourses.CHECKPOINTS + course * 4)
	for index in machine.r16(checkpoints):
		progress.append(machine.r16(checkpoints + 2 + index * 2))
	var first := machine.r32(ModCourses.FIRST_WAYPOINTS + course * 4)
	for index in ModCourses.FIRST_WAYPOINT_BYTES / 2:
		rivals_from.append(machine.r8(first + index))


## A cell's codes, unpacked from its four blocks.
func _game_codes(blocks: int) -> PackedByteArray:
	var all := PackedByteArray()
	all.resize(CODES * CODES)
	for quarter in 4:
		var packed := _machine.r32(blocks + quarter * 4)
		var index := 0
		while index < 256:
			var byte := _machine.r8(packed)
			packed += 1
			if byte == ModCourses.PACKED_END:
				break
			var count := 1
			if byte > ModCourses.PACKED_END:
				count = byte & 0x7F
				byte = _machine.r8(packed)
				packed += 1
			for repeat in count:
				if index < 256:
					all[((quarter >> 1) * 16 + index / 16) * CODES + (quarter & 1) * 16 + index % 16] = byte
					index += 1
	return all


## The scenery as the game puts it: each place has its cell's.
func scenery_of_cells() -> Array[Vector3i]:
	var things: Array[Vector3i] = []
	for place in map.size():
		things.append_array(cell_scenery_at(map[place], place))
	return things


## The game's scenery of cell `cell`, as it would stand at `place`.
func cell_scenery_at(cell: int, place: int) -> Array[Vector3i]:
	var things: Array[Vector3i] = []
	var corner := place_corner(place)
	for thing: Vector3i in _cell_scenery.get(cell, []):
		things.append(Vector3i(corner.x + thing.x, corner.y + thing.y, thing.z))
	return things


func _read_mod(folder: String, mod_config: ConfigFile) -> void:
	config = mod_config
	name = str(config.get_value("course", "name", config.get_value("mod", "name", name)))
	_name_at_load = name
	arcade = bool(config.get_value("course", "arcade", false))
	scale = clampi(int(config.get_value("graphics", "scale", 1)), 1, 4)
	var start_list: Array = config.get_value("course", "start", [start.x, start.y])
	start = Vector2i(int(start_list[0]), int(start_list[1]))
	facing = float(config.get_value("course", "facing", facing))
	var seconds: Variant = config.get_value("course", "time", time)
	time = seconds if seconds is Array else [seconds]
	progress = config.get_value("course", "progress", progress)
	rivals_from = config.get_value("course", "rivals_from", rivals_from)
	music = int(config.get_value("course", "music", music))

	var course := folder.path_join("course")
	var rows := _rows(course.path_join("map.txt"))
	if _is_grid(rows):
		across = rows[0].size()
		down = rows.size()
		map = _flat(rows)
	var sign_rows := _rows(course.path_join("signs.txt"))
	if _is_grid(sign_rows) and sign_rows[0].size() == across and sign_rows.size() == down:
		signs = _flat(sign_rows)
	elif signs.size() != across * down:
		signs.resize(across * down)
	var route := _rows(course.path_join("waypoints.txt"))
	if not route.is_empty():
		waypoints = route
	for cell: int in ModCourses._numbered_pngs(course.path_join("codes")):
		var image := Image.load_from_file(course.path_join("codes/%d.png" % cell))
		if image != null and image.get_size() == Vector2i(CODES, CODES):
			var all := PackedByteArray()
			for y in CODES:
				for x in CODES:
					all.append(ModCourses.code_of(image.get_pixel(x, y)))
			codes[cell] = all
	for cell: int in ModCourses._numbered_pngs(course.path_join("cells")):
		var image := Image.load_from_file(course.path_join("cells/%d.png" % cell))
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			painted[cell] = image
	var placed := _rows(course.path_join("scenery.txt"))
	if not placed.is_empty():
		scenery = []
		for thing in placed:
			if thing.size() >= 3:
				scenery.append(Vector3i(thing[0], thing[1], thing[2]))
	else:
		scenery = scenery_of_cells()


## Writes the course to the mod at `folder`: its mod.cfg and its `course`
## folder. Pictures of cells and codes are written for every cell the mod
## has its own of, and for those in `changed_codes`. Without
## `with_scenery`, each place keeps its cell's scenery.
func save(folder: String, changed_codes: Dictionary = {}, with_scenery := true) -> void:
	var course := folder.path_join("course")
	for sub in ["codes", "cells"]:
		DirAccess.make_dir_recursive_absolute(course.path_join(sub))
	# the mod is called as its course, unless it was called otherwise
	if str(config.get_value("mod", "name", _name_at_load)) == _name_at_load:
		config.set_value("mod", "name", name)
	_name_at_load = name
	if not config.has_section_key("mod", "description"):
		config.set_value("mod", "description", "A course made from the game's %s." %
				("stage %d" % base if base > 0 else "practice course"))
	config.set_value("course", "base", base)
	config.set_value("course", "name", name)
	config.set_value("course", "arcade", arcade)
	config.set_value("course", "start", [start.x, start.y])
	config.set_value("course", "facing", snappedf(facing, 0.01))
	config.set_value("course", "time", time)
	config.set_value("course", "progress", progress)
	config.set_value("course", "rivals_from", rivals_from)
	config.set_value("course", "music", music)
	if scale != 1:
		config.set_value("graphics", "scale", scale)
	config.save(folder.path_join(Mods.FILE))

	_write(course.path_join("map.txt"), _grid_text(map, "%3d"))
	_write(course.path_join("signs.txt"), _grid_text(signs, "%2d"))
	var lines := PackedStringArray(["# x, y, width, height of the box, speed to slow down to"])
	for point in waypoints:
		lines.append(" ".join(Array(point).map(func(value: int) -> String: return str(value))))
	_write(course.path_join("waypoints.txt"), "\n".join(lines))
	if with_scenery:
		lines = PackedStringArray(["# x, y, kind of each thing beside the road, in pixels of the course"])
		for thing in scenery:
			lines.append("%d %d %d" % [thing.x, thing.y, thing.z])
		_write(course.path_join("scenery.txt"), "\n".join(lines))
	for cell: int in changed_codes:
		codes_image(cell).save_png(course.path_join("codes/%d.png" % cell))
	for cell: int in painted:
		if not FileAccess.file_exists(course.path_join("cells/%d.png" % cell)) or changed_codes.has(cell):
			(painted[cell] as Image).save_png(course.path_join("cells/%d.png" % cell))
	# a cell made and then given up (undone) leaves no picture behind
	for cell: int in made:
		if not painted.has(cell) and FileAccess.file_exists(course.path_join("cells/%d.png" % cell)):
			DirAccess.remove_absolute(course.path_join("cells/%d.png" % cell))


## Writes every cell's codes, and the scenery as the cells have it, as the
## exporter does.
func save_all_codes(folder: String) -> void:
	var changed := {}
	for cell: int in codes:
		changed[cell] = true
	save(folder, changed, false)


func codes_image(cell: int) -> Image:
	var image := Image.create_empty(CODES, CODES, false, Image.FORMAT_RGB8)
	var all: PackedByteArray = codes.get(cell, PackedByteArray())
	for index in mini(all.size(), CODES * CODES):
		image.set_pixel(index % CODES, index / CODES, ModCourses.code_colour(all[index]))
	return image


func place_corner(place: int) -> Vector2i:
	return Vector2i(place % across * CELL, place / across * CELL)


## The place at a position of the course, which goes round across.
func place_at(at: Vector2i) -> int:
	var column := posmod(at.x >> 8, across)
	var row := clampi(at.y >> 8, 0, down - 1)
	return row * across + column


## Cell numbers that the map does not use, lowest first, and then new ones.
func free_cell() -> int:
	var used := {}
	for cell in map:
		used[cell] = true
	for cell in game_cells:
		if not used.has(cell):
			return cell
	var cell := game_cells
	while used.has(cell):
		cell += 1
	return cell


## Makes `place` a cell of its own: a copy of its cell, under a number no
## other place has. Returns the number.
func make_own_cell(place: int) -> int:
	var old := map[place]
	var cell := free_cell()
	var old_codes: PackedByteArray = codes.get(old, PackedByteArray())
	codes[cell] = old_codes.duplicate()
	var picture: Image = cell_picture(old).duplicate()
	if picture.get_width() != CELL * scale:
		picture.resize(CELL * scale, CELL * scale, Image.INTERPOLATE_NEAREST)
	painted[cell] = picture
	made[cell] = true
	map[place] = cell
	return cell


## How many places show `cell`.
func uses_of(cell: int) -> int:
	return Array(map).count(cell)


# --- pictures ----------------------------------------------------------------

## A cell's picture: the mod's painted one, or the game's (256 pixels square).
func cell_picture(cell: int) -> Image:
	if painted.has(cell):
		return painted[cell]
	return game_cell_picture(cell)


func game_cell_picture(cell: int) -> Image:
	if _game_pictures.has(cell):
		return _game_pictures[cell]
	_load_tiles()
	var image := Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
	if cell < game_cells:
		var blocks := _machine.r32(_record + ModCourses.GROUND_BLOCKS)
		_draw_tiles(image, _machine.r32(blocks + 2 + cell * 4), CELL_TILES, CELL_TILES, -1)
	_game_pictures[cell] = image
	return image


## A picture of the program ROM (a head of columns and rows, then a tile
## and its attributes for each, column by column), drawn in the course's
## colours, or in `palette` throughout when it is not -1.
func rom_picture(address: int, palette := -1) -> Image:
	_load_tiles()
	var columns := _machine.r16(address)
	var rows := _machine.r16(address + 2)
	if columns == 0 or rows == 0 or columns > 64 or rows > 32:
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var image := Image.create_empty(columns * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	_draw_tiles(image, address + 4, columns, rows, palette)
	return image


## The picture of a kind of scenery.
func scenery_picture(kind: int) -> Image:
	return rom_picture(_machine.r32(_machine.r32(CourseObjects.SCENERY_PICTURES) + kind * 4))


func scenery_kinds() -> int:
	return _machine.r16(SCENERY_KINDS)


func _draw_tiles(image: Image, body: int, columns: int, rows: int, palette: int) -> void:
	var pixels := image.get_data()
	var width := image.get_width()
	for column in columns:
		for row in rows:
			var at := body + (column * rows + row) * 4
			var tile := _machine.r16(at)
			var attributes := _machine.r16(at + 2)
			var drawn_with := palette if palette >= 0 else attributes >> 8
			# tile numbers above 16 bits are in bits 4 to 7 of the attributes
			tile |= ((attributes >> 4) & 0xF) << 16
			var origin := (tile >> 8) * TILE * 4096 + (tile & 255) * TILE
			if origin + 15 * 4096 + 16 > _tiles.size():
				continue
			for y in TILE:
				var to_y := row * TILE + (15 - y if attributes & 2 else y)
				for x in TILE:
					var number := _tiles[origin + y * 4096 + x]
					if number == 0:
						continue
					var to_x := column * TILE + (15 - x if attributes & 1 else x)
					pixels.encode_u32((to_y * width + to_x) * 4, _colours.decode_u32((drawn_with * 16 + number) * 4))
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)


## The tiles' pictures, and the colours of a race on this course as
## car.gd's `load_colours` asks for them, 16 to a palette, as RGBA8.
func _load_tiles() -> void:
	if not _tiles.is_empty():
		return
	_tiles = FileAccess.get_file_as_bytes(MachineLoader.repo_dir().path_join("data/game/tiles.bin"))
	_colours.resize(256 * 16 * 4)
	for number: int in [0, 0x12, 0x13, 0x14, 0x15, 0x16, base + 0x17, 0x1E]:
		var list := _machine.r32(Palettes.SETS + number * 4)
		while _machine.r32(list) != 0:
			var set := _machine.r32(list)
			var first := _machine.r16(set)
			for index in _machine.r16(set + 2) * 16:
				var at := set + 4 + index * 3
				var colour := first * 16 + index
				if colour < 256 * 16 and index % 16 != 0:
					_colours.encode_u32(colour * 4, Color((_machine.r8(at) & 0x1F) / 31.0,
							(_machine.r8(at + 1) & 0x1F) / 31.0, (_machine.r8(at + 2) & 0x1F) / 31.0).to_abgr32())
			list += 4


# --- text files --------------------------------------------------------------

static func _rows(path: String) -> Array[PackedInt32Array]:
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
	return rows


static func _is_grid(rows: Array[PackedInt32Array]) -> bool:
	if rows.is_empty():
		return false
	for row in rows:
		if row.size() != rows[0].size():
			return false
	return true


static func _flat(rows: Array[PackedInt32Array]) -> PackedInt32Array:
	var all := PackedInt32Array()
	for row in rows:
		all.append_array(row)
	return all


func _grid_text(values: PackedInt32Array, format: String) -> String:
	var lines := PackedStringArray()
	for row in down:
		var line := PackedStringArray()
		for column in across:
			line.append(format % values[row * across + column])
		lines.append(" ".join(line))
	return "\n".join(lines)


static func _write(path: String, text: String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(text + "\n")
