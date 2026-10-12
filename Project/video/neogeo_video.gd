class_name NeoGeoVideo
extends Node2D
## Draws the game's picture: backdrop, ground, sprites and the text layer.
##
## It draws either what is in the machine's video RAM, as the hardware would
## (320 pixels wide), or, given a GameScene, what the game asked for: the
## ground straight from the course's map and every object from its record.
## That picture can be wider than the hardware's (`view_width`), and is the
## same in the middle 320 pixels.
##
## Sprites are drawn as one quad per 16-pixel strip, in hardware priority
## order; the shader reproduces the hardware's tile lookup and shrinking.

const SCREEN := Vector2(320, 224)
const FIRST_LINE := 16
const LAST_SPRITE := 380
const SPRITES_PER_LINE := 96
const STRIP_TILES := 32
## Rows of the strip texture: the hardware has 381 sprites, a scene can have more.
const STRIP_ROWS := 2048
const WIDEST_VIEW := 1024
## The text layer's texture: three versions of its 40 columns, then one
## column each for what covers the picture to the left and to the right of
## the layer, and one that says which rows may be drawn in parts.
const CELLS_WIDTH := 123
const SIDE_CELLS := 120
const WHOLE_ROWS := 122
## Where fix.gdshader parts a row to move the HUD's left and right ends to
## the edges of a wider picture: before these columns, the first in rows of
## the picture's upper half and the second in the others. A row with text
## across where it would be parted is left whole.
const HUD_LEFT_END: Array[int] = [15, 13]
const HUD_RIGHT_START := 26
const FIRST_LOWER_ROW := 16
const SOLID := 1
const CLEAR := 2
## The game hides the ragged edges of its scrolling ground by filling the
## text layer's first and last column with a tile of one colour, on some
## screens two columns. A wider picture has no such edges, so up to this
## many columns that are one such tile from top to bottom are left out at
## each side. What the next column holds is taken to go on to the edge of
## the picture where it is a tile of one colour: the game also blacks the
## screen out with such tiles.
const MOST_MASK_COLUMNS := 4
## Which of a tile's 16 columns of pixels the hardware keeps at each of its
## shrink steps across (bit 0 is the leftmost).
const SHRINK_X: Array[int] = [
	0x0100, 0x0110, 0x1110, 0x1114, 0x5114, 0x5154, 0x5554, 0x5555,
	0x5755, 0x575D, 0xD75D, 0xD7DD, 0xF7DD, 0xF7DF, 0xFFDF, 0xFFFF]
## The ground's zoom tables in the program ROM: four words about its raster
## split (how many lines early it is set up, a timing allowance, the first
## and the last line it may be on), and by sixteenths of the zoom across,
## for each of 32 columns how much its width changes from the column before
## (in the high byte).
const GROUND_RASTER := 0x296E2
const GROUND_WIDTH_STEPS := 0x296F2
const PARAM_SCALE := 1024.0

var machine: RefCounted
## What the game asked for, to draw from instead of video RAM while the game
## has the screen. Null draws video RAM always.
var scene: GameScene
## How wide the picture is, in pixels. Beyond the hardware's 320 a race is
## drawn in full; of other screens only the backdrop is.
var view_width := int(SCREEN.x):
	set(value):
		view_width = clampi(value, int(SCREEN.x), WIDEST_VIEW)
		_lay_out()

## True while a race's HUD is shown: in a race, drawn from the game's
## records, and not while the game blacks the screen out.
var hud_shown := false

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
var _solid_cart := PackedByteArray()
var _solid_bios := PackedByteArray()
var _mask_columns := Vector2i.ZERO

var _zoom_y := PackedByteArray()
var _kept_columns: Array[PackedByteArray] = []
var _lookup_bytes := PackedByteArray()
var _lookup_tex: ImageTexture
var _map_key: Array = []
var _pattern_key: Array = []
var _pattern_period := 0

