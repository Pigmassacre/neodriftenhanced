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
## A call that an interrupt arrives in is left to the original, which just
## goes on, since hand-written code cannot be interrupted part way.
##
## The stack below the routine's return address is not compared: the original
## leaves return addresses and saved registers there that nothing reads.

const REGISTERS: Array[StringName] = [&"d0", &"d1", &"d2", &"d3", &"d4", &"d5", &"d6", &"d7",
		&"a0", &"a1", &"a2", &"a3", &"a4", &"a5", &"a6", &"a7"]
const FLAGS: Array[StringName] = [&"fn", &"fz", &"fv", &"fc", &"fx"]
const STATE: Array[StringName] = [&"vram_addr", &"vram_mod", &"sound_command", &"ipl", &"cyc",
		&"lspc_mode", &"timer_reload", &"palette_bank", &"timer_fire_cyc", &"irq1_pending",
		&"irq2_pending", &"recheck", &"event_cyc"]
## Of those, what must come out the same.
const COMPARED_STATE: Array[StringName] = [&"vram_addr", &"vram_mod", &"sound_command",
		&"lspc_mode", &"timer_reload", &"palette_bank"]
## And what depends on when things happened, taken from the original.
const TIMED_STATE: Array[StringName] = [&"cyc", &"timer_fire_cyc", &"irq1_pending", &"irq2_pending",
		&"recheck", &"event_cyc"]
const DEAD_STACK := 0x200
const MAX_BLOCKS := 2000000
const MAX_VARIED_BLOCKS := 100000
## Every how many calls of a routine with variations one of them is tried.
const VARY_EVERY := 4
const INTERRUPTED := -1
const FAILED := -2
const MAX_REPORTS := 5

var machine: NeoGeoMachine
## Per routine address: [name, calls, mismatches, calls an interrupt fell in,
## varied calls compared, varied calls the original could not run].
var results := {}
var frame := 0
var _in_hand_written := false
var _varying := false
var _stopped_at := 0
# Copies of video RAM and the palettes as they were when `video_writes` was
# `_video_copied`: they are large and seldom written, so states share them.
var _vram := PackedInt32Array()
var _palette := PackedInt32Array()
var _video_copied := -1


func _init(checked: NeoGeoMachine) -> void:
	machine = checked


func install() -> int:
	for group in Decomp.groups(machine):
		var table := group.routines()
		var scratch := group.scratch()
		var variations := group.variations()
		for address: int in table:
			_check(address, table[address], scratch.get(address, []), variations.get(address, []))
	return results.size()


func report() -> bool:
	var good := true
	for address: int in results:
		var entry: Array = results[address]
		if entry[2] > 0:
			good = false
		print("routine %06X %s: %d calls, %d differ%s%s" % [address, entry[0], entry[1], entry[2],
				", %d left to the original (interrupted)" % entry[3] if entry[3] > 0 else "",
				", %d varied (%d more not run)" % [entry[4], entry[5]] if entry[4] + entry[5] > 0 else ""])
	return good


func _check(address: int, routine: Callable, scratch: Array, varied: Array) -> void:
	var original := machine.block(address)
	var entry := [routine.get_method(), 0, 0, 0, 0, 0]
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
		if _in_hand_written:
			# Called by a hand-written routine that is itself being checked:
			# this one was checked when the original made the same call.
			routine.call()
			var back_to := machine.r32(machine.a7) & 0xFFFFFF
			machine.a7 = (machine.a7 + 4) & 0xFFFFFFFF
			return back_to
		entry[1] += 1
		var before := _save()
		var stack := machine.a7
		var due := machine.event_cyc
		if not varied.is_empty() and not _varying and entry[1] % VARY_EVERY == 0:
			_vary(address, entry, routine, original, compared, varied[(entry[1] / VARY_EVERY) % varied.size()], before)
		var pc := _run(original, stack, due, MAX_BLOCKS)
		if pc == FAILED:
			if not _varying:
				push_error("routine %06X did not return (at %06X)" % [address, _stopped_at])
			machine.halted = true
			return _stopped_at
		if pc == INTERRUPTED or _interrupt_due(due):
			# An interrupt arrives inside the routine. Hand-written code
			# cannot be interrupted, so this call is left to the original:
			# it simply goes on from here, block by block as usual, and the
			# routines it has called and goes on to call are still checked.
			# (The original may even be waiting for the interrupt.)
			entry[3] += 1
			return _stopped_at if pc == INTERRUPTED else pc
		var wanted := _save()
		# what the original logged, with the times it logged them at
		var sound_times := machine.sound_log_times.slice(before[&"sound"])
		var moved_y := machine.midframe_y.slice(before[&"midframe_y"])
		var moved_text := machine.midframe_text.slice(before[&"midframe_text"])
		_restore(before)
		_in_hand_written = true
		routine.call()
		_in_hand_written = false
		machine.a7 = (machine.a7 + 4) & 0xFFFFFFFF
		var difference := _compare(wanted, compared, stack)
		if difference != "":
			entry[2] += 1
			if entry[2] <= MAX_REPORTS:
				print("routine %06X %s, frame %d, call %d%s: %s\n  entered with %s" % [
						address, entry[0], frame, entry[1], " (in a varied call)" if _varying else "",
						difference, _registers(before)])
		for name in TIMED_STATE:
			machine.set(name, wanted[name])
		if difference == "":
			machine.sound_log_times.resize(before[&"sound"])
			machine.sound_log_times.append_array(sound_times)
		machine.midframe_y.resize(before[&"midframe_y"])
		machine.midframe_y.append_array(moved_y)
		machine.midframe_text.resize(before[&"midframe_text"])
		machine.midframe_text.append_array(moved_text)
		return pc)


