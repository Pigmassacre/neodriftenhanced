class_name SafeFile
extends RefCounted
## Writes the player's files (options, best times, courses) so that a crash,
## a kill or a power cut partway through never leaves one half written:
## each is written next to itself as NAME.tmp, then moved into place, which
## swaps the whole file at once. A .tmp left behind by a kill is written over
## the next time.


static func write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(_temporary(path), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	return _finish(file, path)


static func write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(_temporary(path), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return _finish(file, path)


static func save_config(config: ConfigFile, path: String) -> Error:
	var error := config.save(_temporary(path))
	return error if error != OK else _put_in_place(path)


static func save_png(image: Image, path: String) -> Error:
	var error := image.save_png(_temporary(path))
	return error if error != OK else _put_in_place(path)


static func _temporary(path: String) -> String:
	return path + ".tmp"


static func _finish(file: FileAccess, path: String) -> Error:
	var error := file.get_error()
	file.close()
	return error if error != OK else _put_in_place(path)


static func _put_in_place(path: String) -> Error:
	var whole := ProjectSettings.globalize_path(path)
	return DirAccess.rename_absolute(whole + ".tmp", whole)
