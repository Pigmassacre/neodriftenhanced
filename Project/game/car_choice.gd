extends GameRoutines
## The screen where the player chooses one of three cars: the cars slide
## past with the joystick, a clock counts 20 seconds down, and button A (or
## the clock) settles it.
##
## In a picture wider than the original's (the machine's `view_margin`) the
## cars come and go across all of it: see `_widen`.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Text := preload("res://game/text.gd")

## The car chosen: 0 to 2.
const CAR := 0x1011FA
const CAR_COUNT := 3

## The 17 sprite objects of the screen: four pieces of the backdrop, which
## scrolls by, seven fixed things, of which two are the clock's digits and
## one names the car, and the car twice over in three parts (two pictures
## and one that is animated), as two cars are on screen while they slide.
const SPRITES := 0x1032D6
const SPRITE_COUNT := 17
const BACKDROP_PIECES := 4
const HIDDEN_FROM := 4
const FIXED_COUNT := 11
const DIGIT_SPRITES := 0x1032F6
const NAME_SPRITE := 0x1032FE
const LEFT_PARTS := 0x103302
const RIGHT_PARTS := 0x10330E
## Where the backdrop is (16.16), how far it moves a frame, and its pieces.
const BACKDROP_X := 0x10331A
const BACKDROP_SPEED := 0xAA7E
const BACKDROP_WRAP := 0x150
const BACKDROP_WIDTH := 0x1C0
const PIECE_WIDTH := 0x70
## Where the car's left edge is, and how far a slide to another car has to go.
const CAR_X := 0x10331E
const SLIDE_LEFT := 0x103320
const CAR_X_OFF_SCREEN := 0x14A
const CAR_X_SEEN_FROM := 0xD0
const CAR_X_AT_REST := 0x30
const SLIDE := 0x200
const SLIDE_SPEED := 0x20
## A slide shows the other car's right part until this much is left, and
## its left part until this much.
const SLIDE_RIGHT_PART := 0x160
const SLIDE_LEFT_PART := 0xF0
const BRIGHTNESS := 0x103322
## The clock: frames left, frames of the second left, and its two digits.
const FRAMES_LEFT := 0x103324
const FRAMES_OF_SECOND := 0x103326
const DIGITS := 0x103327
const FIRST_FRAMES_LEFT := 0x4B0
## The chosen car flashes: palettes to go, frames of this one, and which.
const FLASHES_LEFT := 0x103329
const FLASH_FRAMES := 0x10332A
const FLASH := 0x10332D
const FLASH_COUNT := 15
## Two flashes of two words: what to add to the palettes, and frames.
const FLASHES := 0x16666
## The car bobs: down a pixel or not, and frames until that changes.
const BOB := 0x10332B
const BOB_FRAMES := 0x10332E
## The animated part: which of four pictures, and frames left of it.
const PICTURE := 0x10332C
const PICTURE_FRAMES := 0x10332F
const STATE := 0x103330

## The pictures of the screen, by number, and the numbers of the digits
## and of the names (the fourth is shown during a slide).
const PICTURES := 0x80010
const DIGIT_PICTURES := 0x163AA
const NAME_PICTURES := 0x163EA
const NAME_SLIDING := 3
## The fixed sprites: four words each (picture, x, y, depth).
const FIXED := 0x16766
## The car's parts by car, also four words each: left and right, twice.
const LEFT_BODY := [0x167BE, 0x167EE]
const RIGHT_BODY := [0x167D6, 0x16806]
## The animated part, by car and picture: five words each (the fifth is
## for how many frames it shows).
const LEFT_ANIMATED := 0x1681E
const RIGHT_ANIMATED := 0x16896
## Its 14 palettes, from number $40.
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 14
const COLOURS := 0x15EBA
const FADE_IN_SPEED := 12
const FADE_OUT_SPEED := 8
const SOUND_MOVE := 0xC4
const SOUND_CHOSEN := 0xC5
const BUILD_SPRITES := 0x1229E
const CLEAR_SPRITES := 0x120E0
const CLEAR_TEXT := 0xA26

enum {FADING_IN, CAR_ARRIVING, CHOOSING, TO_PREVIOUS, TO_NEXT, CHOSEN, FADING_OUT, DONE}

## For a wider picture: six more sprite objects, for the car that leaves
## while another comes (the original needs none: it has one half of each
## on screen at a time at most).
var _leaving: Array[int] = []
## The car slid away from, or -1 for the original's: the one beside the
## car chosen (with the cars mods add, it may be the same car).
var _from_car := -1


