extends GameRoutines
## The part of the attract mode that presents the three cars one after the
## other: what each is like grows in, its name slides in from both sides,
## and the car itself turns round on the spot.

const Car := preload("res://game/car.gd")
const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Heap := preload("res://game/heap.gd")
const Wipe := preload("res://game/wipe.gd")
const CreditsLine := preload("res://game/credits_line.gd")

## The car shown. It is drawn by the code that draws the player's car,
## from a car of its own for each, kept in memory asked for.
const CHOSEN_CAR := 0x1011FA
const CAR_COUNT := 3
const CARS := 0x100490
const CAR_SIZE := 0x156
## The address of its 32 sprite objects: two parts of the name that come
## from the right and two from the left, and 28 of the description.
const SPRITES := 0x10048C
const SPRITE_COUNT := 32
const NAME_SPRITES := 4
const FRAMES := 0x10049C
## How far the description has grown: 0 to 29.
const GROWN := 0x10049E
const FULLY_GROWN := 29
## Where the two halves of the name are.
const FROM_RIGHT := 0x1004A0
const FROM_LEFT := 0x1004A2
const NAME_SPEED := 8
const NAME_AT := 0x20
## Which way the car faces (of 32), and frames it has faced that way.
const FACING := 0x1004A4
const FACING_FRAMES := 0x1004A6
const FIRST_FACING := 0x18
const STATE := 0x1004A8
enum {GROWING, NAME_SLIDING, TURNING, BETWEEN, DONE}
const FIELD_1004AA := 0x1004AA
## By car, what each sprite object shows, four words each (picture, x, y,
## depth): the description, and the two halves of the name.
const DESCRIPTIONS := 0x388A
const NAMES_FROM_RIGHT := 0x35B6
const NAMES_FROM_LEFT := 0x362E
const PICTURES := 0x80040
## By how far it has grown, the description's zoom across and its x.
const GROWN_ZOOM := 0x3942
const GROWN_X := 0x3906
const CAR_X := 0xE0
const CAR_Y := 0x50
const FIRST_CAR_Y := 0x48
const CAR_OFF_SCREEN_Y := 0x190
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 16
const COLOURS := 0x3B50
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E
const SET_UP_COURSE_TIMES := 0x169A8
const LOAD_COLOURS := 0x1690E
const COURSE := 0x101202
const PLAYER := 0x1011FC


func routines() -> Dictionary:
	return {
		0x3462: set_up,
		0x34D8: update,
		0x3504: growing,
		0x3566: name_sliding,
		0x36A4: turning,
		0x37AE: between,
		0x3812: done,
		0x382A: func() -> void: _take_list(low16(m.d0)),
		0x3850: func() -> void: _take_sprites(low16(m.d0)),
		0x386E: show_description,
		0x39B0: set_up_cars,
		0x3B34: func() -> void: _fade(low16(m.d2)),
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	for address: int in [0x382A, 0x3850, 0x386E, 0x39B0, 0x3B34]:
		table[address] = ["ccr"]
	table[0x39B0] = ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "a1", "a2", "a3", "a4", "a5", "ccr"]
	return table


func _fade(brightness: int) -> void:
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, brightness)


func _sprite(index: int) -> int:
	return u32(u32(SPRITES) + index * 4)


func _picture(number: int) -> int:
	return m.r32(m.r32(PICTURES) + wrap16(number * 4))


func _take_list(count: int) -> void:
	var heap := sibling(Heap) as Heap
	heap.reset()
	set32(SPRITES, 0)
	set32(SPRITES, heap.take(count * 4))


func _take_sprites(count: int) -> void:
	for index in count:
		set32(u32(SPRITES) + index * 4, Sprite.take_record(m))


