extends GameRoutines
## The picture a game closes with, after the list of best times: a line of
## writing opens out over the car driven and stays a second, then the
## picture is squeezed flat, drawn out into a line and faded away.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Joystick := preload("res://game/joystick.gd")
const CreditsLine := preload("res://game/credits_line.gd")

## The car driven, and how the game ended ($FFFF: it was given up).
const CAR := 0x1011FA
const GAME_RESULT_SHOWN := 0x10120A
## The sprite objects of the writing and of the picture.
const WRITING := 0x1011CE
const PICTURE := 0x1011D2
## Frames left of the writing opening out and of it staying.
const OPENING_FRAMES := 0x1011D6
const STAYING_FRAMES := 0x1011D8
## The writing's zoom down and where it is, the picture's zoom down and
## across and where it is.
const WRITING_ZOOM := 0x1011DA
const WRITING_X := 0x1011DC
const WRITING_Y := 0x1011DE
const PICTURE_ZOOM_Y := 0x1011E0
const PICTURE_ZOOM_X := 0x1011E2
const PICTURE_X := 0x1011E4
const PICTURE_Y := 0x1011E6
## What the picture is at, and the whole screen.
const PICTURE_STATE := 0x1011E8
const STATE := 0x1011EA
enum {OPENING, STAYING, SET_UP_PICTURE, PICTURE_LEAVING, OVER}
enum {SQUEEZING, DRAWING_OUT, FADING, GONE}
## Which step of a list of zooms the picture is at, the frames left of it
## and its zoom; the same of a list of brightnesses.
const ZOOM_STEP := 0x1011EC
const ZOOM_FRAMES := 0x1011EE
const ZOOM := 0x1011F0
const FADE_FRAMES := 0x1011F2
const FADE_STEP := 0x1011F4
const BRIGHTNESS := 0x1011F6
## The lists: a value and the frames it lasts.
const ZOOMS := 0x9E90
const SQUEEZED_AT := 9
const DRAWN_OUT_AT := 0x3A
const FADES := 0x9F78
const FADED_AT := 0x22
## The pictures: that of the writing, then one by car.
const PICTURES := 0xA124
const COLOURS := [0x40, 5, 0xA004]
const LINE_COLOURS := [0x44, 1, 0xA0F4]
const FULLY_LIT := 0x100
## The picture comes up nearly dark.
const DARK := 0x10
const LINE_PALETTE := 0xFF44
const WRITING_AT := Vector2i(0x28, 0x80)
const WRITING_Y_OPEN := 0x60
const SOUND_GIVEN_UP := 0x185F
const SOUND_FINISHED := 0x1861
const SOUND_LEAVING := 0xC3
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x994C: set_up,
		0x9A82: update,
		0x9B06: func() -> void: m.d0 = with_low16(m.d0, _announce()),
		0x9B2A: func() -> void: m.d0 = with_low16(m.d0, _open()),
		0x9BA4: func() -> void: m.d0 = with_low16(m.d0, _stay()),
		0x9BEA: func() -> void: m.d0 = with_low16(m.d0, _set_up_picture()),
		0x9C64: func() -> void: m.d0 = with_low16(m.d0, _picture_leaving()),
		0x9D94: func() -> void: m.d0 = with_low16(m.d0, _draw_out()),
		0x9E14: func() -> void: m.d0 = with_low16(m.d0, _fade()),
		0x9E7E: func() -> void: m.d0 = with_low16(m.d0, _remove()),
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "a0", "a1", "a3", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	return table