func routines() -> Dictionary:
	return {
		0x15C16: forget_choice,
		0x15C20: set_up,
		0x15C9C: update,
		0x15CD6: fading_in,
		0x15CF0: car_arriving,
		0x15D0A: choosing,
		0x15D38: sliding.bind(1),
		0x15D60: sliding.bind(-1),
		0x15D88: chosen,
		0x15DA6: fading_out,
		0x15DC0: done,
		0x15DCA: take_sprites,
		0x15E02: free_sprites,
		0x15E22: fade_in,
		0x15E72: fade_out,
		0x15E9E: func() -> void: _fade(low16(m.d2)),
		0x1615A: set_up_joystick,
		0x16172: show_all,
		0x16196: set_up_sprites,
		0x161CC: slide_car_in,
		0x16224: read_joystick,
		0x162D4: scroll_backdrop,
		0x1632A: count_down,
		0x163BE: func() -> void: _show_name(low16(m.d0)),
		0x163F2: show_car,
		0x1640A: func() -> void: _show_left(low16(m.d0)),
		0x16444: func() -> void: _show_right(low16(m.d0)),
		0x16554: bob,
		0x16590: animate,
		0x165DA: next_flash,
		0x16620: flash,
		0x1666E: slide.bind(1),
		0x166E8: slide.bind(-1),
	}


func scratch() -> Dictionary:
	var table := {}
	for address: int in routines():
		table[address] = ["ccr"]
	table[0x15C20] = ["d0", "d1", "d2", "a0", "ccr"]
	table[0x15C9C] = ["a0", "ccr"]
	return table


func _picture(number: int) -> int:
	return m.r32(m.r32(PICTURES) + wrap16(number * 4))


func _sprite(index: int) -> int:
	return u32(SPRITES + index * 4)


## $15C16
func forget_choice() -> void:
	set16(CAR, 0)
	for car in CAR_COUNT:
		Mods.choose_car(m, car, 0)


## $15C20
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	_leaving.clear()
	_from_car = -1
	(sibling(Palettes) as Palettes).choose_shades(0)
	_fade(0)
	set32(BACKDROP_X, -(PIECE_WIDTH << 16))
	set16(FRAMES_LEFT, FIRST_FRAMES_LEFT)
	set8(FRAMES_OF_SECOND, 59)
	set8(DIGITS, 2)
	set8(DIGITS + 1, 0)
	set16(CAR_X, CAR_X_OFF_SCREEN)
	set8(FLASHES_LEFT, FLASH_COUNT)
	set8(FLASH_FRAMES, 0)
	set8(BOB, 0)
	set8(PICTURE, 0)
	set8(FLASH, 0)
	set8(BOB_FRAMES, 0)
	set8(PICTURE_FRAMES, 0)
	set8(STATE, FADING_IN)
	take_sprites()
	set_up_sprites()
	set_up_joystick()
	m.d2 = with_low16(m.d2, 0)
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0)


## $15C9C: a frame of the screen. Leaves 0 in D0 when it is over.
func update() -> void:
	match u8(STATE):
		FADING_IN: fading_in()
		CAR_ARRIVING: car_arriving()
		CHOOSING: choosing()
		TO_PREVIOUS: sliding(1)
		TO_NEXT: sliding(-1)
		CHOSEN: chosen()
		FADING_OUT: fading_out()
		DONE: done()
	if m.view_margin > 0:
		_widen()
	m.call_routine(BUILD_SPRITES)


## $15CD6
func fading_in() -> void:
	scroll_backdrop()
	show_car()
	fade_in()
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15CF0
func car_arriving() -> void:
	scroll_backdrop()
	slide_car_in()
	show_car()
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15D0A
func choosing() -> void:
	m.choosing_car = true
	set16(FRAMES_LEFT, u16(FRAMES_LEFT) - 1)
	scroll_backdrop()
	count_down()
	show_car()
	_show_name(u16(CAR))
	read_joystick()
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15D38 and $15D60: the cars slide by, to the right for the car before
## (`way` 1) and to the left for the one after (-1).
func sliding(way: int) -> void:
	set16(FRAMES_LEFT, u16(FRAMES_LEFT) - 1)
	scroll_backdrop()
	count_down()
	_show_name(NAME_SLIDING)
	slide(way)
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15D88
func chosen() -> void:
	scroll_backdrop()
	next_flash()
	flash()
	show_car()
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15DA6
func fading_out() -> void:
	scroll_backdrop()
	show_car()
	fade_out()
	bob()
	animate()
	m.d0 = with_low16(m.d0, 1)


