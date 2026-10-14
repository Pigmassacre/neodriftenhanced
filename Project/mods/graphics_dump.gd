extends RefCounted
## Saves the game's pictures as it shows them, for making mods
## (`--dump-graphics=FOLDER`): every picture drawn from the program ROM as
## `pictures/ADDRESS.png`, and every block of a course's ground as
## `ground/ADDRESS.png`, and every tile of the text layer as
## `fix/NUMBER.png`, each with its `.colours` (mods/mod_graphics.gd).
## A picture already saved is saved again when it is shown brighter, so
## that what is kept is not one caught in the middle of a fade.

const Sprite := preload("res://game/sprite_object.gd")

var folder := ""
var saved := 0
## By picture or block address, how bright it was when saved.
var _brightness := {}
var _tiles := PackedByteArray()
var _fix := PackedByteArray()
## By text layer tile, how bright it was when saved.
var _fix_brightness := {}


func _init(to: String) -> void:
	folder = to
	DirAccess.make_dir_recursive_absolute(folder.path_join("pictures"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("ground"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("fix"))
	_tiles = FileAccess.get_file_as_bytes(MachineLoader.repo_dir().path_join("data/game/tiles.bin"))
	_fix = FileAccess.get_file_as_bytes(MachineLoader.repo_dir().path_join("data/game/fix_cart.bin"))


## Saves what is shown now that is new or brighter. `colours` are the
## palettes as the picture shows them: 16 RGBA8 colours to each of 256.
func note(machine: NeoGeoMachine, scene: GameScene, colours: PackedByteArray) -> void:
	if _tiles.is_empty():
		return
	for index in Sprite.record_count(machine):
		var record := Sprite.record(index) & 0xFFFF
		if machine.ram.decode_u16(record + Sprite.SHOWN) != 1:
			continue
		var body := ((machine.ram.decode_u16(record + Sprite.PICTURE_BODY) << 16)
				| machine.ram.decode_u16(record + Sprite.PICTURE_BODY + 2)) & 0xFFFFFF
		if Mods.rom_index(body) < 0:
			continue
		var columns := machine.ram.decode_u16(record + Sprite.PICTURE_HEAD)
		var rows := machine.ram.decode_u16(record + Sprite.PICTURE_HEAD + 2)
		if columns == 0 or rows == 0 or columns > 64 or rows > 32:
			continue
		var palette := machine.ram.decode_u16(record + Sprite.PALETTE) & 0xFF
		_save(machine, colours, "pictures", body, columns, rows, palette)
	if machine.fix_from_cart and _fix.size() >= 512 * 512:
		for cell in range(0x7000, 0x7500):
			var word := machine.vram[cell]
			if word & 0xFFF != 0:
				_save_fix(word & 0xFFF, word >> 12, colours)
	if scene != null and scene.ground_on:
		for block in scene.block_count:
			var address := machine.r32(scene.blocks + block * 4) & 0xFFFFFF
			if Mods.rom_index(address) >= 0:
				_save(machine, colours, "ground", address, 16, 16, 0)


## One picture of `columns` by `rows` tiles from `address`, all drawn in
## `palette` if it is not 0.
func _save(machine: NeoGeoMachine, colours: PackedByteArray, kind: String, address: int,
		columns: int, rows: int, palette: int) -> void:
	# how bright its colours are, before drawing it
	var used := {}
	for column in columns:
		for row in rows:
			used[palette if palette != 0 else machine.r16(address + (column * rows + row) * 4 + 2) >> 8] = true
	var brightness := 0
	for number: int in used:
		for index in range(1, 16):
			var colour := colours.decode_u32((number * 16 + index) * 4)
			brightness += (colour & 0xFF) + ((colour >> 8) & 0xFF) + ((colour >> 16) & 0xFF)
	if brightness <= _brightness.get(address, -1):
		return
	var first_time := not _brightness.has(address)
	_brightness[address] = brightness
	var image := Image.create_empty(columns * 16, rows * 16, false, Image.FORMAT_RGBA8)
	for column in columns:
		for row in rows:
			var at := address + (column * rows + row) * 4
			var tile := machine.r16(at)
			var attributes := machine.r16(at + 2)
			var drawn_with := palette if palette != 0 else attributes >> 8
			var origin := (tile >> 8) * 16 * 4096 + (tile & 255) * 16
			for y in 16:
				for x in 16:
					var number := _tiles[origin + y * 4096 + x]
					if number == 0:
						continue
					var colour := colours.decode_u32((drawn_with * 16 + number) * 4)
					var to := Vector2i(15 - x if attributes & 1 else x, 15 - y if attributes & 2 else y)
					image.set_pixel(column * 16 + to.x, row * 16 + to.y, Color8(
							colour & 0xFF, (colour >> 8) & 0xFF, (colour >> 16) & 0xFF))
	var path := folder.path_join(kind).path_join("%06X" % address)
	image.save_png(path + ".png")
	var lines := PackedStringArray()
	for number: int in used:
		var line := PackedStringArray()
		for index in 16:
			var colour := colours.decode_u32((number * 16 + index) * 4)
			line.append("%02x%02x%02x" % [colour & 0xFF, (colour >> 8) & 0xFF, (colour >> 16) & 0xFF])
		lines.append("%s = %s" % ["all" if palette != 0 else str(number), " ".join(line)])
	var file := FileAccess.open(path + ".colours", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	if first_time:
		saved += 1


## A tile of the text layer, as it is drawn in `palette`.
func _save_fix(tile: int, palette: int, colours: PackedByteArray) -> void:
	var origin := (tile >> 6) * 8 * 512 + (tile & 63) * 8
	var brightness := 0
	for index in range(1, 16):
		var colour := colours.decode_u32((palette * 16 + index) * 4)
		brightness += (colour & 0xFF) + ((colour >> 8) & 0xFF) + ((colour >> 16) & 0xFF)
	if brightness <= _fix_brightness.get(tile, -1):
		return
	var first_time := not _fix_brightness.has(tile)
	_fix_brightness[tile] = brightness
	var image := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	var empty := true
	for y in 8:
		for x in 8:
			var number := _fix[origin + y * 512 + x]
			if number != 0:
				empty = false
				var colour := colours.decode_u32((palette * 16 + number) * 4)
				image.set_pixel(x, y, Color8(colour & 0xFF, (colour >> 8) & 0xFF, (colour >> 16) & 0xFF))
	if empty:
		return
	var path := folder.path_join("fix").path_join("%03X" % tile)
	image.save_png(path + ".png")
	var line := PackedStringArray()
	for index in 16:
		var colour := colours.decode_u32((palette * 16 + index) * 4)
		line.append("%02x%02x%02x" % [colour & 0xFF, (colour >> 8) & 0xFF, (colour >> 16) & 0xFF])
	FileAccess.open(path + ".colours", FileAccess.WRITE).store_string("all = %s\n" % " ".join(line))
	if first_time:
		saved += 1
