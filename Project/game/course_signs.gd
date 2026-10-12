extends GameRoutines
## Signs that come up on screen during a race: the one for a checkpoint
## reached, and those the course asks for where the car drives into a
## marked part of it (the course has a map of sign numbers, one for each
## 256 by 256 pixels).

const Sprite := preload("res://game/sprite_object.gd")
const RaceClock := preload("res://game/race_clock.gd")

## Not 0 while no signs are shown.
const PAUSED := 0x10329A
## The checkpoint sign's sprite object.
const CHECKPOINT_SIGN := 0x10329C
## The map: its width and height in cells, and where its cells are.
const MAP_COLUMNS := 0x10328C
const MAP_ROWS := 0x10328E
const MAP := 0x103290
## Where the car is (set by car.gd).
const CAR_X := 0x103294
const CAR_Y := 0x103296
## The sign number of the last marked cell the car was in.
const LAST_SIGN := 0x103298
## The sign showing: the routine that plays it each frame (0 for none)
## and the one that takes it away. The routines keep more after these.
const SHOWING := 0x10324C
const SHOWING_END := 0x04
## What shows a sign: routines to start it (D0 is 0 after if it could
## not), to take it away and to play it, all with SHOWING in A1.
const SIGN_ROUTINES := 0x2A336


func routines() -> Dictionary:
	return {
		0x14760: update,
		0x14700: start,
		0x14730: end,
	}


func scratch() -> Dictionary:
	return {0x14760: ["a0", "ccr"], 0x14700: ["ccr"], 0x14730: ["ccr"]}


## $14760: a frame of the signs.
func update() -> void:
	var saved := [m.d0, m.d2, m.a1, m.a3]
	if u16(PAUSED) == 0:
		var frames := u16(RaceClock.CHECKPOINT_SIGN_FRAMES)
		if frames != 0:
			set16(RaceClock.CHECKPOINT_SIGN_FRAMES, frames - 1)
		m.a0 = u32(CHECKPOINT_SIGN)
		Sprite.show(m, m.a0, frames != 0)
		var columns := u16(MAP_COLUMNS)
		var cell := (u16(CAR_Y) >> 8) % u16(MAP_ROWS) * columns + (u16(CAR_X) >> 8) % columns
		var sign := m.r8(u32(MAP) + wrap16(cell))
		if sign != 0:
			var last := u8(LAST_SIGN)
			set8(LAST_SIGN, sign)
			if sign != last:
				m.a3 = SIGN_ROUTINES
				m.d0 = with_low16(m.d0, sign)
				start()
	m.a1 = SHOWING
	if u32(SHOWING) != 0:
		m.a3 = u32(SHOWING)
		m.call_routine(m.a3)
	m.d0 = saved[0]; m.d2 = saved[1]; m.a1 = saved[2]; m.a3 = saved[3]


## $14700: shows sign D0 with the routines at A3, in place of any other.
func start() -> void:
	var saved := [m.d0, m.a1, m.a3]
	var sign_routines := m.a3
	end()
	m.a1 = SHOWING
	set32(SHOWING, m.r32(sign_routines + 8))
	set32(SHOWING + SHOWING_END, m.r32(sign_routines + 4))
	m.a3 = m.r32(sign_routines)
	m.call_routine(m.a3)
	if low16(m.d0) == 0:
		set32(SHOWING, 0)
	m.d0 = saved[0]; m.a1 = saved[1]; m.a3 = saved[2]


## $14730: takes away the sign that is showing.
func end() -> void:
	if u32(SHOWING) == 0:
		return
	var saved := [m.a1, m.a3]
	m.a1 = SHOWING
	m.a3 = u32(SHOWING + SHOWING_END)
	m.call_routine(m.a3)
	set32(SHOWING, 0)
	m.a1 = saved[0]; m.a3 = saved[1]
