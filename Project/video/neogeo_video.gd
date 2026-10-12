class_name NeoGeoVideo
extends Node2D
## Draws the machine's video state: backdrop, sprites and the text layer.
##
## Sprites are drawn as one quad per 16-pixel strip, in hardware priority
## order; the shader reproduces the hardware's tile lookup and shrinking.

const SCREEN := Vector2(320, 224)
const FIRST_LINE := 16
const LAST_SPRITE := 380
const SPRITES_PER_LINE := 96
const STRIP_TILES := 32
const STRIP_ROWS := 512
const PARAM_SCALE := 1024.0

var machine: RefCounted

var _colours := PackedInt32Array()
var _palette_bytes := PackedByteArray()
var _palette_tex: ImageTexture
var _strip_bytes := PackedByteArray()
var _strips_tex: ImageTexture
var _cell_bytes := PackedByteArray()
var _sprite_top := PackedInt32Array()
var _sprite_rows := PackedInt32Array()
var _last_on_line := PackedInt32Array()
var _first_cut := 0
var _cells_tex: ImageTexture
var _fix_cart: ImageTexture
var _fix_bios: ImageTexture

var _backdrop: ColorRect
var _sprites: Node2D
var _fix: ColorRect
var _sprite_material: ShaderMaterial
var _fix_material: ShaderMaterial


func _ready() -> void:
	_build_colour_table()
	var dir := MachineLoader.repo_dir().path_join("data/game")
	var tiles := _texture(dir.path_join("tiles.bin"), 4096, 4096, Image.FORMAT_R8)
	var zoom_y := _texture(dir.path_join("zoom_y.bin"), 256, 256, Image.FORMAT_R8)
	_fix_cart = _texture(dir.path_join("fix_cart.bin"), 512, 512, Image.FORMAT_R8)
	_fix_bios = _texture(dir.path_join("fix_bios.bin"), 512, 512, Image.FORMAT_R8)

	_palette_bytes.resize(16 * 256 * 4)
	_palette_tex = ImageTexture.create_from_image(
			Image.create_from_data(16, 256, false, Image.FORMAT_RGBA8, _palette_bytes))
	_strip_bytes.resize(STRIP_TILES * STRIP_ROWS * 4)
	_strips_tex = ImageTexture.create_from_image(
			Image.create_from_data(STRIP_TILES, STRIP_ROWS, false, Image.FORMAT_RGBA8, _strip_bytes))
	_sprite_top.resize(LAST_SPRITE + 1)
	_sprite_rows.resize(LAST_SPRITE + 1)
	_cell_bytes.resize(120 * 32 * 4)
	_cells_tex = ImageTexture.create_from_image(
			Image.create_from_data(120, 32, false, Image.FORMAT_RGBA8, _cell_bytes))

	_backdrop = ColorRect.new()
	_backdrop.size = SCREEN
	add_child(_backdrop)

	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = preload("res://video/sprites.gdshader")
	_sprite_material.set_shader_parameter("strips_tex", _strips_tex)
	_sprite_material.set_shader_parameter("tiles_tex", tiles)
	_sprite_material.set_shader_parameter("pal_tex", _palette_tex)
	_sprite_material.set_shader_parameter("zoom_y_tex", zoom_y)
	_sprites = Node2D.new()
	_sprites.material = _sprite_material
	add_child(_sprites)

	_fix_material = ShaderMaterial.new()
	_fix_material.shader = preload("res://video/fix.gdshader")
	_fix_material.set_shader_parameter("cells_tex", _cells_tex)
	_fix_material.set_shader_parameter("pal_tex", _palette_tex)
	_fix = ColorRect.new()
	_fix.size = SCREEN
	_fix.material = _fix_material
	add_child(_fix)


func _texture(path: String, width: int, height: int, format: Image.Format) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Missing %s - run Tools/build_data.py" % path)
		bytes.resize(width * height)
	return ImageTexture.create_from_image(Image.create_from_data(width, height, false, format, bytes))


