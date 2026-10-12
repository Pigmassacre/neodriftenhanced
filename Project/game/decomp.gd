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
]


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


## Gives the game more room than the original's tables have (see
## NeoGeoMachine.more_room). Call after `install`, before the game runs.
static func make_room(machine: NeoGeoMachine) -> void:
	machine.more_room = true
	var made: Array = machine.get_meta(&"hand_written")
	for group: GameRoutines in made:
		var hooks := group.room_hooks()
		for address: int in hooks:
			machine.hook_block(address, hooks[address])
