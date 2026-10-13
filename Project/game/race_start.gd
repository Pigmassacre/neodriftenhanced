extends GameRoutines
## The start of a race: the course is set up behind the curtain, the
## curtain opens, the camera closes in on the car, and "3, 2, 1" is counted
## down.

const Car := preload("res://game/car.gd")
const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Wipe := preload("res://game/wipe.gd")
const CreditsLine := preload("res://game/credits_line.gd")

const CAR := 0x101508
const STATE := 0x101238
enum {SET_UP, CURTAIN, LABEL, CLOSING_IN, SET_UP_COUNTDOWN, COUNTDOWN}
## 1 when the course's music is to play.
const MUSIC_WANTED := 0x10042C
## 1 while the attract mode runs: its races are labelled.
const ATTRACT_MODE := 0x101210
## The camera starts this far out and closes in to 1:1 by a step a frame.
const FIRST_ZOOM := 0xC0

# The countdown.
const COUNT := 0x10123A
const COUNT_STATE := 0x00
const COUNT_BRIGHTNESS := 0x02
const COUNT_ZOOM := 0x04
const COUNT_ENTRY := 0x06
const COUNT_FRAMES := 0x08
const COUNT_SPRITE := 0x0A
enum {COUNT_FIRST, COUNTING, SHOW_GO, GO_APPEARING, HOLD_GO, GO_HELD, SHRINK_GO, GO_SHRINKING, COUNT_DONE}
## What is shown one after the other, five words each: for how many
## frames (0 ends the list), with which sound, which picture, and where.
const COUNTED := 0xBE26
const COUNTED_SIZE := 10
## The address of the address of the pictures of the countdown.
const PICTURES := 0x80014
const GO_PICTURE := 4
const GO_X := 0x40
const GO_Y := 0x50
const GO_WIDTH := 0x60
const GO_PALETTE := 0x34
const GO_COLOURS := 0xBDF6
const GO_HELD_FRAMES := 0x10
const GO_SHRINK_SPEED := 0x18
const SOUND_CURTAIN := 0xC2
const SOUND_GO := 0x1853
const IN_FRONT := 0x7FFF

const SET_UP_COURSE_TIMES := 0x169A8
const BUILD_SPRITES := 0x1229E
const SCROLL_GROUND := 0x13546
const SIGNS := 0x14760
const PROGRESS := 0x19F82
const COURSE_OBJECTS := 0x14160
const ENGINE_SOUND := 0xFA18
const DRAW_DEMO_LABEL := 0xFC74


