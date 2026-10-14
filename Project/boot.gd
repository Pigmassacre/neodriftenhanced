extends Control
## The start of an exported game. The game reads the player's ROMs, and the
## pictures made from them, from a folder of its own
## (MachineLoader.repo_dir): this fills that folder from wherever the player
## put their ROMs, makes the pictures the first time, then starts the game.
## Run from the repository, the game starts without it: Tools/setup.sh has
## made all that in data/ (project.godot names this the main scene of an
## exported game only).

## The files needed of each ROM set, with their sizes.
const SETS := {
	"neodrift": {
		"213-p1.p1": 0x200000, "213-s1.s1": 0x20000, "213-c1.c1": 0x400000, "213-c2.c2": 0x400000,
		"213-m1.m1": 0x20000, "213-v1.v1": 0x200000, "213-v2.v2": 0x200000,
	},
	"neogeo": {"sp-s2.sp1": 0x20000, "000-lo.lo": 0x20000, "sfix.sfix": 0x20000},
}
## Written last into data/game, so pictures half made are made again. Change
## it when what is made changes.
const BUILT := "built.txt"
const BUILT_VERSION := "1"
## How often to look again for ROMs that are not there yet.
const LOOK_AGAIN := 1.0

var _label := Label.new()
var _thread: Thread
var _progress := 0.0
var _waited := 0.0
var _missing: Array[String] = []


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	_try()


func _process(delta: float) -> void:
	if _thread != null:
		if _thread.is_alive():
			_label.text = "Warming up the engine!\n\nGetting the pictures ready from your ROMs: %d%%" \
					% roundi(_progress * 100.0)
			return
		var ok: bool = _thread.wait_to_finish()
		_thread = null
		if ok:
			_start()
		else:
			_label.text = "Could not write the game's pictures to\n%s" % _data_dir()
		return
	if not _missing.is_empty():
		_waited += delta
		if _waited >= LOOK_AGAIN:
			_waited = 0.0
			_try()


func _unhandled_input(event: InputEvent) -> void:
	if _missing.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_accept"):
		OS.shell_open(_beside_game())
	elif event.is_action("ui_cancel"):
		get_tree().quit()


func _try() -> void:
	var was_missing := _missing
	_missing = _gather()
	if not _missing.is_empty():
		if _missing != was_missing:
			print("ROMs missing (%s): put them in %s" % [", ".join(_missing), _beside_game()])
		_label.text =("Insert ROMs to play!\n\nNeo Drift Out Enhanced runs on your own copy of the game. "
				+ "Put MAME's neodrift.zip and neogeo.zip (or folders of the same names) in\n\n%s\n\n"
				+ "and the race is on. Still missing: %s\n\nEnter opens the folder, Esc quits.") \
				% [_beside_game(), ", ".join(_missing)]
		return
	if FileAccess.get_file_as_string(_data_dir().path_join(BUILT)) == BUILT_VERSION:
		_start()
		return
	_thread = Thread.new()
	_thread.start(_build_data)


func _start() -> void:
	get_tree().change_scene_to_file("res://game.tscn")


## The folder the game is in, where the player is asked to put their ROMs.
static func _beside_game() -> String:
	return OS.get_executable_path().get_base_dir()


static func _data_dir() -> String:
	return MachineLoader.repo_dir().path_join("data/game")


## Copies every file of SETS the game's folder has not yet got into it,
## from the places the player may have put them. Returns the sets of which
## files are still missing.
func _gather() -> Array[String]:
	var root := MachineLoader.repo_dir()
	var places: Array[String] = [_beside_game(), _beside_game().path_join("roms"),
			ProjectSettings.globalize_path("user://")]
	var missing: Array[String] = []
	var copied := false
	for set_name: String in SETS:
		var wanted: Dictionary = SETS[set_name]
		var needed: Array[String] = []
		for file: String in wanted:
			var path := root.path_join(set_name).path_join(file)
			if not FileAccess.file_exists(path) or FileAccess.get_size(path) != wanted[file]:
				needed.append(file)
		if needed.is_empty():
			continue
		DirAccess.make_dir_recursive_absolute(root.path_join(set_name))
		for place in places:
			for file in needed.duplicate():
				var data := _find(place, set_name, file)
				if data.size() == wanted[file]:
					var out := FileAccess.open(root.path_join(set_name).path_join(file), FileAccess.WRITE)
					if out != null:
						out.store_buffer(data)
						out.close()
						needed.erase(file)
						copied = true
		if not needed.is_empty():
			missing.append(set_name + ".zip")
	if copied:
		# pictures made from other ROMs are made again
		DirAccess.remove_absolute(_data_dir().path_join(BUILT))
	return missing


