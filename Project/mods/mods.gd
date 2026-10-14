class_name Mods
extends RefCounted
## Mods: changes to the game that players add, each a folder with a
## `mod.cfg` in it, in one of `folders()`. MODDING.md at the top of the
## repository is the guide to making them; this is what reads them.
##
## A mod may replace pictures (mods/mod_graphics.gd), change the program
## ROM's tables (the `[rom]` section here), and change a car or a course
## through sections of their own (mods/mod_cars.gd, mods/mod_courses.gd).
## Mods are applied in the order of their folders' names, so a later one
## wins where two change the same thing.

const FILE := "mod.cfg"

## More folders to look in (the command line's --mod-folder).
static var more_folders: Array[String] = []

const ModCars := preload("res://mods/mod_cars.gd")
const ModCourses := preload("res://mods/mod_courses.gd")


## One mod as found.
class Mod:
	## The folder's name, which is how the options remember it.
	var id := ""
	var path := ""
	var name := ""
	var author := ""
	var version := ""
	var description := ""
	var config := ConfigFile.new()

	## True if it changes how the game plays and not just how it looks or
	## sounds: best times made with it are kept apart.
	func changes_play() -> bool:
		for section in config.get_sections():
			if section in ["rom", "car", "course"] or section.begins_with("car.") or section.begins_with("course."):
				return true
		return false


## Where mods are looked for: `mods/` beside the game (in a copy run from
## the repository, at its top) and `mods/` in the user's folder for it.
static func folders() -> Array[String]:
	var beside := MachineLoader.repo_dir()
	if not OS.has_feature("editor") and OS.has_feature("template"):
		beside = OS.get_executable_path().get_base_dir()
	var found: Array[String] = [beside.path_join("mods"), ProjectSettings.globalize_path("user://mods")]
	found.append_array(more_folders)
	return found


## Every mod there is, in the order they are applied in. Of two with the
## same folder name the one beside the game is taken.
static func find_all() -> Array[Mod]:
	var found := {}
	for folder in folders():
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for id in DirAccess.get_directories_at(folder):
			var path := folder.path_join(id)
			if found.has(id) or not FileAccess.file_exists(path.path_join(FILE)):
				continue
			var mod := Mod.new()
			mod.id = id
			mod.path = path
			if mod.config.load(path.path_join(FILE)) != OK:
				push_warning("Mod %s: %s could not be read" % [id, FILE])
				continue
			mod.name = str(mod.config.get_value("mod", "name", id))
			mod.author = str(mod.config.get_value("mod", "author", ""))
			mod.version = str(mod.config.get_value("mod", "version", ""))
			mod.description = str(mod.config.get_value("mod", "description", ""))
			found[id] = mod
	var ids := found.keys()
	ids.sort()
	var mods: Array[Mod] = []
	for id: String in ids:
		mods.append(found[id])
	return mods


## The mods that are on: all but those the player has turned off.
static func enabled(turned_off: Array) -> Array[Mod]:
	var mods: Array[Mod] = []
	for mod in find_all():
		if not mod.id in turned_off:
			mods.append(mod)
	return mods


## Changes the machine's program ROM as the mods say: their own `[rom]`
## sections, their cars and their courses. `course_mod`, when not empty, is
## the id of the mod whose course is to be driven in place of the one it
## is made from (mods/mod_courses.gd).
static func apply_to_machine(machine: NeoGeoMachine, mods: Array[Mod], course_mod := "") -> void:
	var extra := ModCourses.Extra.new()
	for mod in mods:
		_patch_rom(machine, mod)
		ModCars.apply(machine, mod)
	for mod in mods:
		if mod.id == course_mod:
			ModCourses.apply(machine, mod, extra)
	machine.extra_rom = extra.bytes


## A mod's `[rom]` section: each key a bus address in hexadecimal, each
## value the bytes from there on as a string of hexadecimal digits, or the
## words from there on as a number or a list of numbers.
static func _patch_rom(machine: NeoGeoMachine, mod: Mod) -> void:
	if not mod.config.has_section("rom"):
		return
	for key in mod.config.get_section_keys("rom"):
		var address := key.trim_prefix("0x").trim_prefix("$").hex_to_int()
		var value: Variant = mod.config.get_value("rom", key)
		var bytes := PackedByteArray()
		if value is String:
			bytes = (value as String).replace(" ", "").hex_decode()
		elif value is int:
			bytes = _words([value])
		elif value is Array:
			bytes = _words(value)
		if bytes.is_empty() or not write_rom(machine, address, bytes):
			push_warning("Mod %s: [rom] %s could not be applied" % [mod.id, key])


static func _words(words: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	for word: Variant in words:
		bytes.append((int(word) >> 8) & 0xFF)
		bytes.append(int(word) & 0xFF)
	return bytes


## Writes `bytes` to the program ROM from bus address `address` on, as the
## 68000 sees them (big-endian). False if they do not all land in it.
static func write_rom(machine: NeoGeoMachine, address: int, bytes: PackedByteArray) -> bool:
	for offset in bytes.size():
		var at := rom_index(address + offset)
		if at < 0 or at >= machine.rom.size():
			return false
		machine.rom[at ^ 1] = bytes[offset]
	return true


## Where in NeoGeoMachine.rom the byte at bus address `address` is kept
## (before the swap of the bytes in a word), or -1 for none.
static func rom_index(address: int) -> int:
	if address >= 0 and address < 0x100000:
		return address
	if address >= 0x200000 and address < 0x300000:
		return address - 0x100000
	return -1


## Reads a word of the program ROM by bus address.
static func rom_word(machine: NeoGeoMachine, address: int) -> int:
	return machine.r16(address)
