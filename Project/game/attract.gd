extends GameRoutines
## What the machine shows while nobody plays: two logos, how to play, the
## title, a race driven by a recording, and the best times; then round
## again. A game starting ends it at once.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Heap := preload("res://game/heap.gd")
const Text := preload("res://game/text.gd")

## Not 0 once a game is to start.
const GAME_STARTS := 0x10041A
## The address of its sprite objects, kept in memory asked for.
const SPRITES := 0x10046E
## The address of its timings, which differ by the kind of machine.
const TIMINGS := 0x100472
const TIMINGS_BY_MACHINE := 0x240E
const MACHINE_KIND := 0x10042A
## A set of timings: how fast each of the two logos fades in and out and
## the title fades in (twice, for two sets of palettes), frames each logo
## waits before and after it is shown, frames the title stays, frames
## before its emblem arrives, before its writing shows and before each of
## two voices, and how fast its backdrop rises (16.16).
const LOGO_FADES := 0x00
const TITLE_FADE := 0x08
const WRITING_FADE := 0x0A
const FIRST_WAIT := 0x0C
const LOGO_WAITS := 0x0E
const TITLE_FRAMES := 0x14
const EMBLEM_WAIT := 0x16
const WRITING_WAIT := 0x18
const VOICE_WAITS := 0x1A
const BACKDROP_SPEED := 0x1E
## How far the title's backdrop has risen (16.16).
const BACKDROP_RISEN := 0x100476
const FRAMES := 0x10047A
const BRIGHTNESS := 0x10047C
const WRITING_BRIGHTNESS := 0x10047E
## The step of the emblem's flight, and frames until it and until the
## writing and the voices.
const EMBLEM_STEP := 0x100480
const EMBLEM_FRAMES := 0x100482
const WRITING_FRAMES := 0x100484
const VOICE_FRAMES := 0x100486
const STATE := 0x10048A
enum {LOGO_IN, LOGO_OUT, SET_UP_SECOND_LOGO, SECOND_LOGO_IN, SECOND_LOGO_OUT, SET_UP_HOW_TO_PLAY, HOW_TO_PLAY,
		SET_UP_TITLE, TITLE, SET_UP_RACE, RACE, SET_UP_BEST_TIMES, BEST_TIMES, DONE}
## Which course the race is on; the next time round it is the next.
const RACE_COURSE := 0x10036E
const COURSE := 0x101202
const LAST_COURSE := 6
## The address of its pictures, and for each sprite object four words:
## picture, x, y, depth.
const PICTURES := 0x8002C
const LOGO := 0x3408
const SECOND_LOGO := 0x3410
const TITLE_SPRITES := 0x3418
## The title's backdrop, drawn as ground: where its map and its tiles are
## kept among the pictures.
const BACKDROP_MAP := 0x18
const BACKDROP_TILES := 0x24
## The emblem's flight: 240 steps of x, of y and of zoom.
const EMBLEM_X := 0x2A14
const EMBLEM_Y := 0x2BF4
const EMBLEM_ZOOM := 0x2DD4
const EMBLEM_LAST_STEP := 0xEF
## The two lines under the title and where they are written.
const LINES: Array[int] = [0x3438, 0x344C]
const LINE_CELLS: Array[int] = [0x7219, 0x721A]
const VOICES: Array[int] = [0x184C, 0x184D]
## Its 16 palettes, and the two of the title's writing.
const PALETTES := [0x40, 0x10, 0x308C]
const WRITING_PALETTES := [0x50, 2, 0x33A8]
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E
const GROUND_OFF := 0x133FA
const REDRAW_GROUND := 0x1348E
const SCROLL_GROUND := 0x13546
const GROUND_CAMERA := 0x102534
const SET_UP_HOW_TO_PLAY_SCREEN := 0x3462
const HOW_TO_PLAY_SCREEN := 0x34D8
const SET_DEMO_PLAYING := 0xD704
const SET_UP_DEMO_RACE := 0x1C77A
const DEMO_RACE := 0x1C788
const SET_UP_BEST_TIMES_SCREEN := 0x5B96
const BEST_TIMES_SCREEN := 0x5BDA


