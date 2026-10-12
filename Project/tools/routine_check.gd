class_name RoutineCheck
extends RefCounted
## Checks hand-written routines against their translated originals while a
## session replays: every call runs the original first, then the hand-written
## routine from the same state, and the two outcomes are compared (work RAM,
## video RAM, palettes, sound commands and the registers the routine does not
## declare as scratch). The run then continues from the hand-written
## routine's outcome, but at the time the original took: hand-written code
## takes no CPU time, and where the game's work for a frame does not fit in
## the frame that changes what happens. So the run as a whole can still be
## compared with MAME, and shows up a caller that reads a scratch register.
##
## The stack below the routine's return address is not compared: the original
## leaves return addresses and saved registers there that nothing reads.

const REGISTERS: Array[StringName] = [&"d0", &"d1", &"d2", &"d3", &"d4", &"d5", &"d6", &"d7",
		&"a0", &"a1", &"a2", &"a3", &"a4", &"a5", &"a6", &"a7"]
const FLAGS: Array[StringName] = [&"fn", &"fz", &"fv", &"fc", &"fx"]
const STATE: Array[StringName] = [&"vram_addr", &"vram_mod", &"sound_command", &"ipl", &"cyc"]
const DEAD_STACK := 0x200
const MAX_BLOCKS := 2000000
const MAX_REPORTS := 5

var machine: NeoGeoMachine
## Per routine address: [name, calls, mismatches].
var results := {}
var frame := 0


func _init(checked: NeoGeoMachine) -> void:
	machine = checked


func install() -> int:
	for group in Decomp.groups(machine):
		var table := group.routines()
		var scratch := group.scratch()
		for address: int in table:
			_check(address, table[address], scratch.get(address, []))
	return results.size()


func report() -> bool:
	var good := true
	for address: int in results:
		var entry: Array = results[address]
		if entry[2] > 0:
			good = false
		print("routine %06X %s: %d calls, %d differ" % [address, entry[0], entry[1], entry[2]])
	return good


func _check(address: int, routine: Callable, scratch: Array) -> void:
	var original := machine.block(address)
	var entry := [routine.get_method(), 0, 0]
	results[address] = entry
	# what to compare of each register: all of it, its low word, or nothing
	var compared := {}
	for register in REGISTERS:
		if scratch.has(String(register) + ".high"):
			compared[register] = 0xFFFF
		elif not scratch.has(String(register)):
			compared[register] = 0xFFFFFFFF
	if not scratch.has("ccr"):
		for flag in FLAGS:
			compared[flag] = 1
	machine.set_block(address, func() -> int:
		entry[1] += 1
		var before := _save()
		var stack := machine.a7
		var back := machine.r32(stack) & 0xFFFFFF
		var pc: int = original.call()
		var blocks := 0
		while not (pc == back and machine.a7 == ((stack + 4) & 0xFFFFFFFF)):
			var code: Variant = machine._table.get(pc)
			blocks += 1
			if code == null or machine.halted or blocks > MAX_BLOCKS:
				push_error("routine %06X did not return (at %06X)" % [address, pc])
				machine.halted = true
				return pc
			pc = code.call()
		var wanted := _save()
		_restore(before)
		routine.call()
		machine.a7 = (machine.a7 + 4) & 0xFFFFFFFF
		var difference := _compare(wanted, compared, stack)
		if difference != "":
			entry[2] += 1
			if entry[2] <= MAX_REPORTS:
				print("routine %06X %s, frame %d, call %d: %s\n  entered with %s" % [
						address, entry[0], frame, entry[1], difference, _registers(before)])
		machine.cyc = wanted[&"cyc"]
		return pc)


func _save() -> Dictionary:
	var state := {
		&"ram": machine.ram.duplicate(), &"vram": machine.vram.duplicate(),
		&"palette": machine.palette.duplicate(), &"sound": machine.sound_log.size(),
		&"midframe_y": machine.midframe_y.size(), &"midframe_text": machine.midframe_text.size(),
	}
	for name in REGISTERS + FLAGS + STATE:
		state[name] = machine.get(name)
	return state


func _restore(state: Dictionary) -> void:
	machine.ram = state[&"ram"].duplicate()
	machine.vram = state[&"vram"].duplicate()
	machine.palette = state[&"palette"].duplicate()
	machine.sound_log.resize(state[&"sound"])
	machine.sound_log_times.resize(state[&"sound"])
	machine.midframe_y.resize(state[&"midframe_y"])
	machine.midframe_text.resize(state[&"midframe_text"])
	for name in REGISTERS + FLAGS + STATE:
		machine.set(name, state[name])


func _compare(wanted: Dictionary, compared: Dictionary, stack: int) -> String:
	var found := PackedStringArray()
	for name: StringName in compared:
		if (machine.get(name) ^ wanted[name]) & compared[name]:
			found.append("%s is %X, should be %X" % [name, machine.get(name), wanted[name]])
	for name: StringName in [&"vram_addr", &"vram_mod", &"sound_command"]:
		if machine.get(name) != wanted[name]:
			found.append("%s is %X, should be %X" % [name, machine.get(name), wanted[name]])
	if machine.sound_log.size() != wanted[&"sound"]:
		found.append("sound commands sent differ")
	var ram: PackedByteArray = wanted[&"ram"]
	if machine.ram != ram:
		var top := (stack & 0xFFFF) + 4
		var shown := 0
		for offset in range(0, 0x10000, 2):
			if offset >= top - DEAD_STACK and offset < top:
				continue
			if machine.ram.decode_u16(offset) != ram.decode_u16(offset):
				shown += 1
				if shown <= 4:
					found.append("RAM %06X is %04X, should be %04X" % [0x100000 + offset,
							machine.ram.decode_u16(offset), ram.decode_u16(offset)])
		if shown > 4:
			found.append("and %d more words" % (shown - 4))
	var vram: PackedInt32Array = wanted[&"vram"]
	if machine.vram != vram:
		for index in vram.size():
			if machine.vram[index] != vram[index]:
				found.append("video RAM %04X is %04X, should be %04X" % [index, machine.vram[index], vram[index]])
				break
	if machine.palette != wanted[&"palette"]:
		found.append("palettes differ")
	return ", ".join(found)


func _registers(state: Dictionary) -> String:
	var text := PackedStringArray()
	for name in REGISTERS:
		text.append("%s=%X" % [name, state[name]])
	return " ".join(text)
