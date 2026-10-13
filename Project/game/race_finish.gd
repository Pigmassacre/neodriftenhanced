extends GameRoutines
## The end of a race: a banner for the finish reached, or one that drops
## in when the time ran out, and then the curtain closes.

const Car := preload("res://game/car.gd")
const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Wipe := preload("res://game/wipe.gd")
const CreditsLine := preload("res://game/credits_line.gd")

const CAR := 0x101508
const STATE := 0x101248
enum {SET_UP_FINISHED, FINISHED, SET_UP_TIME_OVER, TIME_OVER, SET_UP_CURTAIN, CURTAIN}
## 0 when the car made it to the finish.
const RACE_RESULT := 0x101206
const COURSE := 0x101202
const LAST_COURSE := 6
const PLAYER := 0x1011FC
## The address of the address of the pictures: those of the countdown
## first, then these: the two parts of "time over", the banner of the
## finish, and what stands under it, after a course and after the last.
const PICTURES := 0x80014
const PICTURE_TIME_OVER := 0
const PICTURE_FINISH := 2
const PICTURE_COURSE_DONE := 3
const PICTURE_ALL_DONE := 4
const IN_FRONT := 0x7FFF
## Either banner stays for two seconds, or until a button is pressed.
const FRAMES_SHOWN := 120

# The banner of the finish.
const BANNER := 0x10124A
const BANNER_STATE := 0x00
const BANNER_FRAMES := 0x02
const BANNER_BRIGHTNESS := 0x04
const BANNER_SPRITES := 0x06
enum {BANNER_SET_UP, BANNER_APPEARING, BANNER_HOLD, BANNER_HELD}
const BANNER_PLACE := Vector2i(0x50, 0x60)
const BELOW_PLACE := Vector2i(0x40, 0xA0)
## Its two palettes and their colours.
const BANNER_PALETTES: Array[int] = [0x34, 0x36]
const BANNER_COLOURS: Array[int] = [0x1FEC6, 0x1FE96]

# "Time over".
const OVER := 0x101258
const OVER_STATE := 0x00
const OVER_FRAMES := 0x02
const OVER_X := 0x04
const OVER_Y := 0x06
const OVER_FALL := 0x08
const OVER_SPRITES := 0x0C
enum {OVER_SET_UP, OVER_FALLING, OVER_LANDED, OVER_HELD}
const OVER_FIRST_Y := -0x30
const OVER_LAST_Y := 0x60
const OVER_GRAVITY := 0x1800
const OVER_SECOND_PART := Vector2i(0x10, 0x20)

const SOUND_FINISH := 0x185E
const SOUND_TIME_OVER := 0x1860
const SOUND_CURTAIN := 0xC3
const CLEAR_SIGNS := 0x146E2
const COURSE_OBJECTS := 0x14160
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0xBE50: set_up,
		0xBE90: update,
		0xBEBA: set_up_curtain,
		0xBEEA: close_curtain,
		0xBF08: set_up_finished,
		0xBF2C: finished,
		0xBF46: set_up_time_over,
		0xBF60: time_over,
		0xBF7A: set_up_banner,
		0xC01E: show_banner,
		0xC06A: func() -> void: _state(banner_set_up),
		0xC0B6: func() -> void: _state(banner_appearing),
		0xC10C: func() -> void: _state(banner_hold),
		0xC11E: func() -> void: _state(banner_held),
		0xC170: set_up_over,
		0xC204: show_over,
		0xC250: func() -> void: _state(over_set_up),
		0xC25C: func() -> void: _state(over_falling),
		0xC294: func() -> void: _state(over_landed),
		0xC2AA: func() -> void: _state(over_held),
		0xC314: place_over,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	table[0xC314] = ["d0", "d2", "a0", "ccr"]
	return table


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _picture(number: int) -> int:
	return m.r32(m.r32(m.r32(PICTURES) + 4) + number * 4)


## The car and everything around it, as the race left them.
func _draw(with_objects := true) -> void:
	var car := sibling(Car) as Car
	m.a6 = CAR
	car.draw_on_ground()
	car.draw_rivals()
	if with_objects:
		m.call_routine(COURSE_OBJECTS)
	m.call_routine(BUILD_SPRITES)