var _backdrop: ColorRect
var _ground: ColorRect
var _ground_material: ShaderMaterial
var _bars: Array[ColorRect] = []
var _sprites: Node2D
var _front_window: Control
var _front: Node2D
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
	_solid_cart = _solid_tiles(FileAccess.get_file_as_bytes(dir.path_join("fix_cart.bin")))
	_solid_bios = _solid_tiles(FileAccess.get_file_as_bytes(dir.path_join("fix_bios.bin")))

	_palette_bytes.resize(16 * 256 * 4)
	_palette_tex = ImageTexture.create_from_image(
			Image.create_from_data(16, 256, false, Image.FORMAT_RGBA8, _palette_bytes))
	_strip_bytes.resize(STRIP_TILES * STRIP_ROWS * 4)
	_strips_tex = ImageTexture.create_from_image(
			Image.create_from_data(STRIP_TILES, STRIP_ROWS, false, Image.FORMAT_RGBA8, _strip_bytes))
	_sprite_top.resize(LAST_SPRITE + 1)
	_sprite_rows.resize(LAST_SPRITE + 1)
	_cell_bytes.resize(CELLS_WIDTH * 32 * 4)
	_cells_tex = ImageTexture.create_from_image(
			Image.create_from_data(CELLS_WIDTH, 32, false, Image.FORMAT_RGBA8, _cell_bytes))

	_zoom_y = FileAccess.get_file_as_bytes(dir.path_join("zoom_y.bin"))
	_zoom_y.resize(0x10000)
	for mask in SHRINK_X:
		var kept := PackedByteArray()
		for column in 16:
			if mask & (1 << column):
				kept.append(column)
		_kept_columns.append(kept)
	_lookup_bytes.resize(WIDEST_VIEW * 2 * 4)
	_lookup_tex = ImageTexture.create_from_image(
			Image.create_from_data(WIDEST_VIEW, 2, false, Image.FORMAT_RGBA8, _lookup_bytes))

	_backdrop = ColorRect.new()
	add_child(_backdrop)

	_ground_material = ShaderMaterial.new()
	_ground_material.shader = preload("res://video/ground.gdshader")
	_ground_material.set_shader_parameter("lookup_tex", _lookup_tex)
	_ground_material.set_shader_parameter("tiles_tex", tiles)
	_ground_material.set_shader_parameter("pal_tex", _palette_tex)
	_ground = ColorRect.new()
	_ground.material = _ground_material
	_ground.visible = false
	add_child(_ground)

	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = preload("res://video/sprites.gdshader")
	_sprite_material.set_shader_parameter("strips_tex", _strips_tex)
	_sprite_material.set_shader_parameter("tiles_tex", tiles)
	_sprite_material.set_shader_parameter("pal_tex", _palette_tex)
	_sprite_material.set_shader_parameter("zoom_y_tex", zoom_y)
	_sprites = Node2D.new()
	_sprites.material = _sprite_material
	add_child(_sprites)

	for side in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		add_child(bar)
		_bars.append(bar)

	_front_window = Control.new()
	_front_window.clip_contents = true
	_front_window.size = SCREEN
	_front_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_front_window)
	_front = Node2D.new()
	_front.material = _sprite_material
	_front_window.add_child(_front)

	_fix_material = ShaderMaterial.new()
	_fix_material.shader = preload("res://video/fix.gdshader")
	_fix_material.set_shader_parameter("cells_tex", _cells_tex)
	_fix_material.set_shader_parameter("pal_tex", _palette_tex)
	_fix = ColorRect.new()
	_fix.material = _fix_material
	add_child(_fix)
	_lay_out()


## How far the hardware's picture is from the left edge.
func margin() -> int:
	return (view_width - int(SCREEN.x)) / 2


func _lay_out() -> void:
	if _fix == null:
		return
	var size := Vector2(view_width, SCREEN.y)
	var left := margin()
	_backdrop.size = size
	_ground.size = size
	_ground_material.set_shader_parameter("view_size", size)
	_sprites.position.x = left
	_front_window.position.x = left
	_fix.size = size
	_fix_material.set_shader_parameter("view_size", size)
	_fix_material.set_shader_parameter("margin", left)
	_bars[0].size = Vector2(left, SCREEN.y)
	_bars[1].size = Vector2(view_width - left - SCREEN.x, SCREEN.y)
	_bars[1].position.x = left + SCREEN.x


func _texture(path: String, width: int, height: int, format: Image.Format) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("Missing %s - run Tools/build_data.py" % path)
		bytes.resize(width * height)
	return ImageTexture.create_from_image(Image.create_from_data(width, height, false, format, bytes))


