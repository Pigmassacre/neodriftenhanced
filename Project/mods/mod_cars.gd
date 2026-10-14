extends RefCounted
## Cars changed by mods: a mod.cfg's `[car]` section changes one of the
## game's three cars (the player's, and the other cars of that make), each
## value a number of times the original's:
##
##     [car]
##     replaces = 1          ; which car: 0, 1 or 2, as the car choice has them
##     adds = false          ; true: a car of its own, after that one
##                           ; on the car choice
##     name = "Lancer Evo"   ; its name there
##     panel = "panel.png"   ; an added car's bar under it there (Mods.PANEL_SIZE)
##     top_speed = 1.1       ; on every surface and as the car wears down
##     acceleration = 1.2
##     braking = 1.0
##     drag = 1.0            ; how fast it slows down by itself
##     grip = 0.9            ; how well its travel follows where it points
##     turning = 1.1         ; how fast it turns
##
## Its looks are the mod's graphics (mods/mod_graphics.gd): the pictures of
## that car, saved with --dump-graphics and painted over.
##
## The tables changed are copied to the mod's part of the ROM (Mods.Extra)
## where other cars share them, and changed in place where they do not.

## The addresses of the tables a car is set up from (car.gd): by machine
## and car, its size, turn table and grip tables; by difficulty and car,
## its speeds, ground table and stages of damage.
const CAR_FIELDS := 0x23706
const SPEED_FIELDS := 0x2370A
const MACHINES := 3
## The board's setting: 16 levels.
const DIFFICULTIES := 16
const CARS := 3
## The speeds can go no higher: the game's tables by speed end there.
const FASTEST := 4080
## Surfaces of the ground: the grip tables and the ground table have one
## entry for each.
const SURFACES := 18
## A grip table: by speed in 256ths, four grips (no pedal, accelerator,
## brake, both).
const GRIP_ENTRIES := 16
## Edges triple the grip, which must still fit in a word.
const MOST_GRIP := 0xFFFF / 3
## The turn table: by speed in 16ths.
const TURN_ENTRIES := 256
## Words of the speed fields: top speed, lowest, on rough ground, the
## ground table's address, then five stages of damage (scrapes, top speed,
## on rough ground, unused).
const SPEED_WORDS := 0x19
const DAMAGE_STAGES := 5


static func adds_car(mod: Mods.Mod) -> bool:
	return mod.config.has_section("car") and bool(mod.config.get_value("car", "adds", false))


## The car it changes, or the car a car it adds is made from.
static func car_of(mod: Mods.Mod) -> int:
	return int(mod.config.get_value("car", "replaces", -1))


static func apply(machine: NeoGeoMachine, mod: Mods.Mod, extra: Mods.Extra) -> void:
	if not mod.config.has_section("car"):
		return
	var config := mod.config
	var car := car_of(mod)
	if car < 0 or car >= CARS:
		push_warning("Mod %s: [car] replaces must be 0, 1 or 2" % mod.id)
		return
	var top := float(config.get_value("car", "top_speed", 1.0))
	var ground := Vector3(float(config.get_value("car", "acceleration", 1.0)),
			float(config.get_value("car", "braking", 1.0)), float(config.get_value("car", "drag", 1.0)))
	var grip := float(config.get_value("car", "grip", 1.0))
	var turning := float(config.get_value("car", "turning", 1.0))

	var speeds_done := {}
	for difficulty in DIFFICULTIES:
		var fields := machine.r32(machine.r32(machine.r32(SPEED_FIELDS) + difficulty * 4) + car * 4)
		if speeds_done.has(fields) or Mods.rom_index(fields) < 0:
			continue
		speeds_done[fields] = true
		var words: Array[int] = []
		for index in SPEED_WORDS:
			words.append(machine.r16(fields + index * 2))
		if top != 1.0:
			words[0] = mini(roundi(words[0] * top), FASTEST)
			words[2] = mini(roundi(words[2] * top), FASTEST)
			for stage in DAMAGE_STAGES:
				words[6 + stage * 4] = mini(roundi(words[6 + stage * 4] * top), FASTEST)
				words[7 + stage * 4] = mini(roundi(words[7 + stage * 4] * top), FASTEST)
		if ground != Vector3.ONE:
			var table: int = (words[3] << 16) | words[4]
			var scaled := []
			for surface in SURFACES:
				for index in 4:
					var value := machine.r16(table + surface * 8 + index * 2)
					if index < 3:
						value = clampi(roundi(value * ground[index]), 0, 0x7FFF)
					scaled.append(value)
			var copy := extra.add_words(scaled)
			words[3] = copy >> 16
			words[4] = copy & 0xFFFF
		Mods.write_words(machine, fields, words)

	if grip == 1.0 and turning == 1.0:
		return
	var copied := {}
	for machine_kind in MACHINES:
		var fields := machine.r32(machine.r32(machine.r32(CAR_FIELDS) + machine_kind * 4) + car * 4)
		if turning != 1.0:
			var turns := machine.r32(fields + 4)
			if not copied.has(turns):
				var scaled := []
				for index in TURN_ENTRIES:
					scaled.append(clampi(roundi(machine.r16(turns + index * 2) * turning), 0, 0x7FFF))
				copied[turns] = extra.add_words(scaled)
			Mods.write_long(machine, fields + 4, copied[turns])
		if grip != 1.0:
			var tables := machine.r32(fields + 8)
			if not copied.has(tables):
				var list := []
				for surface in SURFACES:
					var table := machine.r32(tables + surface * 4)
					if not copied.has(table):
						var scaled := []
						for index in GRIP_ENTRIES * 4:
							scaled.append(clampi(roundi(machine.r16(table + index * 2) * grip), 0, MOST_GRIP))
						copied[table] = extra.add_words(scaled)
					list.append(copied[table] >> 16)
					list.append(copied[table] & 0xFFFF)
				copied[tables] = extra.add_words(list)
			Mods.write_long(machine, fields + 8, copied[tables])
