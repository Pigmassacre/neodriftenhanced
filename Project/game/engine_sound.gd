extends GameRoutines
## The sound of the car's engine. The engine has gears by speed; a change
## of gear, taking off and landing each ask for a note, the notes wait in
## a short queue, and each plays for a set time before the next.

const Car := preload("res://game/car.gd")

## The notes waiting: four words used as a ring, with the offsets of the
## next to play and the next free.
const NEXT_NOTE := 0x101684
const NEXT_FREE := 0x101686
const NOTES := 0x101688
## 0 on the ground, IN_THE_AIR, or JUST_LANDED for the one frame after.
const FLIGHT := 0x101690
const IN_THE_AIR := 1
const JUST_LANDED := 2
## Frames the note playing has left, the note ($FFFF for none), the gear,
## and for how many frames the gear has stayed.
const NOTE_FRAMES := 0x101692
const NOTE := 0x101694
const GEAR := 0x101696
const GEAR_FRAMES := 0x101698
const NOTE_IN_THE_AIR := 9

## Gear by speed (the low four bits of each word).
const GEAR_BY_SPEED := 0xFB78
## The notes of each gear, four words: staying in it, changing up to it,
## changing down to it.
const GEAR_NOTES := 0xFBB8
const CHANGED_UP := 2
const CHANGED_DOWN := 4
## For each note four words: the sound that starts it, the sound that ends
## it, and how many frames it plays.
const NOTE_SOUNDS := 0x26EE0
const REQUEST_SOUND := 0x15256


func routines() -> Dictionary:
	return {
		0xFA18: update,
		0xFA0C: fall_silent,
		0xFC0A: add_note,
		0xFC12: forget_notes,
		0xFC20: add_note,
		0xFC48: take_note,
		0xFBE0: end_note,
	}


func scratch() -> Dictionary:
	return {
		0xFA18: ["d0", "d1", "d2", "a0", "ccr"],
		0xFA0C: ["ccr"],
		0xFC0A: ["d1", "d2", "a0", "ccr"],
		0xFC12: ["ccr"],
		0xFC20: ["d1", "d2", "a0", "ccr"],
		0xFC48: ["d1", "a0", "ccr"],
		0xFBE0: ["d0", "a0", "ccr"],
	}


## $FA18: one frame of it, for the car in A6.
func update() -> void:
	var car := m.a6
	var airborne := u16(car + Car.AIRBORNE) == 1
	var was_airborne := u16(car + Car.AIRBORNE_BEFORE) == 1
	if airborne and not was_airborne:
		set16(FLIGHT, IN_THE_AIR)
		fall_silent()
		_add_note(NOTE_IN_THE_AIR)
	elif was_airborne and not airborne:
		set16(FLIGHT, JUST_LANDED)
		fall_silent()
	if u16(FLIGHT) != IN_THE_AIR:
		var speed := s16(car + Car.SPEED)
		var gear := 0 if speed < 0 else m.r16(GEAR_BY_SPEED + ((speed >> 7) & 0x1F) * 2) & 0xF
		var before := s16(GEAR)
		if u16(FLIGHT) == JUST_LANDED:
			set16(GEAR, gear)
			_add_note(m.r16(GEAR_NOTES + gear * 8))
			set16(FLIGHT, 0)
		elif gear != before:
			set16(GEAR, gear)
			set16(GEAR_FRAMES, 0)
			_add_note(m.r16(GEAR_NOTES + gear * 8 + (CHANGED_UP if gear > before else CHANGED_DOWN)))
		else:
			set16(GEAR, gear)
			set16(GEAR_FRAMES, u16(GEAR_FRAMES) + 1)
			if u16(GEAR_FRAMES) == 5 and gear == 1:
				_add_note(m.r16(GEAR_NOTES + 8))
	set16(NOTE_FRAMES, u16(NOTE_FRAMES) - 1)
	if s16(NOTE_FRAMES) >= 0:
		return
	set16(NOTE_FRAMES, u16(NOTE_FRAMES) + 1)
	var note := _take_note()
	if note == 0xFFFF:
		return
	_end_note(u16(NOTE))
	set16(NOTE, note)
	var sounds := NOTE_SOUNDS + wrap16(note << 3)
	set16(NOTE_FRAMES, m.r16(sounds + 4))
	_request_sound(m.r16(sounds))


## $FA0C
func fall_silent() -> void:
	forget_notes()
	set16(NOTE_FRAMES, 0)


## $FC12
func forget_notes() -> void:
	set16(NEXT_NOTE, 0)
	set16(NEXT_FREE, 0)


## $FC20, $FC0A: adds the note in D0 to those waiting, unless there are three.
func add_note() -> void:
	_add_note(m.d0 & 0xFFFF)


func _add_note(note: int) -> void:
	var free := u16(NEXT_FREE)
	var next := (free + 2) & 7
	if next != u16(NEXT_NOTE):
		set16(NOTES + free, note)
		set16(NEXT_FREE, next)


## $FC48: takes the next note waiting into D0, $FFFF when there is none.
func take_note() -> void:
	m.d0 = with_low16(m.d0, _take_note())


func _take_note() -> int:
	var next := u16(NEXT_NOTE)
	if next == u16(NEXT_FREE):
		return 0xFFFF
	set16(NEXT_NOTE, (next + 2) & 7)
	return u16(NOTES + next)


## $FBE0: ends the note in D0, if it is one.
func end_note() -> void:
	_end_note(m.d0 & 0xFFFF)


func _end_note(note: int) -> void:
	if note == 0xFFFF:
		return
	set16(NOTE, 0xFFFF)
	var sounds := NOTE_SOUNDS + wrap16(note << 3)
	set16(NOTE_FRAMES, m.r16(sounds + 4))
	_request_sound(m.r16(sounds + 2))


func _request_sound(sound: int) -> void:
	m.d0 = with_low16(m.d0, sound)
	m.call_routine(REQUEST_SOUND)
