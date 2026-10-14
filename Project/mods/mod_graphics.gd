extends RefCounted
## The pictures mods replace, made into what the video's shaders draw them
## from (video/replaced.gdshaderinc).
##
## Everything the game draws but the text layer is made of tiles of 16 by 16
## pixels, so that is what is replaced: a mod's pictures are cut into the
## tiles they are made of, and every tile number so given is drawn from the
## mod's picture wherever it is used. A mod gives, in its `graphics` folder:
##
## - `pictures/ADDRESS.png`: a picture of the game, named by the address of
##   its tiles in the program ROM (in hexadecimal; what `--dump-graphics`
##   names the pictures it saves), as large as the picture is or a whole
##   number of times larger (the mod's `[graphics] scale`).
## - `ground/ADDRESS.png`: a block of a course's ground (16 by 16 tiles),
##   likewise.
## - `tiles/NUMBER.png`: a single tile, by its number in hexadecimal.
## - `fix/NUMBER.png`: a tile of the text layer (8 by 8 pixels: letters,
##   digits, the original HUD), by its number in hexadecimal.
##
## Each may have beside it a `.colours` file, as `--dump-graphics` saves it:
## the colours the picture was painted against. With it, the replacement
## changes as the game changes those colours (fading in and out, other cars
## in other colours); without, it is drawn as it is.
##
## A tile of the original with nothing in it is never replaced: pictures
## share such tiles, and painting one would paint them all.

const MOST_SCALE := 4
const ATLAS_WIDTH := 4096
const LARGEST_ATLAS := 16384
const INDEX_SIZE := 1024
## The text layer's tiles are given these numbers and up (as the text layer's
## shader has it, video/fix.gdshader).
const REPLACED_FIX := 0xFF000

## How many times finer than the game's pixels the replacements are.
var scale := 1
## The replacements side by side, the place of each tile number's (plus
## one) in an image of INDEX_SIZE square, two bytes each, and the colours
## each was painted against (16 a row, one row each).
var atlas: Image
var index: Image
var colours: Image
var count := 0
var problems: Array[String] = []

## By tile number: the tile's replacement at `scale` and its 16 colours
## (empty if not known).
var _tiles := {}
var _references := {}
var _rom: PackedByteArray
var _original_tiles: PackedByteArray


## Collects the replacements of all `mods`. `rom` is the program ROM as the
## machine has it, `original_tiles` the game's own tiles (tiles.bin).
func build(mods: Array, rom: PackedByteArray, original_tiles: PackedByteArray) -> void:
	_rom = rom
	_original_tiles = original_tiles
	scale = 1
	for mod: Mods.Mod in mods:
		if _has_graphics(mod):
			scale = maxi(scale, clampi(int(mod.config.get_value("graphics", "scale", 1)), 1, MOST_SCALE))
	for mod: Mods.Mod in mods:
		if not _has_graphics(mod):
			continue
		var mod_scale := clampi(int(mod.config.get_value("graphics", "scale", 1)), 1, MOST_SCALE)
		var folder := mod.path.path_join("graphics")
		for file in _pngs(folder.path_join("pictures")):
			_add_picture(mod, folder.path_join("pictures").path_join(file), mod_scale, false)
		for file in _pngs(folder.path_join("ground")):
			_add_picture(mod, folder.path_join("ground").path_join(file), mod_scale, true)
		for file in _pngs(folder.path_join("tiles")):
			_add_tile(mod, folder.path_join("tiles").path_join(file), mod_scale, 16, 0)
		for file in _pngs(folder.path_join("fix")):
			_add_tile(mod, folder.path_join("fix").path_join(file), mod_scale, 8, REPLACED_FIX)
	_pack()


func _has_graphics(mod: Mods.Mod) -> bool:
	return DirAccess.dir_exists_absolute(mod.path.path_join("graphics"))


func _pngs(folder: String) -> PackedStringArray:
	var files := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return files
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() == "png":
			files.append(file)
	files.sort()
	return files


func _problem(mod: Mods.Mod, text: String) -> void:
	problems.append("%s: %s" % [mod.id, text])
	push_warning("Mod %s: %s" % [mod.id, text])