## A file of a set, from a folder or a zip of the set's name in a place, or
## nothing.
static func _find(place: String, set_name: String, file: String) -> PackedByteArray:
	var path := place.path_join(set_name).path_join(file)
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)
	var zip := ZIPReader.new()
	if zip.open(place.path_join(set_name + ".zip")) != OK:
		return PackedByteArray()
	var data := PackedByteArray()
	for inside in zip.get_files():
		if inside.get_file().to_lower() == file:
			data = zip.read_file(inside)
			break
	zip.close()
	return data


## Makes in data/game what the game draws from, as Tools/build_data.py does:
## the sprite tiles, the text layer's tiles of the cartridge and the board,
## and the board's table of shrunk sprite lines. Runs on a thread of its own.
func _build_data() -> bool:
	var root := MachineLoader.repo_dir()
	var dir := _data_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var c1 := FileAccess.get_file_as_bytes(root.path_join("neodrift/213-c1.c1"))
	var c2 := FileAccess.get_file_as_bytes(root.path_join("neodrift/213-c2.c2"))
	var made := {
		"tiles.bin": _sprite_tiles(c1, c2),
		"fix_cart.bin": _fix_tiles(FileAccess.get_file_as_bytes(root.path_join("neodrift/213-s1.s1"))),
		"fix_bios.bin": _fix_tiles(FileAccess.get_file_as_bytes(root.path_join("neogeo/sfix.sfix"))),
		"zoom_y.bin": FileAccess.get_file_as_bytes(root.path_join("neogeo/000-lo.lo")).slice(0, 0x10000),
		BUILT: BUILT_VERSION.to_utf8_buffer(),
	}
	for file: String in made:
		var out := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
		if out == null:
			return false
		out.store_buffer(made[file])
		out.close()
	return true


## All sprite tiles as one 4096 by 4096 picture of colour numbers, 256
## tiles to a row. A tile is 64 bytes in each of the two files: the right
## half's 16 rows, then the left half's, each row two bytes of bit planes.
func _sprite_tiles(c1: PackedByteArray, c2: PackedByteArray) -> PackedByteArray:
	const SIDE := 4096
	# for each byte, its 8 bits spread one to a byte, the first bit first
	var spread := PackedInt64Array()
	spread.resize(256)
	for value in 256:
		for bit in 8:
			spread[value] |= ((value >> bit) & 1) << (bit * 8)
	var sheet := PackedByteArray()
	sheet.resize(SIDE * SIDE)
	var tiles := mini(c1.size(), c2.size()) / 64
	for tile in mini(tiles, 256 * 256):
		var at := (tile >> 8) * 16 * SIDE + (tile & 255) * 16
		var left := tile * 64 + 0x20
		var right := tile * 64
		for y in 16:
			sheet.encode_s64(at, spread[c1[left]] | spread[c1[left + 1]] << 1
					| spread[c2[left]] << 2 | spread[c2[left + 1]] << 3)
			sheet.encode_s64(at + 8, spread[c1[right]] | spread[c1[right + 1]] << 1
					| spread[c2[right]] << 2 | spread[c2[right + 1]] << 3)
			at += SIDE
			left += 2
			right += 2
		if tile & 1023 == 0:
			_progress = float(tile) / tiles
	return sheet


## The 4096 tiles of the text layer as one 512 by 512 picture of colour
## numbers, 64 tiles to a row. A tile is 32 bytes: its columns two by two,
## in the order 4-5, 6-7, 0-1, 2-3, each 8 bytes of one row.
static func _fix_tiles(s1: PackedByteArray) -> PackedByteArray:
	const SIDE := 512
	const COLUMNS: Array[int] = [0x10, 0x18, 0x00, 0x08]
	var sheet := PackedByteArray()
	sheet.resize(SIDE * SIDE)
	for tile in mini(s1.size() / 32, 4096):
		var at := (tile >> 6) * 8 * SIDE + (tile & 63) * 8
		for column in 4:
			for y in 8:
				var both := s1[tile * 32 + COLUMNS[column] + y]
				sheet[at + y * SIDE + column * 2] = both & 15
				sheet[at + y * SIDE + column * 2 + 1] = both >> 4
	return sheet
