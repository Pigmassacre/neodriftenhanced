extends GameRoutines
## The screen where a name of three characters is entered for the list of
## best times: up and down change the character, button A takes it, button
## B goes back, and after the third the choice is between "end" and "back".
## A clock counts a minute down.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")

const PLAYER := 0x1011FC
## The name as the rest of the game keeps it, in ordinary characters.
const PLAYER_NAME := 0x1011FE
## Its 14 sprite objects: four pieces of the backdrop, three fixed things,
## the three characters and the choice after them, the clock's label and
## its two digits.
const SPRITES := 0x1035B2
const SPRITE_COUNT := 14
const BACKDROP_PIECES := 4
const CHARACTER_SPRITES := 0x1035CE
const CHOICE_SPRITE := 0x1035DA
const TENS_SPRITE := 0x1035E2
const ONES_SPRITE := 0x1035E6
const FRAMES_LEFT := 0x1035EA
const FIRST_FRAMES_LEFT := 3659
const MOST_FRAMES_SHOWN := 0x1796
## The character being chosen blinks: frames until it changes, and 1 while
## it shows.
const BLINK_FRAMES := 0x1035EC
const BLINK := 0x1035EE
const BLINK_EVERY := 30
const STATE := 0x1035F0
enum {FADING_IN, ENTERING, SHOWING_NAME, WAITING, FADING_OUT, CLEARING, DONE}
const BRIGHTNESS := 0x1035F2
const FRAMES_AFTER := 0x1035F4
## The four places of the name, as numbers of characters: 0 to $29 are
## characters, then nothing yet, "end" and "back". The fourth place only
## holds one of the last two.
const NAME := 0x1035F6
const NOTHING_YET := 0x2A
const END := 0x2B
const BACK := 0x2C
const LAST_CHARACTER := 0x2C
const CHOICE_PLACE := 3
const PLACE := 0x1035FA
## The sound of this frame, or 0.
const SOUND := 0x1035FE
const SOUND_CHANGE := 0xC6
const SOUND_TAKE := 0xC7
## Where the backdrop is (16.16), and which of its two pictures comes
## first (0 or 4).
const BACKDROP_X := 0x103600
const BACKDROP_ORDER := 0x103604
const BACKDROP_SPEED := 0xAA7E
const BACKDROP_PERIOD := 0x700000
const BACKDROP_PICTURES := 0x1D290
const PIECE_PLACES: Array[int] = [0x190, 0, 0x70, 0xE0]
## The address of four addresses: the pictures of the fixed things, the
## characters as they are once taken, the characters while they are being
## chosen, and the clock's digits.
const PICTURES := 0x1D4D8
const TAKEN_FONT := 4
const CHOOSING_FONT := 8
const DIGITS := 0xC
## Where each sprite object is and its depth, and which picture each
## fixed one shows; both lists end with 0.
const PLACES := 0x1C996
const FIXED_PICTURES := 0x1CA26
## By second, the clock's two digits as two words.
const SECONDS_AS_DIGITS := 0x1D03E
## What each number of a character is as an ordinary character.
const CHARACTERS := 0x11550
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 11
const COLOURS := 0x1D298
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x11548: func() -> void: m.d0 = (m.d0 & 0xFFFFFF00) | m.r8(CHARACTERS + low16(m.d0)),
		0x1C876: set_up,
		0x1CA78: update,
		0x1CAF4: func() -> void: _state(waiting),
		0x1CB36: func() -> void: _state(fading_in),
		0x1CB7C: func() -> void: _state(showing_name),
		0x1CBF6: func() -> void: _state(fading_out),
		0x1CC44: func() -> void: _state(clearing),
		0x1CC60: func() -> void: _state(entering),
		0x1CE08: func() -> void: _handler(finish),
		0x1CE5A: func() -> void: _handler(go_back),
		0x1CEA4: func() -> void: _handler(take),
		0x1CEFA: func() -> void: _handler(change.bind(1)),
		0x1CF44: func() -> void: _handler(change.bind(-1)),
		0x1CF8C: func() -> void: _handler(nothing),
		0x1CF9A: blink,
		0x1CFD6: show_at_once,
		0x1CFE8: show_clock,
		0x1D1CE: scroll_backdrop,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "a0", "a1", "a2", "a3", "a4", "a5", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	table[0x11548] = ["ccr"]
	# these return nothing in D0; the handlers return in D4
	for address: int in [0x1CE08, 0x1CE5A, 0x1CEA4, 0x1CEFA, 0x1CF44, 0x1CF8C, 0x1CF9A, 0x1CFD6, 0x1CFE8, 0x1D1CE]:
		table[address] = ["d0", "d1", "d2", "d3", "a0", "a1", "a2", "a3", "a4", "a5", "ccr"]
	return table


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _state(state: Callable) -> void:
	m.d0 = with_low16(m.d0, 1 if state.call() else 0)


func _handler(handler: Callable) -> void:
	m.d4 = with_low16(m.d4, 1 if handler.call() else 0)