## $15DC0
func done() -> void:
	free_sprites()
	m.d0 = with_low16(m.d0, 0)


## $15DCA
func take_sprites() -> void:
	for index in SPRITE_COUNT:
		set32(SPRITES + index * 4, Sprite.take_record(m))
	for index in range(HIDDEN_FROM, SPRITE_COUNT):
		Sprite.show(m, _sprite(index), false)


## $15E02
func free_sprites() -> void:
	for index in SPRITE_COUNT:
		Sprite.free_record(m, _sprite(index))
	for sprite in _leaving:
		Sprite.free_record(m, sprite)
		m.open_records.erase(sprite & 0xFFFF)
	_leaving.clear()
	for part in 6:
		m.open_records.erase(u32(LEFT_PARTS + part * 4) & 0xFFFF)


## $15E22
func fade_in() -> void:
	var brightness := (u16(BRIGHTNESS) + FADE_IN_SPEED) & 0xFFFF
	set16(BRIGHTNESS, brightness)
	if brightness >= 0x100:
		brightness = 0x100
		set8(STATE, CAR_ARRIVING)
		set16(BRIGHTNESS, brightness)
		for part in 3:
			Sprite.show(m, u32(LEFT_PARTS + part * 4), true)
	_fade(brightness)


## $15E72
func fade_out() -> void:
	var brightness := wrap16(u16(BRIGHTNESS) - FADE_OUT_SPEED)
	set16(BRIGHTNESS, brightness)
	if brightness <= 0:
		set8(STATE, DONE)
		brightness = 0
	_fade(brightness)


## $15E9E
func _fade(brightness: int) -> void:
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, brightness)
	m.d1 = with_low16(m.d1, PALETTE_COUNT)


## $1615A
func set_up_joystick() -> void:
	(sibling(Joystick) as Joystick).set_repeat(30, 15)


## $16172
func show_all() -> void:
	for index in SPRITE_COUNT:
		Sprite.show(m, _sprite(index), true)


## $16196
func set_up_sprites() -> void:
	for index in FIXED_COUNT:
		var entry := FIXED + index * 8
		var sprite := _sprite(index)
		Sprite.picture(m, sprite, _picture(m.r16(entry)))
		Sprite.place(m, sprite, m.r16(entry + 2), m.r16(entry + 4))
		set16(sprite + Sprite.DEPTH, m.r16(entry + 6))
	count_down()
	_show_name(u16(CAR))
	show_car()


## $161CC: the first car comes in from the right.
func slide_car_in() -> void:
	var x := (u16(CAR_X) - 8) & 0xFFFF
	set16(CAR_X, x)
	for part in 3:
		Sprite.show(m, u32(RIGHT_PARTS + part * 4), x <= CAR_X_SEEN_FROM)
	if x <= CAR_X_AT_REST:
		set16(CAR_X, CAR_X_AT_REST)
		set8(STATE, CHOOSING)
		show_all()


## $16224: left and right go to another car, button A settles for this
## one, and so does the clock.
func read_joystick() -> void:
	if s16(FRAMES_LEFT) > 0:
		var joystick := (sibling(Joystick) as Joystick).read()
		for way: int in [-1, 1]:
			if joystick & (Joystick.LEFT if way < 0 else Joystick.RIGHT):
				_request_sound(SOUND_MOVE)
				_to_choice(way)
				set16(SLIDE_LEFT, SLIDE)
				set8(STATE, TO_PREVIOUS if way < 0 else TO_NEXT)
				return
		if joystick & Joystick.BUTTON_A == 0:
			return
	_request_sound(SOUND_CHOSEN)
	set8(STATE, CHOSEN)


## The cars to choose from, in order, each [car, variant]: the game's
## three, each followed by those mods add in its place (Mods.CarVariant).
func _choices() -> Array:
	var choices := []
	for car in CAR_COUNT:
		for variant in m.car_variants.get(car, []).size() + 1:
			choices.append([car, variant])
	return choices