## Every 16-bit palette word as packed RGBA. The video DAC is a 5-bit
## resistor ladder per channel (3k9, 2k2, 1k, 470, 220 ohm); the "dark" bit
## adds an 8k2 pull-down.
func _build_colour_table() -> void:
	var conductance := [1.0 / 3900, 1.0 / 2200, 1.0 / 1000, 1.0 / 470, 1.0 / 220]
	var total := 0.0
	for g: float in conductance:
		total += g
	var levels := [PackedInt32Array(), PackedInt32Array()]
	for dark in 2:
		for value in 32:
			var sum := 0.0
			for bit in 5:
				if value >> bit & 1:
					sum += conductance[bit]
			levels[dark].append(int(255.0 * sum / (total + (1.0 / 8200 if dark == 1 else 0.0)) + 0.5))
	_colours.resize(0x10000)
	for word in 0x10000:
		var table: PackedInt32Array = levels[word >> 15]
		var r := table[((word >> 7) & 0x1E) | ((word >> 14) & 1)]
		var g := table[((word >> 3) & 0x1E) | ((word >> 13) & 1)]
		var b := table[((word << 1) & 0x1E) | ((word >> 12) & 1)]
		_colours[word] = r | (g << 8) | (b << 16) | (0xFF << 24)


## One quad for a sprite strip between two raster lines.
func _add_strip(points: PackedVector2Array, colours: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array, sprite: int, left: int, from_line: int, to_line: int,
		top: int, shrink_y: int, rows: int, shrink_x: int) -> void:
	if to_line <= from_line or rows == 0:
		return
	var first := points.size()
	var y0 := from_line - FIRST_LINE
	var y1 := to_line - FIRST_LINE
	points.append(Vector2(left, y0))
	points.append(Vector2(left + 16, y0))
	points.append(Vector2(left + 16, y1))
	points.append(Vector2(left, y1))
	uvs.append(Vector2(0, from_line))
	uvs.append(Vector2(16, from_line))
	uvs.append(Vector2(16, to_line))
	uvs.append(Vector2(0, to_line))
	var params := Color(sprite / PARAM_SCALE, top / PARAM_SCALE, shrink_y / PARAM_SCALE,
			(rows + shrink_x * 64) / PARAM_SCALE)
	for corner in 4:
		colours.append(params)
	indices.append_array([first, first + 1, first + 2, first, first + 2, first + 3])


## As _add_strip, but leaves out the lines where the sprite is beyond the
## hardware's limit of sprites on one line.
func _add_limited(points: PackedVector2Array, colours: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array, sprite: int, left: int, from_line: int, to_line: int,
		top: int, shrink_y: int, rows: int, shrink_x: int) -> void:
	if _last_on_line.is_empty() or sprite <= _first_cut:
		_add_strip(points, colours, uvs, indices, sprite, left, from_line, to_line,
				top, shrink_y, rows, shrink_x)
		return
	var start := -1
	for line in range(from_line, to_line):
		if _last_on_line[line - FIRST_LINE] >= sprite:
			if start < 0:
				start = line
		elif start >= 0:
			_add_strip(points, colours, uvs, indices, sprite, left, start, line,
					top, shrink_y, rows, shrink_x)
			start = -1
	if start >= 0:
		_add_strip(points, colours, uvs, indices, sprite, left, start, to_line,
				top, shrink_y, rows, shrink_x)


## Where every strip is, given the vertical control words: its top line,
## height in rows, vertical shrink and x, four numbers a strip. A strip
## chained to the one before takes that one's top, height and shrink and
## sits right after it.
func _strip_geometry(y_controls: PackedInt32Array, vram: PackedInt32Array) -> PackedInt32Array:
	var geometry := PackedInt32Array()
	geometry.resize((LAST_SPRITE + 1) * 4)
	var top := 0
	var rows := 0
	var shrink_y := 0
	var x := 0
	var shrink_x := 0
	for sprite in range(1, LAST_SPRITE + 1):
		var y_control := y_controls[sprite]
		var shrink := vram[0x8000 + sprite]
		if y_control & 0x40:
			x = (x + shrink_x + 1) & 0x1FF
		else:
			top = (0x200 - (y_control >> 7)) & 0x1FF
			rows = y_control & 0x3F
			shrink_y = shrink & 0xFF
			x = vram[0x8400 + sprite] >> 7
		shrink_x = (shrink >> 8) & 0xF
		geometry[sprite * 4] = top
		geometry[sprite * 4 + 1] = rows
		geometry[sprite * 4 + 2] = shrink_y
		geometry[sprite * 4 + 3] = x
	return geometry