func _fade(brightness: int) -> void:
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, brightness)


func _character_sprite(place: int) -> int:
	return u32(CHARACTER_SPRITES + place * 4)


## $1C876
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	(sibling(Palettes) as Palettes).choose_shades(0)
	_fade(0)
	for index in SPRITE_COUNT:
		set32(SPRITES + index * 4, Sprite.take_record(m))
	var entry := PLACES
	while m.r32(entry) != 0:
		var sprite := u32(m.r32(entry))
		Sprite.place(m, sprite, m.r16(entry + 4), m.r16(entry + 6))
		if m.r16(entry + 8) != 0:
			set16(sprite + Sprite.DEPTH, m.r16(entry + 8))
		entry += 10
	Sprite.show(m, u32(CHOICE_SPRITE), false)
	var fixed := m.r32(m.r32(PICTURES))
	entry = FIXED_PICTURES
	while m.r32(entry) != 0:
		Sprite.picture(m, u32(m.r32(entry)), m.r32(fixed + m.r16(entry + 4)))
		entry += 6
	(sibling(Joystick) as Joystick).set_each_repeat(30, 5)
	set8(NAME, 0)
	set8(NAME + 1, NOTHING_YET)
	set8(NAME + 2, NOTHING_YET)
	set8(NAME + 3, END)
	set16(PLACE, 0)
	set16(FRAMES_LEFT, FIRST_FRAMES_LEFT)
	set16(BLINK_FRAMES, BLINK_EVERY)
	set16(BLINK, 1)
	set16(STATE, FADING_IN)
	set16(BRIGHTNESS, 0)
	set16(FRAMES_AFTER, 120)
	set16(SOUND, 0)
	set16(BACKDROP_X, 0)
	set16(BACKDROP_ORDER, 0)
	m.d0 = with_low16(m.d0, 0)


## $1CA78: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	var going_on := true
	match u16(STATE):
		FADING_IN: going_on = fading_in()
		ENTERING: going_on = entering()
		SHOWING_NAME: going_on = showing_name()
		WAITING: going_on = waiting()
		FADING_OUT: going_on = fading_out()
		CLEARING: going_on = clearing()
		_:
			m.call_routine(BUILD_SPRITES)
			m.d0 = with_low16(m.d0, 0)
			return
	if not going_on:
		set16(STATE, u16(STATE) + 1)
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 1)


## $1D1CE: the backdrop moves by; its two pictures alternate.
func scroll_backdrop() -> void:
	var x := (u32(BACKDROP_X) + BACKDROP_SPEED) & 0xFFFFFFFF
	if x >= BACKDROP_PERIOD:
		x -= BACKDROP_PERIOD
		set16(BACKDROP_ORDER, u16(BACKDROP_ORDER) ^ 4)
	set32(BACKDROP_X, x)
	var order := u16(BACKDROP_ORDER)
	for piece in BACKDROP_PIECES:
		var sprite := u32(SPRITES + piece * 4)
		Sprite.place(m, sprite, (x >> 16) + PIECE_PLACES[piece], 0)
		Sprite.picture(m, sprite, m.r32(BACKDROP_PICTURES + wrap16(order ^ (4 if piece & 1 else 0))))


## $1CB36
func fading_in() -> bool:
	scroll_backdrop()
	var brightness := (u16(BRIGHTNESS) + 0x15) & 0xFFFF
	var going_on := brightness <= 0x100
	if not going_on:
		brightness = 0x100
	set16(BRIGHTNESS, brightness)
	_fade(brightness)
	return going_on


## $1CBF6
func fading_out() -> bool:
	scroll_backdrop()
	var brightness := wrap16(u16(BRIGHTNESS) - 0xF)
	var going_on := brightness >= 0
	if not going_on:
		brightness = 0
	set16(BRIGHTNESS, brightness)
	_fade(brightness)
	set16(BRIGHTNESS, brightness - 0xF)
	return going_on


## $1CAF4: the name stays for two seconds, or until button A.
func waiting() -> bool:
	scroll_backdrop()
	if (sibling(Joystick) as Joystick).pressed(u16(PLAYER), Joystick.BUTTON_A):
		set16(FRAMES_AFTER, 1)
		_request_sound(SOUND_TAKE)
	set16(FRAMES_AFTER, u16(FRAMES_AFTER) - 1)
	return s16(FRAMES_AFTER) > 0


## $1CC44
func clearing() -> bool:
	for index in SPRITE_COUNT:
		Sprite.free_record(m, u32(SPRITES + index * 4))
	return false


## $1CB7C: the name as it was entered, without what came after it.
func showing_name() -> bool:
	scroll_backdrop()
	var place := s16(PLACE)
	var taken := m.r32(m.r32(PICTURES) + TAKEN_FONT)
	for index in range(3, -1, -1):
		var sprite := _character_sprite(index)
		if index == place - 1:
			Sprite.picture(m, sprite, m.r32(taken + u8(NAME + index) * 4))
		Sprite.show(m, sprite, index < place)
	return false


