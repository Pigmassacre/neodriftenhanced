extends SceneTree
## Makes a mod of one of the game's courses, to make a course of one's own
## from (mods/mod_courses.gd, MODDING.md):
##
##   Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path Project -s res://tools/export_course.gd -- --course=1 --to=mods/my_course
##
## It writes the mod's mod.cfg (the start, the times, the checkpoints, the
## other cars' first waypoints), `course/map.txt`, `course/signs.txt`,
## `course/waypoints.txt`, every cell's codes in `course/codes/` and what
## each code is on this course in `course/codes.txt`. The
## cells' pictures go to `course/cells_from_game/`, where the game does not
## look: copy those you paint to `course/cells/`. What it writes comes from
## your ROM; keep it to yourself.

const ModCourses := preload("res://mods/mod_courses.gd")
const Car := preload("res://game/car.gd")
const Palettes := preload("res://game/palettes.gd")
const CELL_TILES := 16


func _init() -> void:
	var course := 1
	var to := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--course="):
			course = clampi(int(arg.trim_prefix("--course=")), 0, ModCourses.COURSE_COUNT - 1)
		elif arg.begins_with("--to="):
			to = arg.trim_prefix("--to=")
	if to == "":
		printerr("--to=FOLDER is needed")
		quit(1)
		return
	var machine := MachineLoader.create(true, false)
	if machine == null:
		quit(1)
		return
	to = ProjectSettings.globalize_path(to) if to.begins_with("res://") or to.begins_with("user://") else to
	DirAccess.make_dir_recursive_absolute(to.path_join("course/codes"))
	DirAccess.make_dir_recursive_absolute(to.path_join("course/cells_from_game"))
	_export(machine, course, to)
	machine.release()
	print("Course %d written to %s" % [course, to])
	quit()


func _export(machine: NeoGeoMachine, course: int, to: String) -> void:
	var record := machine.r32(ModCourses.COURSES + course * 4)
	var map := machine.r32(record + ModCourses.GROUND_MAP)
	var across := machine.r16(map)
	var down := machine.r16(map + 2)
	var lines := PackedStringArray()
	for row in down:
		var line := PackedStringArray()
		for column in across:
			line.append("%3d" % machine.r16(map + 4 + (row * across + column) * 2))
		lines.append(" ".join(line))
	_write(to.path_join("course/map.txt"), "\n".join(lines))

	var signs := machine.r32(record + ModCourses.SIGNS)
	lines.clear()
	for row in machine.r16(signs + 2):
		var line := PackedStringArray()
		for column in machine.r16(signs):
			line.append("%2d" % machine.r8(signs + 4 + row * machine.r16(signs) + column))
		lines.append(" ".join(line))
	_write(to.path_join("course/signs.txt"), "\n".join(lines))

	var waypoints := machine.r32(ModCourses.WAYPOINTS + course * 4)
	lines = PackedStringArray(["# x, y, width, height of the box, speed to slow down to"])
	for index in machine.r16(ModCourses.WAYPOINT_COUNTS + course * 2):
		var line := PackedStringArray()
		for word in 5:
			line.append(str(GameRoutines.wrap16(machine.r16(waypoints + index * 10 + word * 2))))
		lines.append(" ".join(line))
	_write(to.path_join("course/waypoints.txt"), "\n".join(lines))

	var cells := machine.r32(record + ModCourses.CODE_CELLS)
	for cell in machine.r16(cells):
		var blocks := machine.r32(cells + 2 + cell * 4)
		var image := Image.create_empty(ModCourses.CODES_ACROSS, ModCourses.CODES_ACROSS, false, Image.FORMAT_RGB8)
		for quarter in 4:
			var codes := _unpack(machine, machine.r32(blocks + quarter * 4))
			for index in codes.size():
				image.set_pixel((quarter & 1) * 16 + index % 16, (quarter >> 1) * 16 + index / 16,
						ModCourses.code_colour(codes[index]))
		image.save_png(to.path_join("course/codes/%d.png" % cell))

	_write(to.path_join("course/codes.txt"), "\n".join(_legend(machine, course)))

	var colours := _colours(machine, course)
	var tiles := FileAccess.get_file_as_bytes(MachineLoader.repo_dir().path_join("data/game/tiles.bin"))
	var blocks := machine.r32(record + ModCourses.GROUND_BLOCKS)
	for cell in machine.r16(blocks):
		_cell_picture(machine, machine.r32(blocks + 2 + cell * 4), tiles, colours).save_png(
				to.path_join("course/cells_from_game/%d.png" % cell))

	var config := ConfigFile.new()
	config.set_value("mod", "name", "Stage %d, changed" % course if course > 0 else "Practice, changed")
	config.set_value("mod", "description", "A course made from the game's %s." % ("stage %d" % course if course > 0 else "practice course"))
	config.set_value("course", "base", course)
	config.set_value("course", "name", "Stage %d, changed" % course if course > 0 else "Practice, changed")
	config.set_value("course", "arcade", false)
	var fields := machine.r32(machine.r32(ModCourses.COURSE_FIELDS) + course * 4)
	config.set_value("course", "start", [machine.r16(fields + 7 * 2), machine.r16(fields + 9 * 2)])
	config.set_value("course", "facing", snappedf(machine.r16(fields + 0x16 * 2) / 65536.0 * 360.0, 0.01))
	var clock := machine.r32(machine.r32(ModCourses.CLOCKS) + 0)
	var times := machine.r32(machine.r32(clock + 4) + course * 4)
	var seconds := []
	for index in ModCourses.TIME_WORDS / 2:
		var frames := machine.r32(times + index * 4)
		if frames == 0 and index > 0:
			break
		seconds.append(snappedf(frames / 65536.0 / ModCourses.FRAMES_PER_SECOND, 0.01))
	config.set_value("course", "time", seconds)
	var progress := machine.r32(ModCourses.CHECKPOINTS + course * 4)
	var ys := []
	for index in machine.r16(progress):
		ys.append(machine.r16(progress + 2 + index * 2))
	config.set_value("course", "progress", ys)
	var first := machine.r32(ModCourses.FIRST_WAYPOINTS + course * 4)
	var starts := []
	for index in ModCourses.FIRST_WAYPOINT_BYTES / 2:
		starts.append(machine.r8(first + index))
	config.set_value("course", "rivals_from", starts)
	config.set_value("course", "music", course)
	config.save(to.path_join("mod.cfg"))


