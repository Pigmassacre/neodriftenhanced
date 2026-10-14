extends SceneTree
## Makes a mod of one of the game's courses, to make a course of one's own
## from (mods/mod_courses.gd, MODDING.md):
##
##   Godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path Project -s res://tools/export_course.gd -- --course=1 --to=mods/my_course
##
## It writes the mod's mod.cfg (the start, the times, the checkpoints, the
## other cars' first waypoints), `course/map.txt`, `course/signs.txt`,
## `course/waypoints.txt`, every cell's codes in `course/codes/` and what
## each code is on this course in `course/codes.txt`. The cells' pictures
## go to `course/cells_from_game/`, where the game does not look: copy
## those you paint to `course/cells/`. With `--scenery` it writes the
## scenery as well, in `course/scenery.txt`, which then stays where it is
## when the map is changed. What it writes comes from your ROM; keep it to
## yourself.

const ModCourses := preload("res://mods/mod_courses.gd")
const Car := preload("res://game/car.gd")


func _init() -> void:
	var course := 1
	var to := ""
	var scenery := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--course="):
			course = clampi(int(arg.trim_prefix("--course=")), 0, ModCourses.COURSE_COUNT - 1)
		elif arg.begins_with("--to="):
			to = arg.trim_prefix("--to=")
		elif arg == "--scenery":
			scenery = true
	if to == "":
		printerr("--to=FOLDER is needed")
		quit(1)
		return
	var machine := MachineLoader.create(true, false)
	if machine == null:
		quit(1)
		return
	to = ProjectSettings.globalize_path(to) if to.begins_with("res://") or to.begins_with("user://") else to
	export_course(machine, course, to, scenery)
	machine.release()
	print("Course %d written to %s" % [course, to])
	quit()


## Writes the mod: also used by the course editor to start a course.
static func export_course(machine: NeoGeoMachine, course: int, to: String, scenery := false) -> CourseData:
	var data := CourseData.from_game(machine, course)
	var changed := {}
	for cell: int in data.codes:
		changed[cell] = true
	data.save(to, changed, scenery)
	_write(to.path_join("course/codes.txt"), "\n".join(legend(machine, course)))
	DirAccess.make_dir_recursive_absolute(to.path_join("course/cells_from_game"))
	for cell in data.game_cells:
		data.game_cell_picture(cell).save_png(to.path_join("course/cells_from_game/%d.png" % cell))
	return data


## What each ground code is on the course, and its colour in the pictures
## of codes.
static func legend(machine: NeoGeoMachine, course: int) -> PackedStringArray:
	var lines := PackedStringArray([
		"# code, its colour in codes/*.png, and what it is on this course",
		"# Gates are two strips side by side, the first before the second; driving",
		"# through them in that order passes a checkpoint, and the finish line ends",
		"# the race. Surfaces 8 to 13 are the slow ground that lines the road.",
	])
	for code in 0x80:
		lines.append("%3d  #%s  %s" % [code, ModCourses.code_colour(code).to_html(false), describe(machine, course, code)])
	return lines


## What a ground code is on a course, in a few words.
static func describe(machine: NeoGeoMachine, course: int, code: int) -> String:
	const NAMES := {6: "the end of a ramp", 7: "the finish line", 15: "a gate's first strip",
			16: "a gate's second strip", 17: "a ramp"}
	if code < 0x20:
		return "wall facing %d degrees" % (code * 360 / 32)
	if code < 0x40:
		return "edge (a kerb or a bank) at %d degrees" % roundi(machine.r16(Car.EDGE_ANGLES + (code - 0x20) * 2) / 65536.0 * 360.0)
	var open := machine.r32(Car.OPEN_GROUND + course * 4) + (code - 0x40) * 4
	var surface := GameRoutines.wrap8(machine.r8(open))
	return "open ground, surface %d%s, dust %d, shake %d, rough %d" % [surface,
			(" (%s)" % NAMES[surface]) if NAMES.has(surface) else "",
			GameRoutines.wrap8(machine.r8(open + 1)), GameRoutines.wrap8(machine.r8(open + 2)),
			GameRoutines.wrap8(machine.r8(open + 3))]


static func _write(path: String, text: String) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(text + "\n")
