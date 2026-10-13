class_name Decomp
extends RefCounted
## The hand-written part of the game: installs every routine of the scripts
## listed here over its translated original.

const GROUPS: Array[GDScript] = [
	preload("res://game/car.gd"),
	preload("res://game/sprite_object.gd"),
	preload("res://game/random.gd"),
	preload("res://game/course_objects.gd"),
	preload("res://game/sound_requests.gd"),
	preload("res://game/ground.gd"),
	preload("res://game/race_clock.gd"),
	preload("res://game/engine_sound.gd"),
	preload("res://game/race.gd"),
	preload("res://game/angles.gd"),
	preload("res://game/rival.gd"),
	preload("res://game/text.gd"),
	preload("res://game/hud.gd"),
	preload("res://game/course_signs.gd"),
	preload("res://game/game_flow.gd"),
	preload("res://game/scenery.gd"),
	preload("res://game/palettes.gd"),
	preload("res://game/joystick.gd"),
	preload("res://game/car_choice.gd"),
	preload("res://game/credits_line.gd"),
	preload("res://game/wipe.gd"),
	preload("res://game/race_start.gd"),
	preload("res://game/race_finish.gd"),
	preload("res://game/continue_screen.gd"),
	preload("res://game/ranking_screens.gd"),
	preload("res://game/demo_race.gd"),
	preload("res://game/heap.gd"),
	preload("res://game/game_over_screen.gd"),
	preload("res://game/course_introduction.gd"),
	preload("res://game/congratulations.gd"),
	preload("res://game/name_entry.gd"),
	preload("res://game/attract.gd"),
	preload("res://game/car_showcase.gd"),
	preload("res://game/best_times_screen.gd"),
	preload("res://game/how_to_play.gd"),
	preload("res://game/best_times.gd"),
	preload("res://game/title_screen.gd"),
	preload("res://game/closing_picture.gd"),
	preload("res://game/memory_card.gd"),
	preload("res://game/start_prompt.gd"),
	preload("res://game/system.gd"),
	preload("res://game/main_loop.gd"),
]
## What a machine without the translated program needs besides.
const NATIVE_GROUPS: Array[GDScript] = [
	preload("res://game/native_drawing.gd"),
]
const TopOfGame := preload("res://game/main_loop.gd")
const Board := preload("res://game/system.gd")
const BestTimes := preload("res://game/best_times.gd")


## All groups, for `machine`, which keeps them alive from then on.
static func groups(machine: NeoGeoMachine) -> Array[GameRoutines]:
	var made: Array[GameRoutines] = []
	for script in GROUPS:
		made.append(script.new(machine))
	machine.set_meta(&"hand_written", made)
	return made


## Returns how many routines were replaced. `only` limits it to those
## addresses, for finding which routine causes a difference.
static func install(machine: NeoGeoMachine, only: Array[int] = []) -> int:
	var count := 0
	for group in groups(machine):
		var table := group.routines()
		for address: int in table:
			if not only.is_empty() and not only.has(address):
				continue
			machine.replace_routine(address, table[address])
			count += 1
	return count


## Makes `machine`, which has no translated program, run the hand-written
## game alone.
static func install_native(machine: NeoGeoMachine) -> void:
	var made := groups(machine)
	for script in NATIVE_GROUPS:
		made.append(script.new(machine))
	machine.set_meta(&"hand_written", made)
	for group in made:
		var table := group.routines()
		for address: int in table:
			machine.replace_routine(address, table[address])
		if group.get_script() == TopOfGame:
			machine.native = group.frame


## Sets a machine made by `install_native` up as a board just switched on:
## the system's settings, and the best times in `kept` (see `kept_times`)
## or, without them, the ones the game starts out with.
static func power_on(machine: NeoGeoMachine, kept := PackedByteArray()) -> void:
	_group(machine, Board).power_on()
	var times: BestTimes = _group(machine, BestTimes)
	if not times.restore(kept):
		times.first_run()


## What the board keeps of the game while it is off, for `power_on`.
static func kept_times(machine: NeoGeoMachine) -> PackedByteArray:
	return _group(machine, BestTimes).kept()


static func _group(machine: NeoGeoMachine, script: GDScript) -> GameRoutines:
	for group: GameRoutines in machine.get_meta(&"hand_written"):
		if group.get_script() == script:
			return group
	return null


## Gives the game more room than the original's tables have (see
## NeoGeoMachine.more_room). Call after `install`, before the game runs.
static func make_room(machine: NeoGeoMachine) -> void:
	machine.more_room = true
	var made: Array = machine.get_meta(&"hand_written")
	for group: GameRoutines in made:
		var hooks := group.room_hooks()
		for address: int in hooks:
			if not machine.native.is_valid():
				machine.hook_block(address, hooks[address])
