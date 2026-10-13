extends GameRoutines
## The screen before a course: its map and name, and the three best times
## driven on it, which slide into place.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")

const COURSE := 0x101202
const PLAYER := 0x1011FC
const FRAMES := 0x1034FC
const STATE := 0x103508
enum {SLIDING_IN, SHOWN, CLEARING}
## Frames left of it once everything is in place; button A ends it.
const FRAMES_LEFT := 0x10350A
const FRAMES_SHOWN := 240
## Which of the five groups of things are still sliding, a bit each.
const SLIDING := 0x103518
const FIELD_10351A := 0x10351A
## A time as text, for the digits' pictures.
const TIME_TEXT := 0x10351C
## Its 30 sprite objects: the map, five parts of the name and the
## headings, and three times of eight characters.
const SPRITES := 0x103534
const SPRITE_COUNT := 30
const TIME_SPRITES: Array[int] = [0x10354C, 0x10356C, 0x10358C]
## The address of three addresses: the pictures of the digits, the
## pictures of each course's writing, and the maps of the courses.
const PICTURES := 0x80018
const DIGITS := 0
const WRITING := 4
const MAPS := 8
## Which sprite object (by where its address is kept) shows which picture
## of the writing: five times an address and a word.
const WRITING_SPRITES := 0x1C08E
## The best times of each course: by course, the address of the addresses
## of the times, in frames (16.16).
const COURSE_BESTS := 0x1000B2
## Digits as the pictures count them, two for each number: frames as
## hundredths, seconds and minutes; and the two marks between them.
const HUNDREDTH_DIGITS := 0x1135E
const SECOND_DIGITS := 0x113D6
const MINUTE_DIGITS := 0x1144E
const MINUTE_MARK := 0xA
const SECOND_MARK := 0xB
## The five groups that slide in. Each has a list of sprite objects (the
## address its address is kept at and where it is within the group, ended
## by 0), a path of stops (eight bytes: frames to stay, x, y), frames left
## at this stop, and the stop it is at, counting down.
const GROUPS: Array[Array] = [
	[0x1C0B0, 0x1C1AC, 0x1034FE, 0x10350E, 0x15],
	[0x1C0BC, 0x1C254, 0x103500, 0x103510, 9],
	[0x1C0C8, 0x1C29C, 0x103502, 0x103512, 9],
	[0x1C114, 0x1C2E4, 0x103504, 0x103514, 9],
	[0x1C160, 0x1C32C, 0x103506, 0x103516, 9],
]
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 11
const COLOURS := 0x1C56A
## What is said of each course, a third of a second in.
const COURSE_SOUNDS := 0x1C55C
const SOUND_AT_FRAME := 20
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E


func routines() -> Dictionary:
	return {
		0x112F8: func() -> void: _write_time(m.a1, low16(m.d1) & 0xFFFF),
		0x114C6: func() -> void: m.d0 = with_low16(m.d0, 1 if _slide(m.a1, m.a3, m.a5, m.a6) else 0),
		0x11522: func() -> void: _show_text(m.a1, m.a2, m.a5),
		0x1BE56: set_up,
		0x1C374: update,
		0x1C3C4: sliding_in,
		0x1C4E8: shown,
		0x1C51A: clearing,
		0x1C536: count_frame,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "a0", "a1", "a3", "a4", "a5", "a6", "ccr"]
	return {0x112F8: ["ccr"], 0x114C6: ["ccr"], 0x11522: ["ccr"], 0x1BE56: free, 0x1C374: free,
			0x1C3C4: free, 0x1C4E8: free, 0x1C51A: free, 0x1C536: ["d0", "ccr"]}