func routines() -> Dictionary:
	return {
		0x2336: set_up,
		0x2416: update,
		0x2488: logo_in.bind(0),
		0x24CA: logo_out.bind(0),
		0x2508: set_up_second_logo,
		0x2558: logo_in.bind(1),
		0x259A: logo_out.bind(1),
		0x25D8: func() -> void: _run(SET_UP_HOW_TO_PLAY_SCREEN, HOW_TO_PLAY),
		0x25F4: func() -> void: _run(HOW_TO_PLAY_SCREEN, SET_UP_TITLE),
		0x2610: set_up_title,
		0x26B8: title,
		0x27F6: set_up_race,
		0x284E: func() -> void: _run(DEMO_RACE, SET_UP_BEST_TIMES),
		0x286A: set_up_best_times,
		0x288C: func() -> void: _run(BEST_TIMES_SCREEN, DONE),
		0x28A8: done,
		0x28C6: func() -> void: _take_list(low16(m.d0)),
		0x28EC: func() -> void: _take_sprites(low16(m.d0)),
		0x2928: func() -> void:
			_set_up_sprite(m.a0, m.a6)
			m.a6 += 8,
		0x295A: func() -> void: m.d1 = with_low16(m.d1, 1 if _raise_backdrop() else 0),
		0x29B6: fly_emblem,
		0x2FB4: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade_in(low16(m.d2)) else 0),
		0x2FE6: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade_writing_in(low16(m.d2)) else 0),
		0x3018: func() -> void: m.d0 = with_low16(m.d0, 1 if _fade_out(low16(m.d2)) else 0),
		0x3070: func() -> void: _queue(PALETTES, low16(m.d2)),
		0x338C: func() -> void: _queue(WRITING_PALETTES, low16(m.d2)),
		0x1352A: func() -> void:
			set16(GROUND_CAMERA, m.d0)
			set16(GROUND_CAMERA + 2, m.d2),
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d7", "a0", "a1", "a3", "a4", "a5", "a6", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	for address: int in [0x28C6, 0x28EC, 0x2928, 0x295A, 0x29B6, 0x2FB4, 0x2FE6, 0x3018, 0x3070, 0x338C, 0x1352A]:
		table[address] = ["ccr"]
	return table


func _queue(palettes: Array, brightness: int) -> void:
	(sibling(Palettes) as Palettes).queue(palettes[0], palettes[1], palettes[2], brightness)


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


func _sprite(index: int) -> int:
	return u32(u32(SPRITES) + index * 4)


func _timing(which: int) -> int:
	return m.r16(u32(TIMINGS) + which)


## Calls `routine`; once it says it is over, the state is `next`.
func _run(routine: int, next: int) -> void:
	m.call_routine(routine)
	if low16(m.d0) == 0:
		set16(STATE, next)
	m.d0 = with_low16(m.d0, 1)


## $28C6 and $28EC
func _take_list(count: int) -> void:
	var heap := sibling(Heap) as Heap
	heap.reset()
	set32(SPRITES, 0)
	set32(SPRITES, heap.take(count * 4))


func _take_sprites(count: int) -> void:
	for index in count:
		set32(u32(SPRITES) + index * 4, Sprite.take_record(m))


func _clear_away() -> void:
	m.call_routine(CLEAR_SPRITES)
	(sibling(Heap) as Heap).give_back(u32(SPRITES))


## $2928
func _set_up_sprite(sprite: int, entry: int) -> void:
	Sprite.picture(m, sprite, m.r32(m.r32(PICTURES) + wrap16(m.r16(entry) * 4)))
	Sprite.place(m, sprite, m.r16(entry + 2), m.r16(entry + 4))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))


## $2FB4, $3018 and $2FE6: a step brighter or darker. Each returns true at
## its end.
func _fade_in(step: int) -> bool:
	var brightness := (u16(BRIGHTNESS) + step) & 0xFFFF
	var full := brightness >= 0x100
	set16(BRIGHTNESS, 0x100 if full else brightness)
	_queue(PALETTES, u16(BRIGHTNESS))
	return full


func _fade_out(step: int) -> bool:
	var brightness := wrap16(u16(BRIGHTNESS) - step)
	var black := brightness < 0
	set16(BRIGHTNESS, 0 if black else brightness)
	_queue(PALETTES, u16(BRIGHTNESS))
	return black


func _fade_writing_in(step: int) -> bool:
	var brightness := (u16(WRITING_BRIGHTNESS) + step) & 0xFFFF
	var full := brightness >= 0x100
	set16(WRITING_BRIGHTNESS, 0x100 if full else brightness)
	_queue(WRITING_PALETTES, u16(WRITING_BRIGHTNESS))
	return full