## Runs the original from its first block until it returns to its caller.
## Gives the address it returned to, INTERRUPTED once an interrupt is due,
## or FAILED where it ran into code that is not there or never returned.
func _run(original: Callable, stack: int, due: int, most_blocks: int) -> int:
	var back := machine.r32(stack) & 0xFFFFFF
	var pc: int = original.call()
	var blocks := 0
	while not (pc == back and machine.a7 == ((stack + 4) & 0xFFFFFFFF)):
		_stopped_at = pc
		if _interrupt_due(due) and not machine.halted:
			return INTERRUPTED
		var code: Variant = machine._table.get(pc)
		blocks += 1
		if code == null or machine.halted or blocks > most_blocks:
			return FAILED
		pc = code.call()
	return pc


## Would the machine take an interrupt before the next block?
func _interrupt_due(due: int) -> bool:
	return machine.cyc >= due or (machine.recheck and (machine.irq1_pending or machine.irq2_pending))


## Compares the two once more from a state the session did not reach:
## `change` alters the state the routine is entered with, to take it down
## branches no recorded session takes. Nothing of it is kept.
func _vary(routine_address: int, entry: Array, routine: Callable, original: Callable, compared: Dictionary,
		change: Callable, before: Dictionary) -> void:
	_varying = true
	change.call()
	var start := _save()
	var stack := machine.a7
	var pc := _run(original, stack, machine.event_cyc, MAX_VARIED_BLOCKS)
	if pc < 0 or _interrupt_due(start[&"event_cyc"]):
		# the original cannot cope with this state, or an interrupt is due
		entry[5] += 1
		machine.halted = false
		machine.missing_block = -1
	else:
		entry[4] += 1
		var wanted := _save()
		_restore(start)
		_in_hand_written = true
		routine.call()
		_in_hand_written = false
		machine.a7 = (machine.a7 + 4) & 0xFFFFFFFF
		var difference := _compare(wanted, compared, stack)
		if difference != "":
			entry[2] += 1
			if entry[2] <= MAX_REPORTS:
				print("routine %06X %s, frame %d, call %d varied: %s\n  entered with %s" % [
						routine_address, entry[0], frame, entry[1], difference, _registers(start)])
	_restore(before)
	_varying = false


func _save() -> Dictionary:
	if machine.video_writes != _video_copied:
		_vram = machine.vram.duplicate()
		_palette = machine.palette.duplicate()
		_video_copied = machine.video_writes
	var state := {
		&"ram": machine.ram.duplicate(), &"vram": _vram, &"palette": _palette,
		&"video": machine.video_writes, &"sound": machine.sound_log.size(),
		&"midframe_y": machine.midframe_y.size(), &"midframe_text": machine.midframe_text.size(),
	}
	for name in REGISTERS + FLAGS + STATE:
		state[name] = machine.get(name)
	return state


func _restore(state: Dictionary) -> void:
	machine.ram = state[&"ram"].duplicate()
	if machine.video_writes != state[&"video"]:
		machine.vram = state[&"vram"].duplicate()
		machine.palette = state[&"palette"].duplicate()
		# a count no earlier state has, standing for these contents
		machine.video_writes += 1
		_vram = state[&"vram"]
		_palette = state[&"palette"]
		_video_copied = machine.video_writes
		state[&"video"] = machine.video_writes
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
	for name in COMPARED_STATE:
		if machine.get(name) != wanted[name]:
			found.append("%s is %X, should be %X" % [name, machine.get(name), wanted[name]])
	if machine.sound_log.size() != wanted[&"sound"]:
		found.append("sound commands sent differ")
	var ram: PackedByteArray = wanted[&"ram"]
	var top := (stack & 0xFFFF) + 4
	var dead := maxi(top - DEAD_STACK, 0)
	if machine.ram.slice(0, dead) != ram.slice(0, dead) or machine.ram.slice(top) != ram.slice(top):
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
	if machine.video_writes != wanted[&"video"] and machine.vram != vram:
		for index in vram.size():
			if machine.vram[index] != vram[index]:
				found.append("video RAM %04X is %04X, should be %04X" % [index, machine.vram[index], vram[index]])
				break
	if machine.video_writes != wanted[&"video"] and machine.palette != wanted[&"palette"]:
		found.append("palettes differ")
	return ", ".join(found)


func _registers(state: Dictionary) -> String:
	var text := PackedStringArray()
	for name in REGISTERS:
		text.append("%s=%X" % [name, state[name]])
	return " ".join(text)