## Goes `way` along the cars: the one chosen becomes that one, and the one
## left, if another car of the game's, is itself again.
func _to_choice(way: int) -> void:
	var choices := _choices()
	var car := u16(CAR)
	var now := choices.find([car, m.chosen_variants.get(car, 0)])
	var next: Array = choices[posmod(now + way, choices.size())]
	if next[0] != car:
		Mods.choose_car(m, car, 0)
	Mods.choose_car(m, next[0], next[1])
	set16(CAR, next[0])
	_from_car = car


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


## $162D4
func scroll_backdrop() -> void:
	var x := wrap32(s32(BACKDROP_X) + BACKDROP_SPEED)
	if x >> 16 >= BACKDROP_WRAP:
		x -= BACKDROP_WIDTH << 16
	set32(BACKDROP_X, x)
	var across := wrap16(x >> 16)
	for piece in BACKDROP_PIECES:
		if across >= BACKDROP_WRAP:
			across -= BACKDROP_WIDTH
		Sprite.place(m, _sprite(piece), across, 0)
		across = wrap16(across + PIECE_WIDTH)


## $1632A: a frame of the clock, and its digits.
func count_down() -> void:
	if s16(FRAMES_LEFT) >= 0:
		var frames := s8(FRAMES_OF_SECOND) - 1
		if frames < 0:
			frames = 59
			var ones := s8(DIGITS + 1) - 1
			if ones < 0:
				ones = 9
				set8(DIGITS, maxi(s8(DIGITS) - 1, 0))
			set8(DIGITS + 1, ones)
		set8(FRAMES_OF_SECOND, frames)
	for digit in 2:
		Sprite.picture(m, u32(DIGIT_SPRITES + digit * 4), _picture(m.r16(DIGIT_PICTURES + u8(DIGITS + digit) * 2)))


## $163BE
func _show_name(car: int) -> void:
	Sprite.picture(m, u32(NAME_SPRITE), _picture(m.r16(NAME_PICTURES + wrap16(car * 2))))


## $163F2
func show_car() -> void:
	_show_left(u16(CAR))
	_show_right(u16(CAR))


## $1640A: the left parts are those of `car`.
func _show_left(car: int) -> void:
	_show_body(u32(LEFT_PARTS), LEFT_BODY[0], car)
	_show_body(u32(LEFT_PARTS + 4), LEFT_BODY[1], car)
	_show_animated(u32(LEFT_PARTS + 8), LEFT_ANIMATED, car)


## $16444
func _show_right(car: int) -> void:
	_show_body(u32(RIGHT_PARTS), RIGHT_BODY[0], car)
	_show_body(u32(RIGHT_PARTS + 4), RIGHT_BODY[1], car)
	_show_animated(u32(RIGHT_PARTS + 8), RIGHT_ANIMATED, car)


## $164B0
func _show_body(sprite: int, parts: int, car: int) -> void:
	_show_body_at(sprite, parts, car, u16(CAR_X))


func _show_body_at(sprite: int, parts: int, car: int, x: int) -> void:
	var entry := parts + wrap16(car << 3)
	Sprite.picture(m, sprite, _picture(m.r16(entry)))
	Sprite.place(m, sprite, x + m.r16(entry + 2), m.r16(entry + 4) - (1 if u8(BOB) != 0 else 0))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))


## $164FC
func _show_animated(sprite: int, parts: int, car: int) -> void:
	_show_animated_at(sprite, parts, car, u16(CAR_X))


func _show_animated_at(sprite: int, parts: int, car: int, x: int) -> void:
	var entry := parts + wrap16(car * 40) + u8(PICTURE) * 10
	Sprite.picture(m, sprite, _picture(m.r16(entry)))
	Sprite.place(m, sprite, x + m.r16(entry + 2), m.r16(entry + 4))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))


## The six sprites in `sprites` as all of `car`, its left edge at `x`.
func _show_whole_car(sprites: Array[int], car: int, x: int) -> void:
	_show_body_at(sprites[0], LEFT_BODY[0], car, x)
	_show_body_at(sprites[1], LEFT_BODY[1], car, x)
	_show_animated_at(sprites[2], LEFT_ANIMATED, car, x)
	_show_body_at(sprites[3], RIGHT_BODY[0], car, x)
	_show_body_at(sprites[4], RIGHT_BODY[1], car, x)
	_show_animated_at(sprites[5], RIGHT_ANIMATED, car, x)
	for sprite in sprites:
		Sprite.show(m, sprite, true)
		m.open_records[sprite & 0xFFFF] = true


