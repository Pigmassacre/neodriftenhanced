extends GameRoutines
## The joystick as menus read it: a direction held counts once, and again
## and again after a while.

const PLAYER_1 := 0x10FD96
const PLAYER_2 := 0x10FD9C
## What of them was not held a frame ago.
const PLAYER_1_PRESSED := 0x10FD97
const PLAYER_2_PRESSED := 0x10FD9D
## Not 0 when the second player's side plays.
const SECOND_PLAYER := 0x1011FC
## Frames until a held direction counts again, the joystick a frame ago,
## and how long to wait for the first repeat and for each after it.
const FRAMES_TO_REPEAT := 0x1016FA
const BEFORE := 0x1016FB
const UNUSED := 0x1016FC
const FIRST_WAIT := 0x1016FD
const REPEAT_WAIT := 0x1016FE
## The same for each direction on its own: frames until it counts again,
## and the two waits.
const EACH_FRAMES_TO_REPEAT := 0x1016DA
const EACH_FIRST_WAIT := 0x1016DE
const EACH_REPEAT_WAIT := 0x1016E0
const DIRECTIONS := 0x0F
const UP := 0x01
const DOWN := 0x02
const LEFT := 0x04
const RIGHT := 0x08
const BUTTON_A := 0x10
const BUTTON_B := 0x20
const BUTTON_C := 0x40
const BUTTON_D := 0x80


func routines() -> Dictionary:
	return {
		0x11AC6: set_repeat_from_registers,
		0x11AE0: read_into_register,
		0x10EF4: func() -> void: set_each_repeat(m.d0 & 0xFF, m.d1 & 0xFF),
		0x10F18: func() -> void: m.d0 = with_low16(m.d0, read_each()),
		0x10E10: func() -> void: _into_register(held(low16(m.d0), BUTTON_A)),
		0x10E36: func() -> void: _into_register(pressed(low16(m.d0), BUTTON_A)),
		0x10E5C: func() -> void: _into_register(held(low16(m.d0), BUTTON_B)),
		0x10E82: func() -> void: _into_register(pressed(low16(m.d0), BUTTON_B)),
	}


func scratch() -> Dictionary:
	return {0x10EF4: ["ccr"], 0x10F18: ["ccr"], 0x11AC6: ["ccr"], 0x11AE0: ["ccr"], 0x10E10: ["ccr"], 0x10E36: ["ccr"], 0x10E5C: ["ccr"],
			0x10E82: ["ccr"]}


## $11AC6: a held direction repeats after D0 frames and then every D2.
func set_repeat_from_registers() -> void:
	set_repeat(m.d0 & 0xFF, m.d2 & 0xFF)


func set_repeat(first_wait: int, repeat_wait: int) -> void:
	set8(FRAMES_TO_REPEAT, 0)
	set8(BEFORE, 0)
	set8(UNUSED, 0)
	set8(FIRST_WAIT, first_wait)
	set8(REPEAT_WAIT, repeat_wait)


## $11AE0: the joystick in the low byte of D0.
func read_into_register() -> void:
	m.d0 = (m.d0 & 0xFFFFFF00) | read()


## The buttons as they are, and the directions only when they count.
func read() -> int:
	var now := u8(PLAYER_1 if u16(SECOND_PLAYER) == 0 else PLAYER_2)
	var frames := s8(FRAMES_TO_REPEAT)
	var before := u8(BEFORE)
	set8(BEFORE, now)
	var counts := true
	if now & DIRECTIONS != before & DIRECTIONS:
		frames = wrap8(u8(FIRST_WAIT) + u8(REPEAT_WAIT))
	else:
		frames = wrap8(frames - 1)
		var repeat_wait := s8(REPEAT_WAIT)
		if frames > repeat_wait or (frames != repeat_wait and frames > 0):
			counts = false
		elif frames != repeat_wait:
			frames = repeat_wait
	set8(FRAMES_TO_REPEAT, frames)
	return now if counts else now & ~DIRECTIONS


## $10E10 and $10E5C: is a button of `player` (0 or not) held down?
func held(player: int, button: int) -> bool:
	return u8(PLAYER_1 if player == 0 else PLAYER_2) & button != 0


## $10E36 and $10E82: was it pressed on this frame?
func pressed(player: int, button: int) -> bool:
	return u8(PLAYER_1_PRESSED if player == 0 else PLAYER_2_PRESSED) & button != 0


func _into_register(yes: bool) -> void:
	m.d0 = with_low16(m.d0, 1 if yes else 0)


## $10EF4: for `read_each`, a held direction repeats after `first_wait`
## frames and then every `repeat_wait`.
func set_each_repeat(first_wait: int, repeat_wait: int) -> void:
	set8(EACH_FIRST_WAIT, first_wait)
	set8(EACH_REPEAT_WAIT, repeat_wait)
	for direction in 4:
		set8(EACH_FRAMES_TO_REPEAT + direction, first_wait)


## $10F18: the directions that count on this frame, each repeating on its
## own while it is held.
func read_each() -> int:
	var second := u16(SECOND_PLAYER) == 1
	var now := u8(PLAYER_2 if second else PLAYER_1)
	var pressed_now := u8(PLAYER_2_PRESSED if second else PLAYER_1_PRESSED)
	var counting := 0
	for direction in 4:
		var bit := 1 << direction
		var frames := EACH_FRAMES_TO_REPEAT + direction
		if pressed_now & bit:
			set8(frames, u8(EACH_FIRST_WAIT))
			counting |= bit
		elif now & bit:
			set8(frames, u8(frames) - 1)
			if u8(frames) == 0:
				set8(frames, u8(EACH_REPEAT_WAIT))
				counting |= bit
	return counting