## $3462
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	_fade(0x100)
	(sibling(Wipe) as Wipe).start(false, 0)
	set16(GROWN, 0)
	set16(STATE, GROWING)
	set16(FIELD_1004AA, 0)
	set8(FACING_FRAMES, 0)
	set16(FACING, FIRST_FACING)
	_start_car()
	_take_list(SPRITE_COUNT)
	_take_sprites(SPRITE_COUNT)
	set_up_cars()
	set16(CHOSEN_CAR, 0)
	m.d0 = with_low16(m.d0, 0)


func _start_car() -> void:
	set16(FRAMES, 59)
	set16(FROM_RIGHT, 0x140)
	set16(FROM_LEFT, -0x100)


## $39B0: the three cars, each set up as for a race on the practice
## course and put below the screen.
func set_up_cars() -> void:
	var saved := [m.d0, m.a0, m.a6]
	var car := sibling(Car) as Car
	m.call_routine(SET_UP_COURSE_TIMES)
	set16(Car.MACHINE, 0)
	set16(COURSE, 0)
	set16(Car.DEMO_PLAYING, 0)
	set16(PLAYER, 0)
	var heap := sibling(Heap) as Heap
	for index in CAR_COUNT:
		set32(CARS + index * 4, heap.take(CAR_SIZE))
	for index in CAR_COUNT:
		set16(CHOSEN_CAR, index)
		m.d0 = with_low16(m.d0, index + 0x12)
		m.call_routine(LOAD_COLOURS)
		m.a6 = u32(CARS + index * 4)
		car.set_up()
		set16(m.a6 + Car.SHAKE_HEIGHT, 0)
		set16(m.a6 + Car.ZOOM_TARGET, 0x100)
		set16(m.a6 + Car.ZOOM, 0x100)
		set16(m.a6 + Car.ZOOM_BEFORE, 0x100)
		car.set_depth()
		car.hide()
		_put_car_away()
		car.draw_on_ground()
	m.d0 = saved[0]; m.a0 = saved[1]; m.a6 = saved[2]


func _put_car_away() -> void:
	set16(m.a6 + Car.SCREEN_X, CAR_X)
	set16(m.a6 + Car.SCREEN_Y, CAR_OFF_SCREEN_Y)
	set16(m.a6 + Car.PICTURE_DIRECTION, FIRST_FACING)


## $34D8: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		GROWING: growing()
		NAME_SLIDING: name_sliding()
		TURNING: turning()
		BETWEEN: between()
		DONE: done()
	m.call_routine(BUILD_SPRITES)


## $3504
func growing() -> void:
	for index in SPRITE_COUNT:
		Sprite.show(m, _sprite(index), index >= NAME_SPRITES)
	show_description()
	set16(GROWN, u16(GROWN) + 1)
	if u16(GROWN) > FULLY_GROWN:
		set16(GROWN, FULLY_GROWN)
		set16(FRAMES, u16(FRAMES) - 1)
		if s16(FRAMES) < 0:
			set16(STATE, NAME_SLIDING)
	m.d0 = with_low16(m.d0, 1)


## $386E
func show_description() -> void:
	var entry := m.r32(DESCRIPTIONS + wrap16(u16(CHOSEN_CAR) * 4))
	var grown := wrap16(u16(GROWN) * 2)
	for index in range(NAME_SPRITES, SPRITE_COUNT):
		var sprite := _sprite(index)
		Sprite.zoom(m, sprite, m.r16(GROWN_ZOOM + grown), 0x100)
		_show(sprite, entry, m.r16(GROWN_X + grown))
		entry += 8


## A sprite object as its four words say, `across` further right.
## Returns its x.
func _show(sprite: int, entry: int, across: int) -> int:
	Sprite.picture(m, sprite, _picture(m.r16(entry)))
	var x := wrap16(across + m.r16(entry + 2))
	Sprite.place(m, sprite, x, m.r16(entry + 4))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))
	return x