## $994C; leaves 0 in D0.
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	sibling(Palettes).queue(COLOURS[0], COLOURS[1], COLOURS[2], FULLY_LIT)
	var writing := Sprite.take_record(m)
	set32(WRITING, writing)
	var picture := Sprite.take_record(m)
	set32(PICTURE, picture)
	set16(WRITING_X, WRITING_AT.x)
	set16(WRITING_Y, WRITING_AT.y)
	Sprite.place(m, writing, WRITING_AT.x, WRITING_AT.y)
	set16(PICTURE_X, 0)
	set16(PICTURE_Y, 0)
	Sprite.place(m, picture, 0, 0)
	set16(WRITING_ZOOM, 1)
	Sprite.zoom(m, writing, 0xA0, 1)
	set16(PICTURE_ZOOM_X, 0x100)
	set16(PICTURE_ZOOM_Y, 0x100)
	m.w16(writing + Sprite.DEPTH, 1)
	m.w16(picture + Sprite.DEPTH, 0)
	Sprite.picture(m, writing, rom_u32(PICTURES))
	Sprite.picture(m, picture, rom_u32(PICTURES + 4 + u16(CAR) * 4))
	m.call_routine(BUILD_SPRITES)
	set16(STATE, OPENING)
	set16(OPENING_FRAMES, 0x78)
	set16(STAYING_FRAMES, 0x3C)
	sibling(CreditsLine).show()
	sibling(CreditsLine).draw_credits()
	sibling(CreditsLine).draw_level()
	m.d0 = with_low16(m.d0, _announce())


## $9B06
func _announce() -> int:
	sibling(SoundRequests).request(SOUND_GIVEN_UP if u16(GAME_RESULT_SHOWN) == 0xFFFF else SOUND_FINISHED)
	return 0


## $9A82: 1 in D0 while it goes on. Button A of either player cuts the
## writing short.
func update() -> void:
	var state := u16(STATE)
	if state >= OVER:
		m.d0 = with_low16(m.d0, 0)
		return
	if state <= STAYING:
		var joystick: Joystick = sibling(Joystick)
		if joystick.pressed(0, Joystick.BUTTON_A) or joystick.pressed(1, Joystick.BUTTON_A):
			state += 1
			set16(STATE, state)
	var going := 0
	match state:
		OPENING:
			going = _open()
		STAYING:
			going = _stay()
		SET_UP_PICTURE:
			going = _set_up_picture()
		PICTURE_LEAVING:
			going = _picture_leaving()
	if going == 0:
		set16(STATE, u16(STATE) + 1)
	m.d0 = with_low16(m.d0, 1)


## $9B2A
func _open() -> int:
	set16(OPENING_FRAMES, u16(OPENING_FRAMES) - 1)
	if u16(OPENING_FRAMES) == 0:
		return 0
	var zoom := (u16(WRITING_ZOOM) + 5) & 0xFFFF
	var y := WRITING_AT.y - (zoom >> 3)
	if zoom > 0x100:
		zoom = 0x100
		y = WRITING_Y_OPEN
	set16(WRITING_Y, y)
	set16(WRITING_ZOOM, zoom)
	var writing := u32(WRITING)
	Sprite.zoom(m, writing, 0x100, zoom)
	Sprite.place(m, writing, WRITING_AT.x, y)
	m.call_routine(BUILD_SPRITES)
	return 1


## $9BA4
func _stay() -> int:
	set16(STAYING_FRAMES, u16(STAYING_FRAMES) - 1)
	if s16(STAYING_FRAMES) <= 0:
		return 0
	var writing := u32(WRITING)
	Sprite.zoom(m, writing, 0x100, 0x100)
	Sprite.place(m, writing, WRITING_AT.x, WRITING_Y_OPEN)
	m.call_routine(BUILD_SPRITES)
	return 1


## $9BEA
func _set_up_picture() -> int:
	sibling(Palettes).choose_shades(1)
	sibling(Palettes).queue(COLOURS[0], COLOURS[1], COLOURS[2], DARK)
	Sprite.show(m, u32(PICTURE), true)
	set16(PICTURE_STATE, SQUEEZING)
	set16(ZOOM_FRAMES, 0)
	set16(ZOOM_STEP, 0xFFFF)
	set16(ZOOM, 0x100)
	set16(FADE_FRAMES, 0)
	set16(FADE_STEP, 0xFFFF)
	set16(BRIGHTNESS, 0x100)
	sibling(SoundRequests).request(SOUND_LEAVING)
	return 0