## For each of the 4096 tiles of a text layer ROM (as fix_cart.bin has them:
## 64 tiles to a row of 512 pixels), SOLID if it is of one colour all over
## and CLEAR if nothing of it shows.
func _solid_tiles(pixels: PackedByteArray) -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(4096)
	if pixels.size() < 512 * 512:
		return solid
	for tile in 4096:
		var at := (tile >> 6) * 8 * 512 + (tile & 63) * 8
		var colour := pixels[at]
		var same := true
		for row in 8:
			if not same:
				break
			for column in 8:
				if pixels[at + row * 512 + column] != colour:
					same = false
					break
		if same:
			solid[tile] = CLEAR if colour == 0 else SOLID
	return solid


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
		top: int, shrink_y: int, rows: int, shrink_x: int, seen_through := 0) -> void:
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
			(rows + shrink_x * 64 + seen_through * 1024) / PARAM_SCALE)
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


## True if the hardware left sprites out of the last picture drawn from video
## RAM, for having more than 96 on a line.
func over_line_limit() -> bool:
	return not _last_on_line.is_empty()


## Rebuilds everything from the machine's current state.
func refresh() -> void:
	var palette: PackedInt32Array = machine.palette
	var bank: int = machine.palette_bank * 0x1000
	for i in 0x1000:
		_palette_bytes.encode_u32(i * 4, _colours[palette[bank + i]])
	var from_scene := scene != null and scene.in_use()
	if from_scene:
		var to_come := scene.colours_to_come()
		for index: int in to_come:
			_palette_bytes.encode_u32(index * 4, _colours[to_come[index]])
	_palette_tex.update(Image.create_from_data(16, 256, false, Image.FORMAT_RGBA8, _palette_bytes))
	_backdrop.color = Color8(_palette_bytes[0xFFF * 4], _palette_bytes[0xFFF * 4 + 1], _palette_bytes[0xFFF * 4 + 2])
	_sprite_material.set_shader_parameter("auto_anim", machine.auto_anim_counter)
	_sprite_material.set_shader_parameter("auto_anim_enabled", (machine.lspc_mode & 8) == 0)
	var covered := _draw_text()
	hud_shown = from_scene and scene.in_race and scene.ground_on and not covered
	var in_race := from_scene and scene.in_race and scene.ground_on and view_width > int(SCREEN.x)
	# the HUD goes to the picture's edges, but not while the game is
	# blacking the screen out with the same layer
	var spread := margin() if in_race and not covered else 0
	# what video RAM has is the hardware's 320 pixels and no more
	var filled := from_scene
	if from_scene:
		_draw_scene(spread)
	else:
		_ground.visible = false
		RenderingServer.canvas_item_clear(_front.get_canvas_item())
		_draw_video_ram()
	for bar in _bars:
		bar.visible = not filled
	_fix_material.set_shader_parameter("open_sides",
			_mask_columns * 8 if filled and view_width > int(SCREEN.x) else Vector2i.ZERO)
	_fix_material.set_shader_parameter("cover_sides", filled)
	_fix_material.set_shader_parameter("spread", spread)


## The sprites as video RAM has them.
func _draw_video_ram() -> void:
	var vram: PackedInt32Array = machine.vram
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