## After a frame of the screen, for a wider picture: the cars are drawn
## wherever they are, not only within the original's 320 pixels. The
## original has a car come from just right of its picture, and has two
## slide by 512 pixels, which is where its hardware starts counting across
## again: the car that leaves on one side is the one that comes on the
## other. Here they come from the edge of the wider picture, and slide as
## much further as it is wider, in the same number of frames; the car that
## leaves has sprites of its own.
func _widen() -> void:
	var state := u8(STATE)
	if state == DONE:
		return
	var car_sprites: Array[int] = []
	for part in 6:
		car_sprites.append(u32(LEFT_PARTS + part * 4))
		m.open_records[car_sprites[part] & 0xFFFF] = true
	var sliding := state == TO_PREVIOUS or state == TO_NEXT
	if not sliding:
		for sprite in _leaving:
			Sprite.show(m, sprite, false)
	if state == CAR_ARRIVING:
		var way_to_go := CAR_X_OFF_SCREEN - CAR_X_AT_REST
		_show_whole_car(car_sprites, u16(CAR),
				CAR_X_AT_REST + (u16(CAR_X) - CAR_X_AT_REST) * (way_to_go + m.view_margin) / way_to_go)
	elif sliding:
		if _leaving.is_empty():
			for part in 6:
				_leaving.append(Sprite.take_record(m))
			if _leaving.has(0):
				# no records left: as the original has it
				_leaving.clear()
				return
		var way := 1 if state == TO_PREVIOUS else -1
		var slide_width := SLIDE + m.view_margin * 2
		var gone := (SLIDE - s16(SLIDE_LEFT)) * slide_width / SLIDE
		var car := u16(CAR)
		_show_whole_car(_leaving, _car_left(way), CAR_X_AT_REST + way * gone)
		_show_whole_car(car_sprites, car, CAR_X_AT_REST + way * (gone - slide_width))


## The car sliding out, `way` from the one chosen.
func _car_left(way: int) -> int:
	return _from_car if _from_car >= 0 else posmod(u16(CAR) + way, CAR_COUNT)


## $16554: every other frame the car is a pixel lower.
func bob() -> void:
	var frames := s8(BOB_FRAMES)
	if frames <= 0:
		set8(BOB, (u8(BOB) + 1) % 2)
		frames = 2
	set8(BOB_FRAMES, frames - 1)


## $16590
func animate() -> void:
	var frames := s8(PICTURE_FRAMES)
	if frames <= 0:
		var picture := (u8(PICTURE) + 1) & 0xFF
		if picture >= 4:
			picture = 0
		set8(PICTURE, picture)
		frames = m.r16(LEFT_ANIMATED + picture * 10 + 8)
	set8(PICTURE_FRAMES, frames - 1)


## $165DA
func next_flash() -> void:
	var frames := s8(FLASH_FRAMES)
	if frames <= 0:
		var which := (u8(FLASH) + 1) & 0xFF
		if which >= 2:
			which = 0
		set8(FLASH, which)
		frames = m.r16(FLASHES + which * 4 + 2)
	set8(FLASH_FRAMES, frames - 1)


## $16620
func flash() -> void:
	var left := (u8(FLASHES_LEFT) - 1) & 0xFF
	set8(FLASHES_LEFT, left)
	if left == 0:
		set8(STATE, FADING_OUT)
		return
	var palette := m.r16(FLASHES + u8(FLASH) * 4)
	for part in 6:
		set16(u32(LEFT_PARTS + part * 4) + Sprite.PALETTE, palette)


## $1666E and $166E8: a frame of the slide to another car. The car chosen
## is already the new one; the one sliding out is `way` from it.
func slide(way: int) -> void:
	var left := wrap16(u16(SLIDE_LEFT) - SLIDE_SPEED)
	set16(SLIDE_LEFT, left)
	set16(CAR_X, u16(CAR_X) + way * SLIDE_SPEED)
	if left <= 0:
		set16(CAR_X, CAR_X_AT_REST)
		set8(STATE, CHOOSING)
	var car := u16(CAR)
	var other := _car_left(way)
	if way > 0:
		_show_right(other if left >= SLIDE_RIGHT_PART else car)
		_show_left(other if left >= SLIDE_LEFT_PART else car)
	else:
		_show_left(other if left >= SLIDE_RIGHT_PART else car)
		_show_right(other if left >= SLIDE_LEFT_PART else car)