## $1CC60: a frame of entering the name.
func entering() -> bool:
	scroll_backdrop()
	set16(FRAMES_LEFT, u16(FRAMES_LEFT) - 1)
	var joystick := sibling(Joystick) as Joystick
	var going_on := true
	var place := u16(PLACE)
	var chosen := u8(NAME + wrap16(place))
	if s16(FRAMES_LEFT) <= 0:
		# out of time: the character showing is taken
		if chosen != END and chosen != BACK:
			set16(PLACE, place + 1)
		going_on = finish()
	elif joystick.pressed(u16(PLAYER), Joystick.BUTTON_A):
		if chosen == END:
			going_on = finish()
		elif chosen == BACK:
			going_on = go_back()
		else:
			going_on = take()
	elif joystick.pressed(u16(PLAYER), Joystick.BUTTON_B):
		going_on = go_back()
	else:
		var directions := joystick.read_each()
		if directions & (Joystick.LEFT | Joystick.RIGHT):
			show_at_once()
			going_on = change(-1 if directions & Joystick.LEFT else 1)
		else:
			going_on = nothing()
	if u16(SOUND) != 0:
		_request_sound(u16(SOUND))
	if not going_on:
		return false
	_show_name()
	show_clock()
	return true


## The characters so far, the one being chosen in its own font, and the
## choice after the third.
func _show_name() -> void:
	var pictures := m.r32(PICTURES)
	var last := 2
	if u16(PLACE) == CHOICE_PLACE:
		Sprite.show(m, u32(CHOICE_SPRITE), true)
		last = CHOICE_PLACE
	else:
		Sprite.show(m, u32(CHOICE_SPRITE), false)
	for index in range(last, -1, -1):
		var font := TAKEN_FONT
		if index == u16(PLACE):
			blink()
			font = CHOOSING_FONT
		Sprite.picture(m, _character_sprite(index), m.r32(m.r32(pictures + font) + u8(NAME + index) * 4))


## $1CE08: the name is done: what was not entered is left out, and the
## rest of the game gets it in ordinary characters.
func finish() -> bool:
	set16(FRAMES_LEFT, 0)
	var place := u16(PLACE)
	while place <= 3:
		set8(NAME + place, END)
		place += 1
	for index in 4:
		set8(PLAYER_NAME + index, m.r8(CHARACTERS + u8(NAME + index)))
	set16(SOUND, SOUND_TAKE)
	return false


## $1CE5A: back to the character before.
func go_back() -> bool:
	var place := u16(PLACE)
	if place != 0:
		Sprite.show(m, _character_sprite(place), true)
		set8(NAME + place, NOTHING_YET)
		set16(PLACE, place - 1)
		set16(SOUND, SOUND_CHANGE)
	return true


## $1CEA4: takes the character and goes on to the next.
func take() -> bool:
	var place := u16(PLACE)
	Sprite.show(m, _character_sprite(place), true)
	place += 1
	set8(NAME + place, END if place == CHOICE_PLACE else 0)
	set16(PLACE, place)
	set16(SOUND, SOUND_TAKE)
	return true


## $1CEFA and $1CF44: the next character (`step` 1) or the one before (-1),
## round and round; in the fourth place, the other of "end" and "back".
func change(step: int) -> bool:
	var place := u16(PLACE)
	var chosen := u8(NAME + place)
	if place >= CHOICE_PLACE:
		chosen = ((chosen - END) ^ 1) + END
	elif step > 0:
		chosen = 0 if chosen >= LAST_CHARACTER else chosen + 1
	else:
		chosen = LAST_CHARACTER if chosen == 0 else chosen - 1
	set8(NAME + place, chosen)
	set16(SOUND, SOUND_CHANGE)
	return true


## $1CF8C
func nothing() -> bool:
	set16(SOUND, 0)
	return true


## $1CFD6: a character just changed shows at once.
func show_at_once() -> void:
	set16(BLINK_FRAMES, BLINK_EVERY)
	set16(BLINK, 1)


## $1CF9A
func blink() -> void:
	set16(BLINK_FRAMES, u16(BLINK_FRAMES) - 1)
	if s16(BLINK_FRAMES) <= 0:
		set16(BLINK, u16(BLINK) ^ 1)
		set16(BLINK_FRAMES, BLINK_EVERY)
	set16(_character_sprite(u16(PLACE)) + Sprite.SHOWN, 2 - u16(BLINK))


## $1CFE8: the seconds left.
func show_clock() -> void:
	var digits := m.r32(m.r32(PICTURES) + DIGITS)
	var frames := u16(FRAMES_LEFT)
	if s16(FRAMES_LEFT) > MOST_FRAMES_SHOWN:
		frames = MOST_FRAMES_SHOWN
	var entry := SECONDS_AS_DIGITS + (frames / 60) * 4
	Sprite.picture(m, u32(ONES_SPRITE), m.r32(digits + wrap16(m.r16(entry + 2) * 4)))
	Sprite.picture(m, u32(TENS_SPRITE), m.r32(digits + wrap16(m.r16(entry) * 4)))