## $3566
func name_sliding() -> void:
	if s16(FROM_RIGHT) < NAME_AT:
		set16(FROM_RIGHT, NAME_AT)
	if s16(FROM_LEFT) >= NAME_AT:
		set16(FROM_LEFT, NAME_AT)
		set16(FRAMES, 209)
		set16(STATE, TURNING)
	var car := wrap16(u16(CHOSEN_CAR) * 4)
	var entry := m.r32(NAMES_FROM_RIGHT + car)
	var margin := m.view_margin
	for index in 2:
		var sprite := _sprite(index)
		var x := _show(sprite, entry + index * 8, _widened(u16(FROM_RIGHT)))
		Sprite.show(m, sprite, x <= 0x140 + margin)
	entry = m.r32(NAMES_FROM_LEFT + car)
	for index in 2:
		var sprite := _sprite(2 + index)
		var x := _show(sprite, entry + index * 8, _widened(u16(FROM_LEFT)))
		Sprite.show(m, sprite, x >= -0x80)
	set16(FROM_RIGHT, u16(FROM_RIGHT) - NAME_SPEED)
	set16(FROM_LEFT, u16(FROM_LEFT) + NAME_SPEED)
	m.d0 = with_low16(m.d0, 1)


## Where a half of the name that is `from` is drawn. In a picture wider than
## the original's (the machine's `view_margin`) the halves come from its
## edges, as much faster as they have further to go, and are drawn even
## where the original's picture ends.
func _widened(from: int) -> int:
	var margin := m.view_margin
	if margin <= 0:
		return from
	for index in NAME_SPRITES:
		m.open_records[_sprite(index) & 0xFFFF] = true
	var way := 0x140 - NAME_AT
	return wrap16(NAME_AT + (wrap16(from) - NAME_AT) * (way + margin) / way)


## $36A4: the car turns round, a step every second frame; at the end the
## curtain closes on it.
func turning() -> void:
	var car := sibling(Car) as Car
	var shown := u16(CHOSEN_CAR)
	m.a6 = u32(CARS + mini(shown, CAR_COUNT - 1) * 4)
	car.show()
	set16(m.a6 + Car.SCREEN_X, CAR_X)
	set16(m.a6 + Car.SCREEN_Y, FIRST_CAR_Y if shown == 0 else CAR_Y)
	set16(FACING, u16(FACING) & 0x1F)
	set16(m.a6 + Car.PICTURE_DIRECTION, u16(FACING))
	car.draw_on_ground()
	if u8(FACING_FRAMES) & 2:
		set16(FACING, u16(FACING) + 1)
		set8(FACING_FRAMES, 0)
	set8(FACING_FRAMES, u8(FACING_FRAMES) + 1)
	m.d0 = with_low16(m.d0, 1)
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) >= 0:
		return
	set16(FRAMES, 0)
	var credits := sibling(CreditsLine) as CreditsLine
	if u16(FIELD_1004AA) == 0:
		credits.hide()
	(sibling(Wipe) as Wipe).step()
	if u16(Wipe.RUNNING) == 1:
		m.d0 = with_low16(m.d0, 1)
		return
	credits.show()
	for index in SPRITE_COUNT:
		Sprite.show(m, _sprite(index), false)
	car.hide()
	_put_car_away()
	set8(FACING_FRAMES, 0)
	set16(FACING, FIRST_FACING)
	set16(FRAMES, 29)
	set16(STATE, BETWEEN)
	m.d0 = with_low16(m.d0, 1)


## $37AE: after half a second the next car, or the end.
func between() -> void:
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) < 0:
		m.call_routine(CLEAR_TEXT)
		(sibling(Wipe) as Wipe).start(false, 0)
		set16(STATE, DONE)
		if u16(CHOSEN_CAR) < CAR_COUNT - 1:
			set16(CHOSEN_CAR, u16(CHOSEN_CAR) + 1)
			set16(FIELD_1004AA, 0)
			set16(GROWN, 0)
			_start_car()
			set16(STATE, GROWING)
	m.d0 = with_low16(m.d0, 1)


## $3812
func done() -> void:
	m.call_routine(CLEAR_SPRITES)
	(sibling(Heap) as Heap).give_back(u32(SPRITES))
	m.d0 = with_low16(m.d0, 0)
