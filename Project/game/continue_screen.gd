extends GameRoutines
## The screen after the time has run out on an arcade board: a count from
## 9 down, during which a credit and the start button go on with the game.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const CreditsLine := preload("res://game/credits_line.gd")

## The sprite objects of the digit and of the question.
const DIGIT_SPRITE := 0x1032C4
const QUESTION_SPRITE := 0x1032C8
## The number shown, frames left of it, and a word nothing reads.
const NUMBER := 0x1032CC
const FRAMES := 0x1032CE
const FIELD_1032D0 := 0x1032D0
## Frames left of the screen once the game goes on, and 0 once it does.
const FRAMES_AFTER := 0x1032D2
const COUNTING := 0x1032D4
## Set by the main loop: a coin has come in, and the game goes on.
const COIN_CAME := 0x100420
const GOES_ON := 0x10041A
## $FFFF when the count ran out, 0 when the game goes on.
const CONTINUE_DECLINED := 0x10120C
const FIRST_NUMBER := 9
const FRAMES_A_NUMBER := 60
const FRAMES_AFTER_CHOICE := 40
## The pictures: the ten digits, the last digit again, the question.
const PICTURES := 0x1564E
const QUESTION_PICTURE := 10
## By frame left, how wide the digit is drawn: it turns round.
const WIDTHS := 0x154E4
const DIGIT_MIDDLE := 0xA0
const DIGIT_Y := 0x60
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 5
const COLOURS := 0x1555E
const SOUND_TICK := 0xCA
const SOUND_GOES_ON := 0x186E
## What is said at 3, 2, 1 and 0.
const LAST_NUMBER_SOUNDS := 0x154DC
const CLEAR_HARDWARE_SPRITES := 0xC004C8
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x15282: set_up,
		0x15354: update,
	}


func scratch() -> Dictionary:
	return {0x15282: ["d1", "a3", "ccr"], 0x15354: ["a3", "ccr"]}


## $15282
func set_up() -> void:
	var saved := [m.d2, m.a0, m.a1, m.a2]
	# the system ROM's routine that clears the hardware's sprites
	m.call_routine(CLEAR_HARDWARE_SPRITES)
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, 0x100)
	var digit := Sprite.take_record(m)
	set32(DIGIT_SPRITE, digit)
	var question := Sprite.take_record(m)
	set32(QUESTION_SPRITE, question)
	Sprite.place(m, question, 0x30, 0x30)
	Sprite.place(m, digit, 0x80, DIGIT_Y)
	Sprite.picture(m, digit, m.r32(PICTURES + FIRST_NUMBER * 4))
	Sprite.picture(m, question, m.r32(PICTURES + QUESTION_PICTURE * 4))
	set16(NUMBER, FIRST_NUMBER)
	set16(FRAMES, FRAMES_A_NUMBER)
	set16(FIELD_1032D0, 0x100)
	set16(GOES_ON, 0)
	set16(FRAMES_AFTER, FRAMES_AFTER_CHOICE)
	set16(COUNTING, 0xFFFF)
	(sibling(CreditsLine) as CreditsLine).show()
	m.d2 = saved[0]; m.a0 = saved[1]; m.a1 = saved[2]; m.a2 = saved[3]
	m.d1 = with_low16(m.d1, PALETTE_COUNT)
	m.a3 = m.r32(PICTURES + QUESTION_PICTURE * 4)
	m.d0 = with_low16(m.d0, 0)


## $15354: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	var saved := [m.d2, m.a0, m.a1]
	var going_on := _count()
	if not going_on:
		Sprite.free_record(m, u32(DIGIT_SPRITE))
		Sprite.free_record(m, u32(QUESTION_SPRITE))
	m.d2 = saved[0]; m.a0 = saved[1]; m.a1 = saved[2]
	m.d0 = with_low16(m.d0, 1 if going_on else 0)


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _count() -> bool:
	if u16(COUNTING) == 0:
		var frames := s16(FRAMES_AFTER) - 1
		set16(FRAMES_AFTER, frames)
		if frames > 0:
			return true
		set16(CONTINUE_DECLINED, 0)
		return false
	if u16(COIN_CAME) != 0:
		# a coin starts the count again
		set16(NUMBER, FIRST_NUMBER)
		set16(FRAMES, FRAMES_A_NUMBER)
		set16(FIELD_1032D0, 0x100)
	if u16(GOES_ON) != 0:
		set16(COUNTING, 0)
		_request_sound(SOUND_GOES_ON)
		return true
	var number := s16(NUMBER)
	if number < 0:
		set16(CONTINUE_DECLINED, 0xFFFF)
		return false
	var digit := u32(DIGIT_SPRITE)
	var picture := m.r32(PICTURES + number * 4)
	Sprite.picture(m, digit, picture)
	m.a3 = picture
	var width := m.r16(WIDTHS + wrap16(u16(FRAMES) * 2))
	Sprite.zoom(m, digit, width, 0x100)
	Sprite.place(m, digit, DIGIT_MIDDLE - (wrap16(width) >> 3), DIGIT_Y)
	m.call_routine(BUILD_SPRITES)
	if u16(FRAMES) == FRAMES_A_NUMBER:
		_request_sound(SOUND_TICK)
		if number <= 3:
			_request_sound(m.r16(LAST_NUMBER_SOUNDS + number * 2))
	var joystick := sibling(Joystick) as Joystick
	# button A hurries the count
	if joystick.pressed(0, Joystick.BUTTON_A) or joystick.pressed(1, Joystick.BUTTON_A):
		set16(FRAMES, 1)
	var frames := s16(FRAMES) - 1
	set16(FRAMES, frames)
	if frames < 0:
		set16(FRAMES, FRAMES_A_NUMBER)
		set16(NUMBER, number - 1)
		set16(FIELD_1032D0, 0x100)
	return true