## $1BE56
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, 0x100)
	set16(STATE, SLIDING_IN)
	set16(FRAMES_LEFT, FRAMES_SHOWN)
	set16(FRAMES, 0)
	for group in GROUPS:
		set16(group[2], 0)
		set16(group[3], group[4])
	set16(SLIDING, 0x1F)
	set16(FIELD_10351A, 0)
	var course := wrap16(u16(COURSE) * 4)
	var pictures := m.r32(PICTURES)
	for index in SPRITE_COUNT:
		set32(SPRITES + index * 4, Sprite.take_record(m))
	var map := u32(SPRITES)
	Sprite.place(m, map, 0, 0)
	Sprite.picture(m, map, m.r32(m.r32(pictures + MAPS) + course))
	set16(map + Sprite.DEPTH, 0xFFFF)
	var writing := m.r32(m.r32(pictures + WRITING) + course)
	for index in 5:
		var entry := WRITING_SPRITES + index * 6
		Sprite.picture(m, u32(m.r32(entry)), m.r32(writing + m.r16(entry + 4)))
	var bests := u32(COURSE_BESTS + course)
	for index in 3:
		var frames := ((u32(u32(bests + index * 4)) + 0x8000) >> 16) & 0xFFFF
		_write_time(TIME_TEXT, frames)
		_show_text(TIME_TEXT, m.r32(pictures + DIGITS), TIME_SPRITES[index])
	for group in GROUPS:
		_slide(group[0], group[1], group[2], group[3])
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0)


## $112F8: a count of frames as eight digits and marks for `_show_text`.
func _write_time(to: int, frames: int) -> void:
	var minutes := MINUTE_DIGITS + frames / 3600 * 2
	var seconds := SECOND_DIGITS + frames % 3600 / 60 * 2
	var hundredths := HUNDREDTH_DIGITS + frames % 60 * 2
	var text := [m.r8(minutes), m.r8(minutes + 1), MINUTE_MARK, m.r8(seconds), m.r8(seconds + 1), SECOND_MARK,
			m.r8(hundredths), m.r8(hundredths + 1), 0]
	for index in text.size():
		m.w8(to + index, text[index])


## $11522: gives eight sprite objects, whose addresses are at `sprites`,
## the pictures of the eight characters at `text`.
func _show_text(text: int, pictures: int, sprites: int) -> void:
	for index in 8:
		Sprite.picture(m, m.r32(sprites + index * 4), m.r32(pictures + m.r8(text + index) * 4))


## $114C6: a frame of a group's slide. Returns false once it has passed
## its last stop.
func _slide(list: int, path: int, frames: int, stop: int) -> bool:
	var at := 0
	var moving := true
	if s16(frames) > 0:
		set16(frames, u16(frames) - 1)
		at = wrap16(u16(stop) << 3)
	else:
		set16(stop, u16(stop) - 1)
		if u16(stop) == 0xFFFF:
			moving = false
		else:
			at = wrap16(u16(stop) << 3)
			set16(frames, m.r16(path + at))
	while m.r32(list) != 0:
		Sprite.place(m, m.r32(m.r32(list)), m.r16(list + 4) + m.r16(path + at + 2), m.r16(list + 6) + m.r16(path + at + 4))
		list += 8
	return moving


## $1C374: a frame of the screen. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		SLIDING_IN: sliding_in()
		SHOWN: shown()
		CLEARING: clearing()
	count_frame()
	if low16(m.d0) == 0:
		set16(STATE, u16(STATE) + 1)
		if u16(STATE) >= CLEARING + 1:
			return
	m.d0 = with_low16(m.d0, 1)


## $1C3C4
func sliding_in() -> void:
	var sliding := u16(SLIDING)
	for index in GROUPS.size():
		var group := GROUPS[index]
		if sliding & (1 << index) and not _slide(group[0], group[1], group[2], group[3]):
			sliding &= ~(1 << index)
	set16(SLIDING, sliding)
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0 if sliding == 0 else 1)


## $1C4E8
func shown() -> void:
	if (sibling(Joystick) as Joystick).held(u16(PLAYER), Joystick.BUTTON_A):
		set16(FRAMES_LEFT, 1)
	set16(FRAMES_LEFT, u16(FRAMES_LEFT) - 1)
	m.d0 = with_low16(m.d0, 1 if s16(FRAMES_LEFT) > 0 else 0)


## $1C51A
func clearing() -> void:
	for index in SPRITE_COUNT:
		Sprite.free_record(m, u32(SPRITES + index * 4))
	m.d0 = with_low16(m.d0, 0)


## $1C536
func count_frame() -> void:
	if u16(FRAMES) == SOUND_AT_FRAME:
		var sound := m.r16(COURSE_SOUNDS + wrap16(u16(COURSE) * 2))
		m.d0 = with_low16(m.d0, sound)
		(sibling(SoundRequests) as SoundRequests).request(sound)
	set16(FRAMES, u16(FRAMES) + 1)