## A picture: `columns` columns of `rows` tiles, each a tile word and an
## attribute word, column after column, from `address` on. A ground block
## is 16 by 16 tiles laid out the same way.
func _add_picture(mod: Mods.Mod, path: String, mod_scale: int, ground: bool) -> void:
	var address := path.get_file().get_basename().get_slice(".", 0).hex_to_int()
	var image := _load(mod, path)
	if image == null:
		return
	var size := 16 * mod_scale
	if image.get_width() % size != 0 or image.get_height() % size != 0:
		_problem(mod, "%s is not a whole number of tiles of %d pixels" % [path.get_file(), size])
		return
	var columns := image.get_width() / size
	var rows := image.get_height() / size
	if ground and (columns != 16 or rows != 16):
		_problem(mod, "%s: a block of ground is 16 by 16 tiles" % path.get_file())
		return
	if not ground and Mods.rom_index(address) >= 4:
		# the picture's own count of columns and rows is mostly just before
		# its tiles
		var head := Vector2i(_word(address - 4), _word(address - 2))
		if head.x <= 64 and head.y <= 32 and head != Vector2i(columns, rows):
			_problem(mod, "%s is %d by %d tiles, the game's picture %d by %d" % [
					path.get_file(), columns, rows, head.x, head.y])
			return
	var references := _read_colours(mod, path.get_basename() + ".colours")
	var empty_painted := 0
	for column in columns:
		for row in rows:
			var at := address + (column * rows + row) * 4
			if Mods.rom_index(at + 3) < 0:
				_problem(mod, "%s reaches beyond the program ROM" % path.get_file())
				return
			var tile := _word(at)
			var attributes := _word(at + 2)
			var number := tile | ((attributes >> 4) & 0xF) << 16
			var piece := image.get_region(Rect2i(column * size, row * size, size, size))
			if attributes & 1:
				piece.flip_x()
			if attributes & 2:
				piece.flip_y()
			if _is_empty(number):
				if not piece.is_invisible():
					empty_painted += 1
				continue
			_set_tile(number, piece, mod_scale, references.get(-1, references.get(attributes >> 8, PackedColorArray())))
	if empty_painted > 0:
		_problem(mod, "%s: %d tiles painted where the game's picture has an empty tile, which other pictures share; left out" % [
				path.get_file(), empty_painted])


## A tile `size` pixels square, given the number `first` plus its own.
func _add_tile(mod: Mods.Mod, path: String, mod_scale: int, size: int, first: int) -> void:
	var number := first + path.get_file().get_basename().get_slice(".", 0).hex_to_int()
	var image := _load(mod, path)
	if image == null:
		return
	if image.get_size() != Vector2i(size, size) * mod_scale:
		_problem(mod, "%s is not %d pixels square" % [path.get_file(), size * mod_scale])
		return
	if size < 16:
		# in the top left of a place for a tile of 16
		var whole := Image.create_empty(16 * mod_scale, 16 * mod_scale, false, Image.FORMAT_RGBA8)
		whole.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
		image = whole
	var references := _read_colours(mod, path.get_basename() + ".colours")
	var any: PackedColorArray = references.values()[0] if not references.is_empty() else PackedColorArray()
	_set_tile(number, image, mod_scale, references.get(-1, any))


func _load(mod: Mods.Mod, path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_problem(mod, "%s could not be read" % path.get_file())
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## A `.colours` file: by palette number (and -1 for "all of it"), 16
## colours. Its lines are `NUMBER = rrggbb rrggbb ...`, or `all = ...` for
## a picture the game drew all in one palette.
func _read_colours(mod: Mods.Mod, path: String) -> Dictionary:
	var found := {}
	if not FileAccess.file_exists(path):
		return found
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var parts := line.split("=", false, 1)
		if parts.size() != 2 or line.begins_with(";") or line.begins_with("#"):
			continue
		var key := parts[0].strip_edges()
		var values := parts[1].strip_edges().split(" ", false)
		if values.size() != 16:
			_problem(mod, "%s: a line without 16 colours" % path.get_file())
			continue
		var palette := PackedColorArray()
		for value in values:
			palette.append(Color.html(value))
		found[-1 if key == "all" else key.to_int()] = palette
	return found


func _set_tile(number: int, image: Image, mod_scale: int, references: PackedColorArray) -> void:
	if number >= INDEX_SIZE * INDEX_SIZE:
		return
	if mod_scale != scale:
		image.resize(16 * scale, 16 * scale, Image.INTERPOLATE_NEAREST)
	_tiles[number] = image
	_references[number] = references


## True if the game's own tile `number` has nothing in it (or there is none).
func _is_empty(number: int) -> bool:
	if number >= 0x10000:
		return false
	var origin := (number >> 8) * 16 * 4096 + (number & 255) * 16
	for row in 16:
		for column in 16:
			if _original_tiles.size() > origin + row * 4096 + column and _original_tiles[origin + row * 4096 + column] != 0:
				return false
	return true


func _word(address: int) -> int:
	var at := Mods.rom_index(address)
	if at < 0 or at + 1 >= _rom.size():
		return 0
	return _rom.decode_u16(at)


func _pack() -> void:
	count = _tiles.size()
	var size := 16 * scale
	var across := ATLAS_WIDTH / size
	var most := across * (LARGEST_ATLAS / size)
	if count > most:
		problems.append("more tiles replaced than fit (%d of %d)" % [count, most])
		count = most
	var down := maxi((count + across - 1) / across, 1)
	atlas = Image.create_empty(ATLAS_WIDTH, down * size, false, Image.FORMAT_RGBA8)
	index = Image.create_empty(INDEX_SIZE, INDEX_SIZE, false, Image.FORMAT_RG8)
	colours = Image.create_empty(16, maxi(count, 1), false, Image.FORMAT_RGBA8)
	var numbers := _tiles.keys()
	numbers.sort()
	for slot in count:
		var number: int = numbers[slot]
		atlas.blit_rect(_tiles[number], Rect2i(0, 0, size, size), Vector2i(slot % across, slot / across) * size)
		index.set_pixel(number % INDEX_SIZE, number / INDEX_SIZE,
				Color8((slot + 1) & 0xFF, (slot + 1) >> 8, 0))
		var references: PackedColorArray = _references[number]
		for colour in references.size():
			colours.set_pixel(colour, slot, Color(references[colour], 1.0))
	_tiles.clear()
	_references.clear()