## $9C64
func _picture_leaving() -> int:
	var picture := u32(PICTURE)
	Sprite.place(m, picture, u16(PICTURE_X), u16(PICTURE_Y))
	Sprite.zoom(m, picture, u16(PICTURE_ZOOM_X), u16(PICTURE_ZOOM_Y))
	m.call_routine(BUILD_SPRITES)
	match u16(PICTURE_STATE):
		SQUEEZING:
			return _squeeze()
		DRAWING_OUT:
			return _draw_out()
		FADING:
			return _fade()
	return _remove()


## Steps on in the list of zooms when the step it is at is over; true when
## that came to step `end`.
func _next_zoom(end: int) -> bool:
	if u16(ZOOM_FRAMES) != 0:
		return false
	set16(ZOOM_STEP, u16(ZOOM_STEP) + 1)
	var step := ZOOMS + s16(ZOOM_STEP) * 4
	set16(ZOOM, rom_u16(step))
	set16(ZOOM_FRAMES, rom_u16(step + 2))
	return s16(ZOOM_STEP) >= end


## $9CB6: the picture is squeezed down to a line, the writing with it.
func _squeeze() -> int:
	if _next_zoom(SQUEEZED_AT):
		m.w16(u32(PICTURE) + Sprite.PALETTE, LINE_PALETTE)
		Sprite.free_record(m, u32(WRITING))
		sibling(Palettes).choose_shades(0)
		set16(PICTURE_STATE, u16(PICTURE_STATE) + 1)
		return 1
	set16(ZOOM_FRAMES, u16(ZOOM_FRAMES) - 1)
	set16(PICTURE_ZOOM_X, 0x100)
	var zoom := s16(ZOOM)
	set16(PICTURE_ZOOM_Y, zoom)
	set16(PICTURE_Y, (((0x100 - zoom) * 0x80) & 0xFFFFFFFF) >> 8)
	var writing := u32(WRITING)
	Sprite.zoom(m, writing, 0x100, zoom)
	Sprite.place(m, writing, u16(WRITING_X), WRITING_AT.y - (((zoom * 0x20) & 0xFFFFFFFF) >> 8))
	return 1


## $9D94: the line is drawn out to the right.
func _draw_out() -> int:
	if _next_zoom(DRAWN_OUT_AT):
		set16(PICTURE_STATE, u16(PICTURE_STATE) + 1)
		return 1
	set16(ZOOM_FRAMES, u16(ZOOM_FRAMES) - 1)
	var zoom := s16(ZOOM)
	set16(PICTURE_ZOOM_X, zoom)
	set16(PICTURE_ZOOM_Y, 1)
	set16(PICTURE_X, (((0x100 - zoom) * 0xA0) & 0xFFFFFFFF) >> 8)
	return 1


## $9E14: the line fades.
func _fade() -> int:
	if u16(FADE_FRAMES) == 0:
		set16(FADE_STEP, u16(FADE_STEP) + 1)
		var step := FADES + s16(FADE_STEP) * 4
		set16(BRIGHTNESS, rom_u16(step))
		set16(FADE_FRAMES, rom_u16(step + 2))
		if s16(FADE_STEP) >= FADED_AT:
			set16(PICTURE_STATE, u16(PICTURE_STATE) + 1)
			return 1
	set16(FADE_FRAMES, u16(FADE_FRAMES) - 1)
	sibling(Palettes).queue(LINE_COLOURS[0], LINE_COLOURS[1], LINE_COLOURS[2], s16(BRIGHTNESS))
	return 1


## $9E7E
func _remove() -> int:
	Sprite.free_record(m, u32(PICTURE))
	return 0