## The hardware draws at most 96 sprite strips on a line, lowest numbers
## first, whether or not they are on screen sideways. Fills _last_on_line with
## the last strip drawn on each screen line, or empties it if no line is full.
func _find_line_limits(vram: PackedInt32Array) -> void:
	_last_on_line.clear()
	var lines := int(SCREEN.y)
	var change := PackedInt32Array()
	change.resize(lines + 1)
	var top := 0
	var rows := 0
	for sprite in range(1, LAST_SPRITE + 1):
		var y_control := vram[0x8200 + sprite]
		if (y_control & 0x40) == 0:
			top = (0x200 - (y_control >> 7)) & 0x1FF
			rows = y_control & 0x3F
		_sprite_top[sprite] = top
		_sprite_rows[sprite] = rows
		if rows == 0:
			continue
		if rows > 0x20:
			change[0] += 1
			continue
		# on screen lines first..last-1, counted modulo 512
		var first := (top - FIRST_LINE) & 0x1FF
		var last := first + rows * 16
		if first < lines:
			change[first] += 1
			change[mini(last, lines)] -= 1
		if last > 0x200:
			change[0] += 1
			change[mini(last - 0x200, lines)] -= 1
	var count := 0
	var full := false
	for line in lines:
		count += change[line]
		change[line] = count
		full = full or count > SPRITES_PER_LINE
	if not full:
		return
	_last_on_line.resize(lines)
	_last_on_line.fill(LAST_SPRITE)
	_first_cut = LAST_SPRITE
	for line in lines:
		if change[line] <= SPRITES_PER_LINE:
			continue
		count = 0
		for sprite in range(1, LAST_SPRITE + 1):
			var height := _sprite_rows[sprite] * 16
			if height == 0:
				continue
			if height <= 0x200 and ((line + FIRST_LINE - _sprite_top[sprite]) & 0x1FF) >= height:
				continue
			count += 1
			if count == SPRITES_PER_LINE:
				_last_on_line[line] = sprite
				_first_cut = mini(_first_cut, sprite)
				break