## The text layer as video RAM has it. Returns whether any of it is taken
## to go on to the sides of a wider picture.
func _draw_text() -> bool:
	var vram: PackedInt32Array = machine.vram
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
		var out := (cell / 40 * CELLS_WIDTH + cell % 40) * 4
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
	var solid := _solid_cart if machine.fix_from_cart else _solid_bios
	var covered := false
	for side in 2:
		var masks := 0
		while masks < MOST_MASK_COLUMNS:
			var at := 0x7000 + (39 - masks if side == 1 else masks) * 32
			var tile := vram[at + 2]
			var mask := solid[tile & 0xFFF] == SOLID
			for row in range(3, 30):
				mask = mask and vram[at + row] == tile
			if not mask:
				break
			masks += 1
		_mask_columns[side] = masks
	for row in 32:
		for side in 2:
			var next := 39 - _mask_columns.y if side == 1 else _mask_columns.x
			var word := vram[0x7000 + next * 32 + row]
			var cover := 0
			if solid[word & 0xFFF] == SOLID:
				cover = (word & 0xFFF) | ((word >> 12) << 16) | (0xFF << 24)
				covered = covered or (row >= 2 and row < 30)
			_cell_bytes.encode_u32((row * CELLS_WIDTH + SIDE_CELLS + side) * 4, cover)
		var whole := false
		for column: int in [HUD_LEFT_END[0 if row < FIRST_LOWER_ROW else 1], HUD_RIGHT_START]:
			var at := 0x7000 + column * 32 + row
			if solid[vram[at] & 0xFFF] != CLEAR and solid[vram[at - 32] & 0xFFF] != CLEAR:
				whole = true
		_cell_bytes.encode_u32((row * CELLS_WIDTH + WHOLE_ROWS) * 4, 0 if whole else 0xFF000000)
	_cells_tex.update(Image.create_from_data(CELLS_WIDTH, 32, false, Image.FORMAT_RGBA8, _cell_bytes))
	_fix_material.set_shader_parameter("fix_tex", _fix_cart if machine.fix_from_cart else _fix_bios)
	return covered


## The ground and the objects as the game asked for them. `spread` is how
## far the parts of the HUD at the right are moved towards the picture's edge.
func _draw_scene(spread: int) -> void:
	_last_on_line.clear()
	# A race is drawn as wide as the picture is. Of other screens only the
	# backdrop is, over and over; the rest is kept to the hardware's 320
	# pixels, as screens put things just off the hardware's screen to hide
	# them.
	var open := scene.in_race
	var backdrop := 0
	if not scene.ground_on and view_width > int(SCREEN.x) and scene.backdrop_period > 0:
		backdrop = scene.backdrop_strips
	var left := -margin()
	var right := int(SCREEN.x) - left
	var bottom := FIRST_LINE + int(SCREEN.y)
	var strips := scene.strips
	var points: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	var colours: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
	var uvs: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	var indices: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	var count := mini(strips.size() / GameScene.STRIP_FIELDS, STRIP_ROWS)
	for strip in count:
		var at := strip * GameScene.STRIP_FIELDS
		var x := strips[at] + strips[at + 5] * spread
		var top := strips[at + 1]
		var rows := strips[at + 2]
		var first_line := maxi(top, FIRST_LINE)
		var last_line := mini(top + rows * 16, bottom)
		if strip < backdrop:
			var period := scene.backdrop_period
			x -= (ceili(float(x + 16 - left) / period) - 1) * period
			while x < right:
				_add_strip(points[0], colours[0], uvs[0], indices[0], strip, x, first_line, last_line,
						top & 0x1FF, strips[at + 4], rows, strips[at + 3])
				x += period
			continue
		var to := 0
		if not open:
			to = 1
			# as on the hardware, which counts across in nine bits: some
			# screens rely on a row of columns coming round on the left
			x &= 0x1FF
			if x > 0x1F0:
				x -= 0x200
			if x >= int(SCREEN.x):
				continue
		if x >= right or x + 16 <= left:
			continue
		_add_strip(points[to], colours[to], uvs[to], indices[to], strip, x, first_line, last_line,
				top & 0x1FF, strips[at + 4], rows, strips[at + 3], strips[at + 6])
	var bytes := scene.strip_tiles.slice(0, count * GameScene.STRIP_BYTES)
	bytes.resize(_strip_bytes.size())
	_strips_tex.update(Image.create_from_data(
			STRIP_TILES, STRIP_ROWS, false, Image.FORMAT_RGBA8, bytes))
	_show_strips(_sprites, points[0], colours[0], uvs[0], indices[0])
	_show_strips(_front, points[1], colours[1], uvs[1], indices[1])

	_ground.visible = scene.ground_on and scene.zoom.x >= 0x10
	if _ground.visible:
		_load_map()
		_look_up_ground()
		if not scene.in_race and view_width > int(SCREEN.x):
			_repeat_ground()
		_ground_material.set_shader_parameter("auto_anim", machine.auto_anim_counter)
		_ground_material.set_shader_parameter("auto_anim_enabled", (machine.lspc_mode & 8) == 0)


