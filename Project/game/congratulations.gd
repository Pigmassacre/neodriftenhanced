extends GameRoutines
## The picture shown after the ending: the car the game was driven with,
## under a line of writing that blinks.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")

const CHOSEN_CAR := 0x1011FA
const SPRITES := 0x1011B0
const BLINK := 0x1011C4
const STATE := 0x1011C6
enum {SOUND, FADING_IN, SHOWN, STILL_SHOWN, FADING_OUT, WAITING, DONE}
const BRIGHTNESS := 0x1011C8
const FRAMES_OF_STATE := 0x1011CA
const FRAMES_TO_WAIT := 0x1011CC
const FRAMES_SHOWN := 130
const FRAMES_WAITED := 120
## The address of its pictures: two backdrops, a strip, the three cars,
## and the writing lit and unlit.
const PICTURES := 0x8BE8
const CAR_PICTURES := 3
const WRITING_PICTURES := 6
## Where each of the five sprite objects is and its depth.
const PLACES := [[0, 0, 0], [0, 0, 0xFFFF], [0, 0xA0, 3], [0x80, 0x80, 1], [0x80, 0x60, 2]]
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 17
const COLOURS := 0x8888
const SOUND_2C := 0x2C
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x84DE: set_up,
		0x8628: update,
		0x865E: waiting,
		0x86AC: sound,
		0x86C6: fading_in,
		0x86E6: shown,
		0x870C: fading_out,
		0x872C: func() -> void: m.d0 = with_low16(m.d0, 0),
		0x8732: func() -> void: m.d0 = with_low16(m.d0, 1 if _wait() else 0),
		0x8758: func() -> void:
			_request_sound(SOUND_2C)
			m.d0 = with_low16(m.d0, 0),
		0x8778: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade(8) else 0),
		0x87C4: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade(-4) else 0),
		0x8810: blink,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "a0", "a1", "a3", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	return table


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _picture(number: int) -> int:
	return m.r32(m.r32(PICTURES) + wrap16(number * 4))


## $84DE
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	var palettes := sibling(Palettes) as Palettes
	palettes.choose_shades(1)
	palettes.queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, 0)
	var pictures: Array[int] = [0, 1, 2, CAR_PICTURES + u16(CHOSEN_CAR), WRITING_PICTURES]
	for index in 5:
		set32(SPRITES + index * 4, Sprite.take_record(m))
	for index in 5:
		var sprite := u32(SPRITES + index * 4)
		Sprite.place(m, sprite, PLACES[index][0], PLACES[index][1])
		set16(sprite + Sprite.DEPTH, PLACES[index][2])
		Sprite.picture(m, sprite, _picture(pictures[index]))
	set16(BLINK, 0)
	set16(STATE, SOUND)
	set16(BRIGHTNESS, 0)
	set16(FRAMES_OF_STATE, FRAMES_SHOWN)
	set16(FRAMES_TO_WAIT, FRAMES_WAITED)
	m.d0 = with_low16(m.d0, 0)


## $8628: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		SOUND: sound()
		FADING_IN: fading_in()
		SHOWN, STILL_SHOWN: shown()
		FADING_OUT: fading_out()
		WAITING: waiting()
		DONE: m.d0 = with_low16(m.d0, 0)


func _next_state() -> void:
	set16(STATE, u16(STATE) + 1)


## $86AC
func sound() -> void:
	_request_sound(SOUND_2C)
	_next_state()
	m.d0 = with_low16(m.d0, 1)


## $86C6
func fading_in() -> void:
	blink()
	if not _fade(8):
		_next_state()
	m.d0 = with_low16(m.d0, 1)


## $86E6
func shown() -> void:
	blink()
	set16(FRAMES_OF_STATE, u16(FRAMES_OF_STATE) - 1)
	if s16(FRAMES_OF_STATE) <= 0:
		_next_state()
		set16(FRAMES_OF_STATE, FRAMES_SHOWN)


## $870C
func fading_out() -> void:
	blink()
	if not _fade(-4):
		_next_state()
	m.d0 = with_low16(m.d0, 1)


## $865E
func waiting() -> void:
	if not _wait():
		_next_state()
	m.d0 = with_low16(m.d0, 1)


## $8732
func _wait() -> bool:
	set16(FRAMES_TO_WAIT, u16(FRAMES_TO_WAIT) - 1)
	return s16(FRAMES_TO_WAIT) > 0


## $8778 and $87C4: a step brighter or darker. Returns false at the end.
func _fade(step: int) -> bool:
	var brightness := u16(BRIGHTNESS) + step
	if step > 0:
		brightness = mini(wrap16(brightness), 0x100)
	elif brightness & 0xFFFF == 0:
		brightness = 0
	set16(BRIGHTNESS, brightness)
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, wrap16(brightness))
	brightness &= 0xFFFF
	return brightness < 0x100 if step > 0 else brightness > 0


## $8810: the writing is lit for half of every 64 frames.
func blink() -> void:
	var count := (u16(BLINK) + 1) & 0x3F
	set16(BLINK, count)
	Sprite.picture(m, u32(SPRITES + 16), _picture(WRITING_PICTURES + (1 if count < 30 else 0)))
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 1)