## $2336
func set_up() -> void:
	if u16(GAME_STARTS) != 0:
		m.d0 = with_low16(m.d0, 0)
		return
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	(sibling(Palettes) as Palettes).choose_shades(0)
	_queue(PALETTES, 0)
	set32(TIMINGS, m.r32(TIMINGS_BY_MACHINE + wrap16(u16(MACHINE_KIND) * 4)))
	set16(STATE, LOGO_IN)
	set16(BRIGHTNESS, 0)
	set16(EMBLEM_STEP, 0)
	set32(BACKDROP_RISEN, 0x600000)
	set16(EMBLEM_FRAMES, _timing(EMBLEM_WAIT))
	set16(WRITING_FRAMES, _timing(WRITING_WAIT))
	set16(FRAMES, _timing(FIRST_WAIT))
	set16(VOICE_FRAMES, _timing(VOICE_WAITS))
	set16(VOICE_FRAMES + 2, _timing(VOICE_WAITS + 2))
	if u16(RACE_COURSE) > 5 and s16(RACE_COURSE) < 0:
		set16(RACE_COURSE, 0)
	_take_list(1)
	_take_sprites(1)
	_set_up_sprite(_sprite(0), LOGO)
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0)


## $2416: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	if u16(GAME_STARTS) != 0:
		m.call_routine(CLEAR_SPRITES)
		m.call_routine(GROUND_OFF)
		(sibling(Heap) as Heap).give_back(u32(SPRITES))
		m.d0 = with_low16(m.d0, 0)
		return
	match u16(STATE):
		LOGO_IN: logo_in(0)
		LOGO_OUT: logo_out(0)
		SET_UP_SECOND_LOGO: set_up_second_logo()
		SECOND_LOGO_IN: logo_in(1)
		SECOND_LOGO_OUT: logo_out(1)
		SET_UP_HOW_TO_PLAY: _run(SET_UP_HOW_TO_PLAY_SCREEN, HOW_TO_PLAY)
		HOW_TO_PLAY: _run(HOW_TO_PLAY_SCREEN, SET_UP_TITLE)
		SET_UP_TITLE: set_up_title()
		TITLE: title()
		SET_UP_RACE: set_up_race()
		RACE: _run(DEMO_RACE, SET_UP_BEST_TIMES)
		SET_UP_BEST_TIMES: set_up_best_times()
		BEST_TIMES: _run(BEST_TIMES_SCREEN, DONE)
		DONE: done()


## $2488 and $2558: a logo fades in and then waits.
func logo_in(logo: int) -> void:
	if _fade_in(_timing(LOGO_FADES + logo * 4)):
		set16(FRAMES, u16(FRAMES) - 1)
		if s16(FRAMES) < 0:
			set16(FRAMES, _timing(LOGO_WAITS + logo * 4))
			(sibling(Palettes) as Palettes).choose_shades(0)
			set16(STATE, LOGO_OUT if logo == 0 else SECOND_LOGO_OUT)
	m.d0 = with_low16(m.d0, 1)


## $24CA and $259A: it fades out, and after a wait is gone.
func logo_out(logo: int) -> void:
	if _fade_out(_timing(LOGO_FADES + logo * 4 + 2)):
		set16(FRAMES, u16(FRAMES) - 1)
		if s16(FRAMES) < 0:
			_clear_away()
			set16(STATE, SET_UP_SECOND_LOGO if logo == 0 else SET_UP_HOW_TO_PLAY)
	m.d0 = with_low16(m.d0, 1)


## $2508
func set_up_second_logo() -> void:
	(sibling(Palettes) as Palettes).choose_shades(0)
	_queue(PALETTES, 0)
	_take_list(1)
	_take_sprites(1)
	_set_up_sprite(_sprite(0), SECOND_LOGO)
	set16(FRAMES, _timing(LOGO_WAITS + 2))
	set16(STATE, SECOND_LOGO_IN)
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 1)


## $2610: the title: the emblem, the backdrop twice (as ground, and as a
## sprite object above it), and two things of the writing.
func set_up_title() -> void:
	(sibling(Palettes) as Palettes).choose_shades(0)
	_queue(PALETTES, 0)
	_queue(WRITING_PALETTES, 0)
	_take_list(4)
	_take_sprites(4)
	m.a4 = m.r32(PICTURES) + BACKDROP_MAP
	m.a5 = m.r32(PICTURES) + BACKDROP_TILES
	m.d0 = with_low16(m.d0, 0x10)
	m.d1 = with_low16(m.d1, 0x60)
	m.d2 = with_low16(m.d2, 0x100)
	m.d3 = with_low16(m.d3, 0x100)
	m.call_routine(REDRAW_GROUND)
	for index in 4:
		_set_up_sprite(_sprite(index), TITLE_SPRITES + index * 8)
		if index != 1:
			Sprite.show(m, _sprite(index), false)
	set16(FRAMES, _timing(TITLE_FRAMES))
	set16(STATE, TITLE)
	m.d0 = with_low16(m.d0, 1)