## For a state entered on its own.
func _state(state: Callable) -> void:
	m.d0 = with_low16(m.d0, 1 if state.call() else 0)


## $BE50
func set_up() -> void:
	set16(STATE, SET_UP_FINISHED if u16(RACE_RESULT) == 0 else SET_UP_TIME_OVER)
	m.call_routine(CLEAR_SIGNS)
	_draw(false)
	m.d0 = with_low16(m.d0, 0)


## $BE90: a frame of it. Leaves 0 in D0 at its end.
func update() -> void:
	match u16(STATE):
		SET_UP_FINISHED: set_up_finished()
		FINISHED: finished()
		SET_UP_TIME_OVER: set_up_time_over()
		TIME_OVER: time_over()
		SET_UP_CURTAIN: set_up_curtain()
		CURTAIN: close_curtain()


## $BEBA
func set_up_curtain() -> void:
	_request_sound(SOUND_CURTAIN)
	(sibling(CreditsLine) as CreditsLine).hide()
	var wipe := sibling(Wipe) as Wipe
	wipe.fill(true)
	wipe.start(false, 0)
	set16(STATE, CURTAIN)
	m.d0 = with_low16(m.d0, 1)


## $BEEA
func close_curtain() -> void:
	(sibling(Wipe) as Wipe).step()
	if u16(Wipe.RUNNING) != 0:
		m.d0 = with_low16(m.d0, 1)
		return
	(sibling(CreditsLine) as CreditsLine).show()
	m.d0 = with_low16(m.d0, 0)


## $BF08
func set_up_finished() -> void:
	_request_sound(SOUND_FINISH)
	set_up_banner()
	set16(STATE, FINISHED)
	m.d0 = with_low16(m.d0, 1)


## $BF2C
func finished() -> void:
	show_banner()
	if low16(m.d0) == 0:
		set16(STATE, SET_UP_CURTAIN)
	m.d0 = with_low16(m.d0, 1)


## $BF46
func set_up_time_over() -> void:
	set_up_over()
	set16(STATE, TIME_OVER)
	m.d0 = with_low16(m.d0, 1)


## $BF60
func time_over() -> void:
	show_over()
	if low16(m.d0) == 0:
		set16(STATE, SET_UP_CURTAIN)
	m.d0 = with_low16(m.d0, 1)


func _take_sprite(picture: int) -> int:
	var sprite := Sprite.take_record(m)
	set16(sprite + Sprite.DEPTH, IN_FRONT)
	Sprite.picture(m, sprite, _picture(picture))
	return sprite


## $BF7A
func set_up_banner() -> void:
	_draw()
	set16(BANNER + BANNER_STATE, BANNER_SET_UP)
	var banner := _take_sprite(PICTURE_FINISH)
	set32(BANNER + BANNER_SPRITES, banner)
	Sprite.place(m, banner, BANNER_PLACE.x, BANNER_PLACE.y)
	var below := _take_sprite(PICTURE_ALL_DONE if s16(COURSE) >= LAST_COURSE else PICTURE_COURSE_DONE)
	set32(BANNER + BANNER_SPRITES + 4, below)
	Sprite.place(m, below, BELOW_PLACE.x, BELOW_PLACE.y)
	m.d0 = with_low16(m.d0, 0)


## $C01E: a frame of the banner. Leaves 0 in D0 at its end.
func show_banner() -> void:
	var going_on := true
	match u16(BANNER + BANNER_STATE):
		BANNER_SET_UP: going_on = banner_set_up()
		BANNER_APPEARING: going_on = banner_appearing()
		BANNER_HOLD: going_on = banner_hold()
		BANNER_HELD: going_on = banner_held()
	_draw()
	m.d0 = with_low16(m.d0, 1 if going_on else 0)


func _fade_banner() -> void:
	for index in 2:
		(sibling(Palettes) as Palettes).queue(BANNER_PALETTES[index], 1, BANNER_COLOURS[index],
				u16(BANNER + BANNER_BRIGHTNESS))


