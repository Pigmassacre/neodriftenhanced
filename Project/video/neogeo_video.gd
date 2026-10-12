class_name NeoGeoVideo
extends Node2D
## Draws the machine's video state: backdrop, sprites and the text layer.
##
## Sprites are drawn as one quad per 16-pixel strip, in hardware priority
## order; the shader reproduces the hardware's tile lookup and shrinking.

const SCREEN := Vector2(320, 224)
const FIRST_LINE := 16
const LAST_SPRITE := 380
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
	_cell_bytes.resize(80 * 32 * 4)
	_cells_tex = ImageTexture.create_from_image(
			Image.create_from_data(80, 32, false, Image.FORMAT_RGBA8, _cell_bytes))

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


## Rebuilds everything from the machine's current video state.
func refresh() -> void:
	var vram: PackedInt32Array = machine.vram
	var palette: PackedInt32Array = machine.palette
	var bank: int = machine.palette_bank * 0x1000
	for i in 0x1000:
		_palette_bytes.encode_u32(i * 4, _colours[palette[bank + i]])
	_palette_tex.update(Image.create_from_data(16, 256, false, Image.FORMAT_RGBA8, _palette_bytes))
	_backdrop.color = Color8(_palette_bytes[0xFFF * 4], _palette_bytes[0xFFF * 4 + 1], _palette_bytes[0xFFF * 4 + 2])

	# Strips whose vertical position changed while the picture was drawn are
	# split into bands, each band using the value that was in effect there.
	var changes := {}
	for change: Vector3i in machine.midframe_y:
		if not changes.has(change.y):
			changes[change.y] = []
		changes[change.y].append(change)

	var points := PackedVector2Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var top := 0
	var rows := 0
	var shrink_y := 0
	var x := 0
	var shrink_x := 0
	for sprite in range(1, LAST_SPRITE + 1):
		var y_control := vram[0x8200 + sprite]
		var shrink := vram[0x8000 + sprite]
		if y_control & 0x40:
			# chained to the previous strip: same height, placed right after it
			x = (x + shrink_x + 1) & 0x1FF
		else:
			top = (0x200 - (y_control >> 7)) & 0x1FF
			rows = y_control & 0x3F
			shrink_y = shrink & 0xFF
			x = vram[0x8400 + sprite] >> 7
		shrink_x = (shrink >> 8) & 0xF
		if rows == 0:
			continue
		var left := x - 0x200 if x > 0x1F0 else x
		if left >= SCREEN.x:
			continue
		var base := sprite * 64
		var out := sprite * STRIP_TILES * 4
		# `rows` is the height on screen; a shrunk strip shows tiles beyond it
		var tiles_used := STRIP_TILES if (shrink_y < 0xFF or rows > STRIP_TILES) else rows
		for tile in tiles_used:
			var attr := vram[base + tile * 2 + 1]
			_strip_bytes.encode_u32(out + tile * 4,
					vram[base + tile * 2] | ((attr & 0xF) << 16) | ((attr >> 8) << 24))
		if changes.has(sprite) and (y_control & 0x40) == 0:
			var band_start := FIRST_LINE
			for change: Vector3i in changes[sprite]:
				var old_top := (0x200 - (change.z >> 7)) & 0x1FF
				_add_strip(points, colours, uvs, indices, sprite, left, band_start, change.x,
						old_top, shrink_y, change.z & 0x3F, shrink_x)
				band_start = change.x
			_add_strip(points, colours, uvs, indices, sprite, left, band_start,
					FIRST_LINE + int(SCREEN.y), top, shrink_y, rows, shrink_x)
		else:
			_add_strip(points, colours, uvs, indices, sprite, left, FIRST_LINE,
					FIRST_LINE + int(SCREEN.y), top, shrink_y, rows, shrink_x)
	_strips_tex.update(Image.create_from_data(
			STRIP_TILES, STRIP_ROWS, false, Image.FORMAT_RGBA8, _strip_bytes))
	var item := _sprites.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(item, indices, points, colours, uvs)
	_sprite_material.set_shader_parameter("auto_anim", machine.auto_anim_counter)
	_sprite_material.set_shader_parameter("auto_anim_enabled", (machine.lspc_mode & 8) == 0)

	# Text changed while the picture was being drawn shows the old text above
	# the raster line of the change. The texture's right half holds the old
	# words, and a cell's fourth byte the screen line where the new one starts.
	# Going backwards leaves a cell's earliest change in place.
	var old_text := {}
	for index in range(machine.midframe_text.size() - 1, -1, -1):
		var change: Vector3i = machine.midframe_text[index]
		old_text[change.y] = change
	for cell in 40 * 32:
		var address := 0x7000 + (cell % 40) * 32 + cell / 40
		var word := vram[address]
		var out := (cell / 40 * 80 + cell % 40) * 4
		var split := 0
		if old_text.has(address):
			var change: Vector3i = old_text[address]
			split = clampi(change.x - FIRST_LINE, 0, int(SCREEN.y))
			_cell_bytes.encode_u32(out + 160, (change.z & 0xFFF) | ((change.z >> 12) << 16))
		_cell_bytes.encode_u32(out, (word & 0xFFF) | ((word >> 12) << 16) | (split << 24))
	_cells_tex.update(Image.create_from_data(80, 32, false, Image.FORMAT_RGBA8, _cell_bytes))
	_fix_material.set_shader_parameter("fix_tex", _fix_cart if machine.fix_from_cart else _fix_bios)