## $26B8: the backdrop rises while the emblem flies in; then the writing
## shows with two voices, and the title stays a while.
func title() -> void:
	_fade_in(_timing(TITLE_FADE))
	if _raise_backdrop():
		set16(FRAMES, u16(FRAMES) - 1)
		if s16(FRAMES) < 0:
			m.call_routine(CLEAR_TEXT)
			m.call_routine(GROUND_OFF)
			_clear_away()
			set16(STATE, SET_UP_RACE)
	else:
		set16(EMBLEM_FRAMES, u16(EMBLEM_FRAMES) - 1)
		if s16(EMBLEM_FRAMES) < 0:
			set16(EMBLEM_FRAMES, 0)
			Sprite.show(m, _sprite(0), true)
			fly_emblem()
		set16(WRITING_FRAMES, u16(WRITING_FRAMES) - 1)
		if s16(WRITING_FRAMES) < 0:
			_show_writing()
	m.call_routine(BUILD_SPRITES)
	m.call_routine(SCROLL_GROUND)
	m.d0 = with_low16(m.d0, 1)


func _show_writing() -> void:
	for voice in 2:
		var frames := VOICE_FRAMES + voice * 2
		set16(frames, u16(frames) - 1)
		if s16(frames) == 0:
			_request_sound(VOICES[voice])
		if s16(frames) <= 0:
			set16(frames, 0)
	set16(WRITING_FRAMES, 0)
	for line in 2:
		var characters := PackedByteArray()
		var at := LINES[line]
		while m.r8(at) != 0:
			characters.append(m.r8(at))
			at += 1
		Text.write(m, characters, LINE_CELLS[line], 9, 0x300)
	m.set_sr(m.get_sr() & 0xF8FF)
	Sprite.show(m, _sprite(2), true)
	Sprite.show(m, _sprite(3), true)
	(sibling(Palettes) as Palettes).choose_shades(1)
	_fade_writing_in(_timing(WRITING_FADE))


## $295A: the backdrop rises a step. Returns true once it is all the way up.
func _raise_backdrop() -> bool:
	var risen := (u32(BACKDROP_RISEN) + m.r32(u32(TIMINGS) + BACKDROP_SPEED)) & 0xFFFFFFFF
	var up := (risen >> 16) > 0x100
	if up:
		risen = (0x100 << 16) | (risen & 0xFFFF)
	set16(GROUND_CAMERA, 0x10)
	set16(GROUND_CAMERA + 2, risen >> 16)
	set32(BACKDROP_RISEN, risen)
	Sprite.place(m, _sprite(1), 0, 0x100 - (risen >> 16))
	return up


## $29B6: a step of the emblem's flight.
func fly_emblem() -> void:
	var step := u16(EMBLEM_STEP)
	if step > EMBLEM_LAST_STEP:
		step = EMBLEM_LAST_STEP
		set16(EMBLEM_STEP, step)
	var emblem := _sprite(0)
	Sprite.place(m, emblem, m.r16(EMBLEM_X + step * 2), m.r16(EMBLEM_Y + step * 2))
	var zoom := m.r16(EMBLEM_ZOOM + step * 2)
	Sprite.zoom(m, emblem, zoom, zoom)
	set16(EMBLEM_STEP, u16(EMBLEM_STEP) + 1)


## $27F6: the race is on the course after the one shown last time.
func set_up_race() -> void:
	if s16(RACE_COURSE) < 0:
		set16(RACE_COURSE, 0)
	set16(RACE_COURSE, u16(RACE_COURSE) + 1)
	if s16(RACE_COURSE) > LAST_COURSE:
		set16(RACE_COURSE, 1)
	set16(COURSE, u16(RACE_COURSE))
	m.d0 = with_low16(m.d0, 1)
	m.call_routine(SET_DEMO_PLAYING)
	_run(SET_UP_DEMO_RACE, RACE)


## $286A
func set_up_best_times() -> void:
	m.call_routine(CLEAR_TEXT)
	_run(SET_UP_BEST_TIMES_SCREEN, BEST_TIMES)


## $28A8
func done() -> void:
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	(sibling(Heap) as Heap).give_back(u32(SPRITES))
	m.d0 = with_low16(m.d0, 0)