## $C06A
func banner_set_up() -> bool:
	set16(BANNER + BANNER_BRIGHTNESS, 0)
	(sibling(Palettes) as Palettes).choose_shades(1)
	_fade_banner()
	set16(BANNER + BANNER_STATE, BANNER_APPEARING)
	return true


## $C0B6
func banner_appearing() -> bool:
	var brightness := mini(wrap16(u16(BANNER + BANNER_BRIGHTNESS) + 8), 0x100)
	set16(BANNER + BANNER_BRIGHTNESS, brightness)
	_fade_banner()
	if brightness >= 0x100:
		set16(BANNER + BANNER_STATE, BANNER_HOLD)
	return true


## $C10C
func banner_hold() -> bool:
	set16(BANNER + BANNER_FRAMES, FRAMES_SHOWN)
	set16(BANNER + BANNER_STATE, BANNER_HELD)
	return true


## Counts the frames a banner at `frames` stays; a button ends it at once.
func _count_shown(frames: int) -> bool:
	var joystick := sibling(Joystick) as Joystick
	if joystick.held(u16(PLAYER), Joystick.BUTTON_A) or joystick.held(u16(PLAYER), Joystick.BUTTON_B):
		set16(frames, 0)
	set16(frames, u16(frames) - 1)
	return s16(frames) >= 0


## $C11E
func banner_held() -> bool:
	if _count_shown(BANNER + BANNER_FRAMES):
		return true
	Sprite.free_record(m, u32(BANNER + BANNER_SPRITES))
	Sprite.free_record(m, u32(BANNER + BANNER_SPRITES + 4))
	return false


## $C170
func set_up_over() -> void:
	set16(OVER + OVER_STATE, OVER_SET_UP)
	set16(OVER + OVER_FRAMES, FRAMES_SHOWN)
	set16(OVER + OVER_X, 0x40)
	set16(OVER + OVER_Y, OVER_FIRST_Y)
	set32(OVER + OVER_FALL, 0)
	set32(OVER + OVER_SPRITES, _take_sprite(PICTURE_TIME_OVER))
	set32(OVER + OVER_SPRITES + 4, _take_sprite(PICTURE_TIME_OVER + 1))
	place_over()
	_draw()
	m.d0 = with_low16(m.d0, 0)


## $C204: a frame of "time over". Leaves 0 in D0 at its end.
func show_over() -> void:
	var going_on := true
	match u16(OVER + OVER_STATE):
		OVER_SET_UP: going_on = over_set_up()
		OVER_FALLING: going_on = over_falling()
		OVER_LANDED: going_on = over_landed()
		OVER_HELD: going_on = over_held()
	_draw()
	m.d0 = with_low16(m.d0, 1 if going_on else 0)


## $C250
func over_set_up() -> bool:
	set16(OVER + OVER_STATE, OVER_FALLING)
	return true


## $C25C: it falls from above the screen.
func over_falling() -> bool:
	set32(OVER + OVER_FALL, u32(OVER + OVER_FALL) + OVER_GRAVITY)
	var y := mini(wrap16(u16(OVER + OVER_Y) + u16(OVER + OVER_FALL)), OVER_LAST_Y)
	set16(OVER + OVER_Y, y)
	place_over()
	if y >= OVER_LAST_Y:
		set16(OVER + OVER_STATE, OVER_LANDED)
	return true


## $C294
func over_landed() -> bool:
	_request_sound(SOUND_TIME_OVER)
	set16(OVER + OVER_STATE, OVER_HELD)
	return true


## $C2AA
func over_held() -> bool:
	if _count_shown(OVER + OVER_FRAMES):
		_draw(false)
		return true
	Sprite.free_record(m, u32(OVER + OVER_SPRITES))
	Sprite.free_record(m, u32(OVER + OVER_SPRITES + 4))
	return false


## $C314
func place_over() -> void:
	var x := u16(OVER + OVER_X)
	var y := u16(OVER + OVER_Y)
	Sprite.place(m, u32(OVER + OVER_SPRITES), x, y)
	Sprite.place(m, u32(OVER + OVER_SPRITES + 4), x + OVER_SECOND_PART.x, y + OVER_SECOND_PART.y)