## Rebuilds everything from the machine's current video state.
func refresh() -> void:
	var vram: PackedInt32Array = machine.vram
	var palette: PackedInt32Array = machine.palette
	var bank: int = machine.palette_bank * 0x1000
	for i in 0x1000:
		_palette_bytes.encode_u32(i * 4, _colours[palette[bank + i]])
	_palette_tex.update(Image.create_from_data(16, 256, false, Image.FORMAT_RGBA8, _palette_bytes))
	_backdrop.color = Color8(_palette_bytes[0xFFF * 4], _palette_bytes[0xFFF * 4 + 1], _palette_bytes[0xFFF * 4 + 2])

	# The game changes strips' vertical control words while the picture is
	# being drawn (to move the background, or to clear the screen). The frame
	# is cut into bands at those raster lines, and each band is drawn with
	# the words that were in effect there: stepping back through the changes
	# from the final state gives the earlier ones.
	# A band starts on the line after a change. The line of the change itself
	# is in between: the hardware (as MAME models it) picks the strips for a
	# line when the line starts, from the words as they are then, but draws
	# them when it ends, with the words as they are by then.
	var band_starts: Array[int] = [FIRST_LINE]
	for change: Vector3i in machine.midframe_y:
		if change.x + 1 > FIRST_LINE and not band_starts.has(change.x + 1):
			band_starts.append(change.x + 1)
	band_starts.sort()
	var y_controls := vram.slice(0x8200, 0x8200 + LAST_SPRITE + 1)
	var bands: Array[PackedInt32Array] = []
	bands.resize(band_starts.size())
	for band in range(band_starts.size() - 1, -1, -1):
		bands[band] = _strip_geometry(y_controls, vram)
		for index in range(machine.midframe_y.size() - 1, -1, -1):
			var change: Vector3i = machine.midframe_y[index]
			if change.x + 1 == band_starts[band]:
				y_controls[change.y] = change.z
	band_starts.append(FIRST_LINE + int(SCREEN.y))

	_find_line_limits(vram)
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for sprite in range(1, LAST_SPRITE + 1):
		var shrink_x := (vram[0x8000 + sprite] >> 8) & 0xF
		var tiles_used := 0
		var band := 0
		while band < bands.size():
			# bands in which the strip is the same are drawn as one
			var geometry := bands[band].slice(sprite * 4, sprite * 4 + 4)
			var from_line := band_starts[band]
			band += 1
			while band < bands.size() and bands[band].slice(sprite * 4, sprite * 4 + 4) == geometry:
				band += 1
			var rows := geometry[1]
			if rows == 0:
				continue
			var to_line := band_starts[band]
			if band < bands.size():
				# the run ends with the line of a change: drawn only if the
				# strip was on that line before, and then as it is after. A
				# strip set to no height is still drawn there, at full height.
				to_line -= 1
				var after := bands[band].slice(sprite * 4, sprite * 4 + 4)
				var after_left := after[3] - 0x200 if after[3] > 0x1F0 else after[3]
				if after_left < SCREEN.x and to_line >= from_line \
						and (rows > 0x20 or ((to_line - geometry[0]) & 0x1FF) < rows * 16):
					tiles_used = STRIP_TILES
					_add_limited(points, colours, uvs, indices, sprite, after_left, to_line, to_line + 1,
							after[0], after[2], after[1] if after[1] != 0 else 0x20, shrink_x)
			var left := geometry[3] - 0x200 if geometry[3] > 0x1F0 else geometry[3]
			if left >= SCREEN.x:
				continue
			# `rows` is the height on screen; a shrunk strip shows tiles beyond it
			tiles_used = maxi(tiles_used, STRIP_TILES if (geometry[2] < 0xFF or rows > STRIP_TILES) else rows)
			_add_limited(points, colours, uvs, indices, sprite, left, from_line, to_line,
					geometry[0], geometry[2], rows, shrink_x)
		var base := sprite * 64
		var out := sprite * STRIP_TILES * 4
		for tile in tiles_used:
			var attr := vram[base + tile * 2 + 1]
			_strip_bytes.encode_u32(out + tile * 4,
					vram[base + tile * 2] | ((attr & 0xF) << 16) | ((attr >> 8) << 24))
	_strips_tex.update(Image.create_from_data(
			STRIP_TILES, STRIP_ROWS, false, Image.FORMAT_RGBA8, _strip_bytes))
	var item := _sprites.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(item, indices, points, colours, uvs)
	_sprite_material.set_shader_parameter("auto_anim", machine.auto_anim_counter)
	_sprite_material.set_shader_parameter("auto_anim_enabled", (machine.lspc_mode & 8) == 0)

	# Text changed while the picture was being drawn shows the old text above
	# the raster line of the change. A cell can change twice in a frame (the
	# attract mode blanks its text and writes it again), so the texture holds
	# three versions side by side: the final one, the one before the last
	# change and the one before the change before that. A cell's fourth byte
	# is the screen line where that version starts.
	var text_changes := {}
	for change in machine.midframe_text:
		if not text_changes.has(change.y):
			text_changes[change.y] = []
		text_changes[change.y].append(change)
	for cell in 40 * 32:
		var address := 0x7000 + (cell % 40) * 32 + cell / 40
		var word := vram[address]
		var out := (cell / 40 * 120 + cell % 40) * 4
		var split := 0
		if text_changes.has(address):
			var list: Array = text_changes[address]
			var last: Vector3i = list[-1]
			split = clampi(last.x - FIRST_LINE, 0, int(SCREEN.y))
			var before := 0
			if list.size() > 1:
				var earlier: Vector3i = list[-2]
				before = clampi(earlier.x - FIRST_LINE, 0, int(SCREEN.y))
				_cell_bytes.encode_u32(out + 320, (earlier.z & 0xFFF) | ((earlier.z >> 12) << 16))
			_cell_bytes.encode_u32(out + 160, (last.z & 0xFFF) | ((last.z >> 12) << 16) | (before << 24))
		_cell_bytes.encode_u32(out, (word & 0xFFF) | ((word >> 12) << 16) | (split << 24))
	_cells_tex.update(Image.create_from_data(120, 32, false, Image.FORMAT_RGBA8, _cell_bytes))
	_fix_material.set_shader_parameter("fix_tex", _fix_cart if machine.fix_from_cart else _fix_bios)
