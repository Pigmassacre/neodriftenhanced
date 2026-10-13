extends GameRoutines
## "Game over": it fades in over a picture of the course the game ended
## on, stays five seconds or until button A, and fades out.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Heap := preload("res://game/heap.gd")

const COURSE := 0x101202
const PLAYER := 0x1011FC
const PLAYER_1_PRESSED := 0x10FD97
const PLAYER_2_PRESSED := 0x10FD9D
const BUTTON_A := 0x10
## The address of its five sprite objects: the picture of the course, then
## the four parts of the writing.
const SPRITES := 0x103606
const SPRITE_COUNT := 5
const FRAMES := 0x10360A
const BRIGHTNESS := 0x10360C
const STATE := 0x10360E
enum {FADING_IN, SHOWN, FADING_OUT}
const FRAMES_BEFORE := 59
const FRAMES_SHOWN := 299
const FADE_SPEED := 4
## The pictures, and for each sprite four words: picture, x, y, depth. The
## picture of the course is the fifth, by course.
const PICTURES := 0x80020
const WRITING := 0x1E926
const COURSE_PICTURES := 0x1E946
## The palettes of the writing, which fade, and those of the course.
const WRITING_PALETTES := [0x40, 10, 0x1E63A]
const COURSE_PALETTES := [0x50, 5, 0x1E836]
const SOUND_04 := 0x04
const SOUND_07 := 0x07
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x1E39C: set_up,
		0x1E404: update,
		0x1E428: fading_in,
		0x1E47A: shown,
		0x1E4C0: fading_out,
		0x1E4EE: func() -> void: _take_list(low16(m.d0)),
		0x1E514: func() -> void: _take_sprites(low16(m.d0)),
		0x1E532: set_up_sprites,
		0x1E5BC: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade_in(low16(m.d2)) else 0),
		0x1E5EE: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade_out(low16(m.d2)) else 0),
		0x1E61E: func() -> void: _queue(WRITING_PALETTES, low16(m.d2)),
		0x1E81A: func() -> void: _queue(COURSE_PALETTES, low16(m.d2)),
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d7", "a0", "a3", "a5", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = ["ccr"]
	for address: int in [0x1E39C, 0x1E404, 0x1E428, 0x1E47A, 0x1E4C0]:
		table[address] = free
	return table


func _queue(palettes: Array, brightness: int) -> void:
	(sibling(Palettes) as Palettes).queue(palettes[0], palettes[1], palettes[2], brightness)


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _sprite(index: int) -> int:
	return u32(u32(SPRITES) + index * 4)


## $1E39C
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	(sibling(Palettes) as Palettes).choose_shades(1)
	_queue(WRITING_PALETTES, 0)
	_queue(COURSE_PALETTES, 0x100)
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	set16(STATE, FADING_IN)
	set16(BRIGHTNESS, 0)
	set16(FRAMES, FRAMES_BEFORE)
	_take_list(SPRITE_COUNT)
	_take_sprites(SPRITE_COUNT)
	set_up_sprites()
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0)


## $1E4EE
func _take_list(count: int) -> void:
	var heap := sibling(Heap) as Heap
	heap.reset()
	set32(SPRITES, 0)
	set32(SPRITES, heap.take(count * 4))


## $1E514
func _take_sprites(count: int) -> void:
	for index in count:
		set32(u32(SPRITES) + index * 4, Sprite.take_record(m))


## $1E532
func set_up_sprites() -> void:
	for index in SPRITE_COUNT - 1:
		_set_up_sprite(_sprite(index), WRITING + index * 8)
	_set_up_sprite(_sprite(SPRITE_COUNT - 1), COURSE_PICTURES + wrap16(u16(COURSE) << 3))
	for index in range(1, SPRITE_COUNT):
		Sprite.show(m, _sprite(index), false)


## $1E58A
func _set_up_sprite(sprite: int, entry: int) -> void:
	Sprite.picture(m, sprite, m.r32(m.r32(PICTURES) + wrap16(m.r16(entry) * 4)))
	Sprite.place(m, sprite, m.r16(entry + 2), m.r16(entry + 4))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))


## $1E404: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		FADING_IN: fading_in()
		SHOWN: shown()
		FADING_OUT: fading_out()
	m.call_routine(BUILD_SPRITES)


## $1E428
func fading_in() -> void:
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) < 0:
		set16(FRAMES, 0)
		for index in range(1, SPRITE_COUNT):
			Sprite.show(m, _sprite(index), true)
		if _fade_in(FADE_SPEED):
			set16(FRAMES, FRAMES_SHOWN)
			set16(STATE, SHOWN)
	m.d0 = with_low16(m.d0, 1)


## $1E47A
func shown() -> void:
	if u8(PLAYER_1_PRESSED if u16(PLAYER) == 0 else PLAYER_2_PRESSED) & BUTTON_A:
		set16(FRAMES, 0)
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) < 0:
		(sibling(Palettes) as Palettes).choose_shades(0)
		set16(STATE, FADING_OUT)
	m.d0 = with_low16(m.d0, 1)


## $1E4C0
func fading_out() -> void:
	if _fade_out(FADE_SPEED):
		m.call_routine(CLEAR_SPRITES)
		(sibling(Heap) as Heap).give_back(u32(SPRITES))
		m.d0 = with_low16(m.d0, 0)
	else:
		m.d0 = with_low16(m.d0, 1)


## $1E5BC: the writing a step brighter. Returns true once it is full.
func _fade_in(step: int) -> bool:
	var brightness := (u16(BRIGHTNESS) + step) & 0xFFFF
	var full := brightness >= 0x100
	if full:
		brightness = 0x100
	set16(BRIGHTNESS, brightness)
	_queue(WRITING_PALETTES, brightness)
	return full


## $1E5EE: everything a step darker. Returns true once it is black.
func _fade_out(step: int) -> bool:
	var brightness := wrap16(u16(BRIGHTNESS) - step)
	var black := brightness < 0
	if black:
		brightness = 0
	set16(BRIGHTNESS, brightness)
	_queue(WRITING_PALETTES, brightness)
	_queue(COURSE_PALETTES, brightness)
	return black