## What each ground code is on the course, and its colour in the pictures
## of codes.
func _legend(machine: NeoGeoMachine, course: int) -> PackedStringArray:
	const NAMES := {6: "the end of a ramp", 7: "the finish line", 15: "a gate's first strip",
			16: "a gate's second strip", 17: "a ramp"}
	var lines := PackedStringArray([
		"# code, its colour in codes/*.png, and what it is on this course",
		"# Gates are two strips side by side, the first before the second; driving",
		"# through them in that order passes a checkpoint, and the finish line ends",
		"# the race. Surfaces 8 to 13 are the slow ground that lines the road.",
	])
	var open := machine.r32(Car.OPEN_GROUND + course * 4)
	for code in 0x80:
		var what := ""
		if code < 0x20:
			what = "wall facing %d degrees" % (code * 360 / 32)
		elif code < 0x40:
			what = "edge (a kerb or a bank) at %d degrees" % roundi(machine.r16(Car.EDGE_ANGLES + (code - 0x20) * 2) / 65536.0 * 360.0)
		else:
			var surface := GameRoutines.wrap8(machine.r8(open + (code - 0x40) * 4))
			what = "open ground, surface %d%s, dust %d, shake %d, rough %d" % [surface,
					(" (%s)" % NAMES[surface]) if NAMES.has(surface) else "",
					GameRoutines.wrap8(machine.r8(open + (code - 0x40) * 4 + 1)),
					GameRoutines.wrap8(machine.r8(open + (code - 0x40) * 4 + 2)),
					GameRoutines.wrap8(machine.r8(open + (code - 0x40) * 4 + 3))]
		lines.append("%3d  #%s  %s" % [code, ModCourses.code_colour(code).to_html(false), what])
	return lines


func _write(path: String, text: String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(text + "\n")


func _unpack(machine: NeoGeoMachine, packed: int) -> PackedByteArray:
	var codes := PackedByteArray()
	while codes.size() < 256:
		var byte := machine.r8(packed)
		packed += 1
		if byte < ModCourses.PACKED_END:
			codes.append(byte)
		elif byte == ModCourses.PACKED_END:
			break
		else:
			var code := machine.r8(packed)
			packed += 1
			for count in byte & 0x7F:
				codes.append(code)
	codes.resize(256)
	return codes


## The colours of a race on this course, as car.gd's `load_colours` asks
## for them (sets of colours from palettes.gd's table), 16 to a palette.
func _colours(machine: NeoGeoMachine, course: int) -> PackedColorArray:
	var colours := PackedColorArray()
	colours.resize(256 * 16)
	for number: int in [0, 0x12, 0x13, 0x14, 0x15, 0x16, course + 0x17, 0x1E]:
		var list := machine.r32(Palettes.SETS + number * 4)
		while machine.r32(list) != 0:
			var set := machine.r32(list)
			var first := machine.r16(set)
			for index in machine.r16(set + 2) * 16:
				var at := set + 4 + index * 3
				if first * 16 + index < colours.size():
					colours[first * 16 + index] = Color((machine.r8(at) & 0x1F) / 31.0,
							(machine.r8(at + 1) & 0x1F) / 31.0, (machine.r8(at + 2) & 0x1F) / 31.0)
			list += 4
	return colours


## A cell's picture: 16 by 16 tiles, column by column.
func _cell_picture(machine: NeoGeoMachine, block: int, tiles: PackedByteArray, colours: PackedColorArray) -> Image:
	var image := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for column in CELL_TILES:
		for row in CELL_TILES:
			var at := block + (column * CELL_TILES + row) * 4
			var tile := machine.r16(at)
			var attributes := machine.r16(at + 2)
			var palette := attributes >> 8
			var origin := (tile >> 8) * 16 * 4096 + (tile & 255) * 16
			for y in 16:
				for x in 16:
					var number := tiles[origin + y * 4096 + x] if origin + y * 4096 + x < tiles.size() else 0
					if number == 0:
						continue
					image.set_pixel(column * 16 + (15 - x if attributes & 1 else x),
							row * 16 + (15 - y if attributes & 2 else y), colours[palette * 16 + number])
	return image