func routines() -> Dictionary:
	return {
		0xB978: set_up,
		0xB98C: update,
		0xB9C0: set_up_course,
		0xBA62: open_curtain,
		0xBAB6: show_label,
		0xBAD6: close_in,
		0xBB6A: set_up_countdown,
		0xBB7C: count_down,
		0xBB92: start_counting,
		0xBBBC: count,
		0xBC22: func() -> void: _count_state(count_first),
		0xBC2C: func() -> void: _count_state(counting),
		0xBC94: func() -> void: _count_state(show_go),
		0xBD02: func() -> void: _count_state(go_appearing),
		0xBD3A: func() -> void: _count_state(hold_go),
		0xBD4C: func() -> void: _count_state(go_held),
		0xBD5E: func() -> void: _count_state(shrink_go),
		0xBD80: func() -> void: _count_state(go_shrinking),
		0xBDE6: func() -> void: _count_state(count_done),
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	return table


func _car() -> Car:
	return sibling(Car) as Car


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


## $B978
func set_up() -> void:
	set16(Car.FRAMES_SINCE_REV, Car.REV_EVERY)
	set16(STATE, SET_UP)
	m.d0 = with_low16(m.d0, 0)


## $B98C: a frame of the start. Leaves 0 in D0 when the race can begin.
func update() -> void:
	m.a6 = CAR
	set16(CAR + Car.SPEED, 0)
	match u16(STATE):
		SET_UP: set_up_course()
		CURTAIN: open_curtain()
		LABEL: show_label()
		CLOSING_IN: close_in()
		SET_UP_COUNTDOWN: set_up_countdown()
		COUNTDOWN: count_down()


## $B9C0
func set_up_course() -> void:
	_request_sound(SOUND_CURTAIN)
	(sibling(CreditsLine) as CreditsLine).hide()
	var wipe := sibling(Wipe) as Wipe
	wipe.fill(false)
	wipe.start(true, 0)
	m.call_routine(SET_UP_COURSE_TIMES)
	var car := _car()
	m.a6 = CAR
	car.set_up()
	set16(CAR + Car.SKID_COUNTDOWN, 0)
	car.set_up_rivals()
	car.set_up_course()
	car.load_colours()
	car.drive_again()
	car.set_depth()
	set16(CAR + Car.ZOOM, FIRST_ZOOM)
	car.place_camera()
	car.scale_margins()
	car.show_course()
	car.draw_on_ground()
	m.call_routine(SIGNS)
	m.call_routine(PROGRESS)
	m.call_routine(COURSE_OBJECTS)
	m.call_routine(BUILD_SPRITES)
	m.call_routine(SCROLL_GROUND)
	set16(STATE, CURTAIN)
	m.d0 = with_low16(m.d0, 1)


## The car as it stands waiting, and everything around it.
func _draw_waiting() -> void:
	var car := _car()
	m.a6 = CAR
	car.draw_on_ground()
	m.call_routine(ENGINE_SOUND)
	car.rev()
	m.call_routine(COURSE_OBJECTS)
	m.call_routine(BUILD_SPRITES)


## $BA62
func open_curtain() -> void:
	_draw_waiting()
	var wipe := sibling(Wipe) as Wipe
	wipe.step()
	if u16(Wipe.RUNNING) == 0:
		if u16(MUSIC_WANTED) == 1:
			_car().play_course_music()
		(sibling(CreditsLine) as CreditsLine).show()
		set16(STATE, LABEL)
	m.d0 = with_low16(m.d0, 1)


## $BAB6
func show_label() -> void:
	if u16(ATTRACT_MODE) == 1:
		m.call_routine(DRAW_DEMO_LABEL)
	set16(STATE, CLOSING_IN)
	close_in()


## $BAD6
func close_in() -> void:
	var car := _car()
	m.a6 = CAR
	if s16(CAR + Car.ZOOM) >= 0x100:
		set16(CAR + Car.ZOOM, 0x100)
		set16(STATE, SET_UP_COUNTDOWN)
	else:
		set16(CAR + Car.ZOOM, u16(CAR + Car.ZOOM) + 1)
	car.place_camera()
	car.scale_margins()
	car.show_course()
	car.draw_on_ground()
	m.call_routine(ENGINE_SOUND)
	car.rev()
	m.call_routine(COURSE_OBJECTS)
	m.call_routine(BUILD_SPRITES)
	m.call_routine(SCROLL_GROUND)
	m.d0 = with_low16(m.d0, 1)


## $BB6A
func set_up_countdown() -> void:
	start_counting()
	set16(STATE, COUNTDOWN)
	m.d0 = with_low16(m.d0, 1)


## $BB7C
func count_down() -> void:
	count()
	m.d0 = with_low16(m.d0, 0 if low16(m.d0) == 0 else 1)


## $BB92
func start_counting() -> void:
	set16(COUNT + COUNT_STATE, COUNT_FIRST)
	set16(COUNT + COUNT_ENTRY, -COUNTED_SIZE)
	set16(COUNT + COUNT_FRAMES, 0)
	var sprite := Sprite.take_record(m)
	set32(COUNT + COUNT_SPRITE, sprite)
	set16(sprite + Sprite.DEPTH, IN_FRONT)
	count()


## $BBBC: a frame of the countdown. Leaves 0 in D0 at its end.
func count() -> void:
	var going_on := true
	match u16(COUNT + COUNT_STATE):
		COUNT_FIRST: going_on = count_first()
		COUNTING: going_on = counting()
		SHOW_GO: going_on = show_go()
		GO_APPEARING: going_on = go_appearing()
		HOLD_GO: going_on = hold_go()
		GO_HELD: going_on = go_held()
		SHRINK_GO: going_on = shrink_go()
		GO_SHRINKING: going_on = go_shrinking()
		COUNT_DONE: going_on = count_done()
	_draw_waiting()
	m.d0 = with_low16(m.d0, 1 if going_on else 0)


## For a state of the countdown entered on its own.
func _count_state(state: Callable) -> void:
	m.d0 = with_low16(m.d0, 1 if state.call() else 0)


func _count_picture(number: int) -> int:
	return m.r32(m.r32(m.r32(PICTURES)) + wrap16(number * 4))


## $BC22
func count_first() -> bool:
	set16(COUNT + COUNT_STATE, COUNTING)
	return counting()


## $BC2C: each thing of the list in its turn.
func counting() -> bool:
	var frames := s16(COUNT + COUNT_FRAMES) - 1
	set16(COUNT + COUNT_FRAMES, frames)
	if frames >= 0:
		return true
	var entry := wrap16(u16(COUNT + COUNT_ENTRY) + COUNTED_SIZE)
	set16(COUNT + COUNT_ENTRY, entry)
	var counted := COUNTED + entry
	set16(COUNT + COUNT_FRAMES, m.r16(counted))
	if m.r16(counted) == 0:
		set16(COUNT + COUNT_STATE, SHOW_GO)
		return true
	_request_sound(m.r16(counted + 2))
	var sprite := u32(COUNT + COUNT_SPRITE)
	Sprite.picture(m, sprite, _count_picture(m.r16(counted + 4)))
	Sprite.place(m, sprite, m.r16(counted + 6), m.r16(counted + 8))
	return true


func _fade_go() -> void:
	(sibling(Palettes) as Palettes).queue(GO_PALETTE, 1, GO_COLOURS, u16(COUNT + COUNT_BRIGHTNESS))


## $BC94
func show_go() -> bool:
	set16(COUNT + COUNT_BRIGHTNESS, 0)
	_request_sound(SOUND_GO)
	(sibling(Palettes) as Palettes).choose_shades(1)
	_fade_go()
	var sprite := u32(COUNT + COUNT_SPRITE)
	Sprite.picture(m, sprite, _count_picture(GO_PICTURE))
	Sprite.place(m, sprite, GO_X, GO_Y)
	set16(COUNT + COUNT_STATE, GO_APPEARING)
	return true


## $BD02
func go_appearing() -> bool:
	var brightness := wrap16(u16(COUNT + COUNT_BRIGHTNESS) + 0x10)
	if brightness >= 0x100:
		brightness = 0x100
		set16(COUNT + COUNT_STATE, HOLD_GO)
	set16(COUNT + COUNT_BRIGHTNESS, brightness)
	_fade_go()
	return true


## $BD3A
func hold_go() -> bool:
	set16(COUNT + COUNT_FRAMES, GO_HELD_FRAMES)
	set16(COUNT + COUNT_STATE, GO_HELD)
	return true


## $BD4C
func go_held() -> bool:
	var frames := s16(COUNT + COUNT_FRAMES) - 1
	set16(COUNT + COUNT_FRAMES, frames)
	if frames < 0:
		set16(COUNT + COUNT_STATE, SHRINK_GO)
	return true


## $BD5E
func shrink_go() -> bool:
	set16(COUNT + COUNT_ZOOM, 0x100)
	Sprite.zoom(m, u32(COUNT + COUNT_SPRITE), 0x100, 0x100)
	set16(COUNT + COUNT_STATE, GO_SHRINKING)
	return true


## $BD80: it shrinks towards its middle, across only.
func go_shrinking() -> bool:
	var zoom := maxi(s16(COUNT + COUNT_ZOOM) - GO_SHRINK_SPEED, 1)
	set16(COUNT + COUNT_ZOOM, zoom)
	var sprite := u32(COUNT + COUNT_SPRITE)
	Sprite.zoom(m, sprite, zoom, zoom)
	Sprite.place(m, sprite, Car._margin_at_zoom(zoom, GO_WIDTH) + GO_X, GO_WIDTH)
	if zoom <= 1:
		set16(COUNT + COUNT_STATE, COUNT_DONE)
	return true


## $BDE6
func count_done() -> bool:
	Sprite.free_record(m, u32(COUNT + COUNT_SPRITE))
	return false
