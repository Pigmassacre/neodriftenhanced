extends GameRoutines
## The races the attract mode shows: a course starts as in a game, and a
## recording drives the car for twenty seconds.

const STATE := 0x1035AC
enum {SET_UP_START, START, SET_UP_HUD, DRIVING}
const FRAMES_LEFT := 0x1035AE
const FRAMES_SHOWN := 1200
const CAR := 0x101508
const SET_UP_RACE_START := 0xB978
const RACE_START := 0xB98C
const REQUEST_SOUND := 0x15256
const SOUND_06 := 0x06
const SOUND_09 := 0x09
## What draws the HUD at first, and what a frame of the race calls.
const SET_UP_HUD_ROUTINES: Array[int] = [0xFD74, 0xFDB8, 0xFE60, 0x100BE]
const FRAME_ROUTINES: Array[int] = [0xD956, 0xFE0A, 0xFECC, 0x100D2, 0xF6EC, 0xF5DA, 0x14760, 0x19F82, 0x14160,
		0x1229E, 0x13546]


func routines() -> Dictionary:
	return {
		0x1C77A: set_up,
		0x1C788: update,
		0x1C7AA: set_up_start,
		0x1C7BE: start,
		0x1C7D8: set_up_hud,
		0x1C806: drive,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "ccr"]
	return {0x1C77A: ["ccr"], 0x1C788: free, 0x1C7AA: free, 0x1C7BE: free, 0x1C7D8: free, 0x1C806: free}


## $1C77A
func set_up() -> void:
	set16(STATE, SET_UP_START)
	m.d0 = with_low16(m.d0, 0)


## $1C788: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		SET_UP_START: set_up_start()
		START: start()
		SET_UP_HUD: set_up_hud()
		DRIVING: drive()


## $1C7AA
func set_up_start() -> void:
	m.call_routine(SET_UP_RACE_START)
	set16(STATE, START)
	m.d0 = with_low16(m.d0, 1)


## $1C7BE
func start() -> void:
	m.call_routine(RACE_START)
	if low16(m.d0) == 0:
		set16(STATE, SET_UP_HUD)
	m.d0 = with_low16(m.d0, 1)


## $1C7D8
func set_up_hud() -> void:
	set16(FRAMES_LEFT, FRAMES_SHOWN)
	for routine in SET_UP_HUD_ROUTINES:
		m.call_routine(routine)
	set16(STATE, DRIVING)
	m.d0 = with_low16(m.d0, 1)


## $1C806
func drive() -> void:
	set16(FRAMES_LEFT, u16(FRAMES_LEFT) - 1)
	if s16(FRAMES_LEFT) < 0:
		for sound: int in [SOUND_06, SOUND_09]:
			m.d0 = with_low16(m.d0, sound)
			m.call_routine(REQUEST_SOUND)
		m.d0 = with_low16(m.d0, 0)
		return
	m.a6 = CAR
	for routine in FRAME_ROUTINES:
		m.call_routine(routine)
	m.d0 = with_low16(m.d0, 1)