func _show_strips(on: Node2D, points: PackedVector2Array, colours: PackedColorArray,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var item := on.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(item, indices, points, colours, uvs)


## Makes the textures of the course's map when the course has changed: the
## block number of every place, and the 16 by 16 tiles of every block, 16
## blocks to a texture row, each as it is in the ROM (a column at a time;
## tile number, then flips and palette).
func _load_map() -> void:
	var key := [scene.map_places, scene.blocks, scene.map_across, scene.map_down, scene.block_count]
	if key == _map_key:
		return
	_map_key = key
	var places := PackedByteArray()
	var across := maxi(scene.map_across, 1)
	var down := maxi(scene.map_down, 1)
	places.resize(across * down * 4)
	for place in across * down:
		places.encode_u16(place * 4, machine.r16(scene.map_places + place * 2))
	var block_bytes := PackedByteArray()
	var rom: PackedByteArray = machine.rom
	for block in scene.block_count:
		var address: int = machine.r32(scene.blocks + block * 4) & 0xFFFFFF
		if address >= 0x200000:
			address -= 0x100000
		block_bytes.append_array(rom.slice(address, address + 0x400))
	var block_rows := maxi((scene.block_count + 15) / 16, 1)
	block_bytes.resize(block_rows * 16 * 0x400)
	_ground_material.set_shader_parameter("places_tex", ImageTexture.create_from_image(
			Image.create_from_data(across, down, false, Image.FORMAT_RGBA8, places)))
	_ground_material.set_shader_parameter("blocks_tex", ImageTexture.create_from_image(
			Image.create_from_data(0x1000, block_rows, false, Image.FORMAT_RGBA8, block_bytes)))


## Works out which column of the map's tiles, and which of a tile's pixels,
## is at every pixel across the picture, and likewise down it, as the
## original's ground of 32 hardware sprites shows them ($13CAA, $13D34 and
## the hardware's shrinking), and carries on in the same way to the sides
## of the hardware's 32 columns.
func _look_up_ground() -> void:
	var rom: PackedByteArray = machine.rom
	var zoom_x := scene.zoom.x
	var zoom_y := scene.zoom.y
	var blocks_across := maxi(scene.map_across, 1)
	var blocks_down := maxi(scene.map_down, 1)
	_lookup_bytes.fill(0)

	# Across: a column of tiles is as many pixels wide as the zoom has whole
	# sixteenths, and some columns one more, by a table of 32.
	var wider := PackedByteArray()
	var steps := GROUND_WIDTH_STEPS + (zoom_x & 0xF) * 64
	var sum := 0
	for column in 32:
		sum += rom.decode_s16(steps + column * 2) >> 8
		wider.append(sum)
	var narrowest := (((zoom_x - 0x10) & 0xF0) << 4) + zoom_y - 1
	var whole := zoom_x >> 4
	var first_column := scene.camera.x >> 4
	var start := ((-(((scene.camera.x & 15) * zoom_x) >> 1)) & 0xFF80) >> 7
	if start >= 0x100:
		start -= 0x200
	var view_left := -margin()
	var view_right := view_width + view_left
	var x := start
	var column := 0
	while x < view_right:
		var extra := wider[column & 31]
		_fill_column(x - view_left, ((narrowest + (extra << 8)) >> 8) & 0xF,
				_tile_in_map(first_column + column, blocks_across))
		x += whole + extra
		column += 1
	x = start
	column = -1
	while x > view_left:
		var extra := wider[column & 31]
		x -= whole + extra
		_fill_column(x - view_left, ((narrowest + (extra << 8)) >> 8) & 0xF,
				_tile_in_map(first_column + column, blocks_across))
		column -= 1

	# Down: the hardware's own table says which line of the 512 of the ring
	# of tiles is on each line of the picture. The ring is set a second time
	# lower down the picture where it would end.
	var raster_early := rom.decode_s16(GROUND_RASTER)
	var raster_first := rom.decode_s16(GROUND_RASTER + 4)
	var raster_last := rom.decode_s16(GROUND_RASTER + 6)
	var shrink := (zoom_y - 1) & 0xFF
	var period := (shrink + 1) << 1
	var first_top := zoom_y - (((scene.camera.y & 0x1FF) * zoom_y) >> 8)
	var split := first_top + zoom_y
	var first_row := (scene.camera.y >> 4) - 2
	for y in int(SCREEN.y):
		var line := y + FIRST_LINE
		var top := first_top
		if split < raster_first or (split <= raster_last and line >= split - raster_early):
			top = split + zoom_y
		var ring_line := (line - top) & 0x1FF
		var zoom_line := ring_line & 0xFF
		var upside_down := (ring_line & 0x100) != 0
		if upside_down:
			zoom_line ^= 0xFF
		zoom_line %= period
		if zoom_line > shrink:
			zoom_line = period - 1 - zoom_line
			upside_down = not upside_down
		var entry := _zoom_y[shrink * 256 + zoom_line]
		if upside_down:
			entry ^= 0x1FF
		var row := _tile_in_map(first_row + (((entry >> 4) + 16 - first_row) & 31), blocks_down)
		_lookup_bytes.encode_u32((WIDEST_VIEW + y) * 4, row | ((entry & 15) << 16) | (0xFF << 24))
	_lookup_tex.update(Image.create_from_data(WIDEST_VIEW, 2, false, Image.FORMAT_RGBA8, _lookup_bytes))


## Outside a race the ground is a still backdrop, as wide as the hardware's
## picture. If what shows of it is a pattern that repeats, it is repeated
## here to both sides.
func _repeat_ground() -> void:
	var first := margin() + _mask_columns.x * 8
	var shown := int(SCREEN.x) - (_mask_columns.x + _mask_columns.y) * 8
	var key := [_map_key, scene.camera, scene.zoom, first, shown]
	if key != _pattern_key:
		_pattern_key = key
		_pattern_period = _ground_period(first, shown)
	if _pattern_period == 0:
		return
	var pattern := _lookup_bytes.slice(first * 4, (first + _pattern_period) * 4)
	for x in view_width:
		_lookup_bytes.encode_u32(x * 4, pattern.decode_u32(posmod(x - first, _pattern_period) * 4))
	_lookup_tex.update(Image.create_from_data(WIDEST_VIEW, 2, false, Image.FORMAT_RGBA8, _lookup_bytes))


## After how many pixels the ground in the `shown` pixels from `first` of
## the lookup repeats itself, or 0 if it does not. It is only looked into
## tile by tile and not zoomed, and it has to repeat at least twice.
func _ground_period(first: int, shown: int) -> int:
	if scene.zoom != Vector2i(0x100, 0x100):
		return 0
	var columns := PackedInt32Array()
	for x in range(first, first + shown):
		var column := _lookup_bytes.decode_u16(x * 4)
		if columns.is_empty() or columns[-1] != column:
			columns.append(column)
	var rows := PackedInt32Array()
	for y in int(SCREEN.y):
		var row := _lookup_bytes.decode_u16((WIDEST_VIEW + y) * 4)
		if rows.is_empty() or rows[-1] != row:
			rows.append(row)
	var tiles := PackedInt32Array()
	for column in columns:
		for row in rows:
			var place: int = machine.r16(scene.map_places + ((row >> 4) * scene.map_across + (column >> 4)) * 2)
			var block: int = machine.r32(scene.blocks + place * 4)
			tiles.append(machine.r32(block + ((column & 15) * 16 + (row & 15)) * 4))
	var down := rows.size()
	for period in range(1, columns.size() / 2 + 1):
		if tiles.slice(0, (columns.size() - period) * down) == tiles.slice(period * down):
			return period * 16
	return 0


## Which of the map's tiles, across or down, the tile `tile` from its edge
## is. The map repeats, and as the original counts blocks in a byte ($13706)
## it starts again after 256 blocks whether it fits or not.
func _tile_in_map(tile: int, blocks: int) -> int:
	return ((((tile >> 4) & 0xFF) % blocks) << 4) | (tile & 15)


## Notes the pixels of one column of tiles, the leftmost at `x` of the view.
func _fill_column(x: int, shrink: int, column: int) -> void:
	var kept := _kept_columns[shrink]
	for index in kept.size():
		var at := x + index
		if at >= 0 and at < view_width:
			_lookup_bytes.encode_u32(at * 4, column | (kept[index] << 16) | (0xFF << 24))
