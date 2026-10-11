class_name GameData
extends RefCounted
## Loads the data cache built from the ROMs by Tools/build_data.py.

const TILE_SHEET_SIZE := 4096

var tiles: ImageTexture
var palette: ImageTexture
var map: ImageTexture
var map_size: Vector2i
var zoom_y: ImageTexture
## Background raster parameters: line offset, timing offset, first and last visible line.
var bg_raster: Vector4i
## Per zoom fraction (0-15): 32 per-column shrink control steps and X steps.
var bg_shrink_steps: Array[PackedInt32Array] = []
var bg_x_steps: Array[PackedInt32Array] = []


static func data_dir() -> String:
	# The cache lives next to the project folder and is never part of the repo.
	return ProjectSettings.globalize_path("res://").path_join("../data/game").simplify_path()


func load_course(course: String) -> Error:
	var dir := data_dir()
	var tile_bytes := FileAccess.get_file_as_bytes(dir.path_join("tiles.bin"))
	var pal_bytes := FileAccess.get_file_as_bytes(dir.path_join(course + ".pal"))
	var map_file := FileAccess.open(dir.path_join(course + ".map"), FileAccess.READ)
	if tile_bytes.is_empty() or pal_bytes.is_empty() or map_file == null:
		push_error("Game data missing in %s - run Tools/build_data.py first." % dir)
		return ERR_FILE_NOT_FOUND
	var zoom_bytes := FileAccess.get_file_as_bytes(dir.path_join("zoom_y.bin"))
	var bg_zoom := FileAccess.get_file_as_bytes(dir.path_join("bg_zoom.bin"))
	if zoom_bytes.is_empty() or bg_zoom.is_empty():
		push_error("Game data incomplete in %s - run Tools/build_data.py again." % dir)
		return ERR_FILE_NOT_FOUND
	zoom_y = ImageTexture.create_from_image(Image.create_from_data(
			256, 256, false, Image.FORMAT_R8, zoom_bytes))
	bg_raster = Vector4i(bg_zoom.decode_s16(0), bg_zoom.decode_s16(2),
			bg_zoom.decode_s16(4), bg_zoom.decode_s16(6))
	bg_shrink_steps.clear()
	bg_x_steps.clear()
	for fraction in 16:
		var shrink := PackedInt32Array()
		var x := PackedInt32Array()
		for column in 32:
			shrink.append(bg_zoom.decode_s16(8 + (fraction * 32 + column) * 2))
			x.append(bg_zoom.decode_s16(8 + 1024 + (fraction * 32 + column) * 2))
		bg_shrink_steps.append(shrink)
		bg_x_steps.append(x)
	map_size = Vector2i(map_file.get_32(), map_file.get_32())
	var map_bytes := map_file.get_buffer(map_size.x * map_size.y * 4)
	tiles = ImageTexture.create_from_image(Image.create_from_data(
			TILE_SHEET_SIZE, TILE_SHEET_SIZE, false, Image.FORMAT_R8, tile_bytes))
	palette = ImageTexture.create_from_image(Image.create_from_data(
			16, 256, false, Image.FORMAT_RGBA8, pal_bytes))
	map = ImageTexture.create_from_image(Image.create_from_data(
			map_size.x, map_size.y, false, Image.FORMAT_RGBA8, map_bytes))
	return OK
