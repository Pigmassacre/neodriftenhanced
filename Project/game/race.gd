extends GameRoutines
## A race, frame by frame: what is updated and in which order.

## The player's car (car.gd).
const PLAYER_CAR := 0x101508
## 1 when other cars are on the course.
const RIVALS_PRESENT := 0x101222

const UPDATE_CAR := 0xD956
const UPDATE_RIVALS := 0xC558
const SHOW_TIME_TAKEN := 0xFE0A
const SHOW_TIME_LEFT := 0xFECC
const SHOW_SPEED := 0x100D2
const LEAVE_SKID_MARKS := 0xF6EC
const RAISE_DUST := 0xF5DA
const RAISE_RIVALS_DUST := 0xD566
const ROUTINE_14760 := 0x14760
const SHOW_PROGRESS := 0x19F82
const UPDATE_COURSE_OBJECTS := 0x14160
const BUILD_SPRITES := 0x1229E
const SCROLL_GROUND := 0x13546


func routines() -> Dictionary:
	return {
		0xB844: frame,
		0xD6C8: update_rivals,
	}


func scratch() -> Dictionary:
	return {
		0xB844: ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "ccr"],
		0xD6C8: ["ccr"],
	}


## $B844: one frame of the race. D0 is 0 once the race is over.
func frame() -> void:
	m.a6 = PLAYER_CAR
	m.call_routine(UPDATE_CAR)
	update_rivals()
	var goes_on := low16(m.d0) != 0
	m.call_routine(SHOW_TIME_TAKEN)
	m.call_routine(SHOW_TIME_LEFT)
	m.call_routine(SHOW_SPEED)
	if goes_on:
		m.call_routine(LEAVE_SKID_MARKS)
		m.call_routine(RAISE_DUST)
		m.call_routine(RAISE_RIVALS_DUST)
		m.call_routine(ROUTINE_14760)
		m.call_routine(SHOW_PROGRESS)
		m.call_routine(UPDATE_COURSE_OBJECTS)
		m.call_routine(BUILD_SPRITES)
		m.call_routine(SCROLL_GROUND)
	m.d0 = with_low16(m.d0, 1 if goes_on else 0)


## $D6C8
func update_rivals() -> void:
	if u16(RIVALS_PRESENT) == 1:
		m.call_routine(UPDATE_RIVALS)
