extends GameRoutines
## What a race shows on top of the course: the time taken, the time left,
## the speed, how far it is to the next checkpoint, and a warning on slow
## ground. All but the checkpoint bar is drawn on the text layer (text.gd).

const Text := preload("res://game/text.gd")
const Sprite := preload("res://game/sprite_object.gd")
const RaceClock := preload("res://game/race_clock.gd")
const Car := preload("res://game/car.gd")

# --- time taken --------------------------------------------------------------

## The time taken as text (minutes ' seconds " hundredths), and the cell
## it is written from.
const TIME_TAKEN_TEXT := 0x1016AA
const TIME_TAKEN_CELL := 0x1016C2
const TIME_TAKEN_ROUNDED := 0x1016D4
## Where `format_time` leaves its text.
const TIME_TEXT := 0x1016E6
## Two characters for each count of minutes and of seconds, and the
## hundredths of a second for each count of frames.
const MINUTE_DIGITS := 0x11280
const SECOND_DIGITS := 0x11208
const FRAME_DIGITS := 0x11190
const FRAMES_PER_SECOND := 60
const FRAMES_PER_MINUTE := 3600
const SMALL_FONT := 0x300
const PALETTE_WHITE := 9

# --- time left ---------------------------------------------------------------

## The whole frames left when it was last shown.
const TIME_LEFT_SHOWN := 0x1016C4
## Digits of the seconds left, and of the hundredths.
const SECOND_DIGITS_LEFT := 0x1016C6
const HUNDREDTH_DIGITS_LEFT := 0x1016CA
## The palette of the time left: PALETTE_RUNNING, then PALETTE_OVER.
const TIME_LEFT_PALETTE := 0x1016CE
## One bit for each of the last ten seconds that has been counted aloud.
const SECONDS_COUNTED := 0x1016D0
const PALETTE_RUNNING := 8
const PALETTE_OVER := 7
## Two digits for each count of seconds up to 100, and the hundredths for
## each count of frames.
const SECONDS_AS_DIGITS := 0x26FC6
const FRAMES_AS_DIGITS := 0x2708E
## Where in a list of pictures each digit's is; the lists of large and of
## small digits.
const DIGIT_OFFSETS := 0x26F46
const LARGE_DIGITS := 0x27106
const SMALL_DIGITS := 0x271F6
const TIME_LEFT_LABEL := 0xFEC0
const TIME_LEFT_LABEL_CELL := 0x7406
const MINUS_SIGN := 0xFEB8
const MINUS_SIGN_CELL := 0x7345
const SECOND_CELLS: Array[int] = [0x7383, 0x73C3]
const HUNDREDTH_CELLS: Array[int] = [0x7425, 0x7465]
## The voice counting down the last ten seconds.
const COUNT_DOWN_SOUNDS := 0x26F30
const REQUEST_SOUND := 0x15256

# --- speed -------------------------------------------------------------------

## The car's speed as the rest of the game reads it (car.gd).
const CAR_SPEED := 0x101666
const SPEED_DIGITS := 0x1016D8
## The three digits shown for each sixteenth of the speed.
const SPEED_AS_DIGITS := 0x27316
const SPEED_DIGIT_OFFSETS := 0x27296
const SPEED_DIGIT_PICTURES := 0x27716
const SPEED_CELLS: Array[int] = [0x7059, 0x7099, 0x70D9]

# --- slow ground -------------------------------------------------------------

## 1 while the warning is shown, the same a frame ago, and the frames the
## car has to be on or off slow ground for until it changes.
const SLOW_SIGN := 0x10169A
const SLOW_SIGN_BEFORE := 0x10169C
const SLOW_SIGN_COUNTDOWN := 0x10169E
const SLOW_SIGN_FRAMES := 0xF
## The warning's two pictures: blank and shown.
const SLOW_SIGN_PICTURES := 0x278C6
const SLOW_SIGN_CELL := 0x71BA

# --- progress to the next checkpoint -----------------------------------------

## The checkpoints of the course, those reached, and the car's y (set by
## car.gd through $19F74).
const CHECKPOINT_COUNT := 0x103468
const CHECKPOINTS_REACHED := 0x10346A
const CAR_Y := 0x10346C
## For each checkpoint, the y it is at and how far it is from the one before.
const CHECKPOINT_Y := 0x10346E
const STRETCH_LENGTH := 0x10347E
## Sprite objects: the label, the bar and the marker at its end.
const PROGRESS_LABEL := 0x10348E
const PROGRESS_BAR := 0x103492
const PROGRESS_MARKER := 0x103496
const PROGRESS_FRAMES := 0x10349A
const PROGRESS_CAR := 0x103466
const BAR_PICTURE := 0x4C
const MARKER_PICTURES := 0x50
## The pictures of things other than the course's own.
const PICTURES := 0x80008
const LABEL_NO_CHECKPOINTS := 0x48
const LABEL_FIRST := 0x34
const LABEL_LAST_ODD := 0x40
const LABEL_LAST_EVEN := 0x44
const LABEL_ODD := 0x38
const LABEL_EVEN := 0x3C
const BAR_X := 0x118
const BAR_BOTTOM := 0x51
const PALETTE_OVERRIDE := 0x14
const PALETTE_FLASH := 0xFFFE


func routines() -> Dictionary:
	return {
		0xFE0A: show_time_taken,
		0x11120: format_time,
		0xFECC: show_time_left,
		0x100D2: show_speed,
		0xFC9E: show_slow_ground,
		0xFD1C: draw_slow_sign,
		0x19F82: show_progress,
		0x19E38: set_up_progress,
		0x19F42: clear_progress,
		0x19F74: func() -> void:
			set16(CHECKPOINTS_REACHED, m.d0)
			set16(CAR_Y, m.d2),
		0xFC74: draw_demo_label,
		0xFC84: reset_slow_sign,
		0xFD34: func() -> void: _write_text(PAUSE_TEXT, PAUSE_CELL),
		0xFD4E: func() -> void: _write_text(PAUSE_BLANK, PAUSE_CELL),
		0xFD74: draw_course_label,
		0xFDB8: set_up_time_taken,
		0xFE60: set_up_time_left,
		0x100BE: set_up_speed,
	}


func scratch() -> Dictionary:
	var free := ["d0", "d1", "d2", "d3", "d4", "d5", "a0", "a1", "a2", "a3", "ccr"]
	return {
		0xFE0A: free,
		0x11120: ["ccr"],
		0xFECC: free,
		0x100D2: free,
		0xFC9E: free,
		0xFD1C: free,
		0x19F82: ["a0", "ccr"],
		0x19E38: ["ccr"],
		0x19F42: ["ccr"],
		0x19F74: ["ccr"],
		0xFC74: free,
		0xFC84: ["ccr"],
		0xFD34: free,
		0xFD4E: free,
		0xFD74: free,
		0xFDB8: free + ["d7"],
		0xFE60: free,
		0x100BE: free,
	}


func variations() -> Dictionary:
	return {
		0xFECC: [
			func() -> void: set32(RaceClock.TIME_LEFT, 0x8000),
			func() -> void: set32(RaceClock.TIME_LEFT, 0x7FFF),
			func() -> void: set32(RaceClock.TIME_LEFT, 200 * FRAMES_PER_SECOND << 16),
			func() -> void:
				set32(RaceClock.TIME_LEFT, -0x18000)
				set16(TIME_LEFT_SHOWN, 3),
			func() -> void:
				set32(RaceClock.TIME_LEFT, 7 * FRAMES_PER_SECOND << 16)
				set32(SECONDS_COUNTED, 0),
		],
		0x19F82: [
			func() -> void: set16(CAR_Y, u16(CHECKPOINT_Y + u16(CHECKPOINTS_REACHED) * 2) + 5),
			func() -> void: set16(CAR_Y, u16(CHECKPOINT_Y + u16(CHECKPOINTS_REACHED) * 2)),
			func() -> void: set16(CAR_Y, u16(CHECKPOINT_Y + u16(CHECKPOINTS_REACHED) * 2) - 0x7000),
			func() -> void: set16(PROGRESS_FRAMES, 0x7F),
			func() -> void: set16(PROGRESS_FRAMES, 4),
		],
	}


## $FE0A: writes the time taken, rounded to whole frames.
func show_time_taken() -> void:
	set32(TIME_TAKEN_ROUNDED, u32(RaceClock.TIME_TAKEN) + 0x8000)
	var text := _time_as_text(u16(TIME_TAKEN_ROUNDED))
	for index in 8:
		set8(TIME_TAKEN_TEXT + index, text[index])
	Text.write(m, text.slice(0, 8), u16(TIME_TAKEN_CELL), PALETTE_WHITE, SMALL_FONT)
	m.set_sr(m.get_sr() & 0xF8FF)


## $11120: the count of frames at A1 as text at A3: minutes, ', seconds, ",
## hundredths.
func format_time() -> void:
	_time_as_text(m.r16(m.a1))
	m.a3 = TIME_TEXT


func _time_as_text(frames: int) -> PackedByteArray:
	var minutes := MINUTE_DIGITS + frames / FRAMES_PER_MINUTE * 2
	var seconds := SECOND_DIGITS + frames % FRAMES_PER_MINUTE / FRAMES_PER_SECOND * 2
	var hundredths := FRAME_DIGITS + frames % FRAMES_PER_SECOND * 2
	var text := PackedByteArray([rom_u8(minutes), rom_u8(minutes + 1), 0x27, rom_u8(seconds), rom_u8(seconds + 1),
			0x22, rom_u8(hundredths), rom_u8(hundredths + 1), 0])
	for index in text.size():
		set8(TIME_TEXT + index, text[index])
	return text


## $FECC: shows the seconds left in large digits and the hundredths in
## small ones. Once the time is out they change colour and count up, with
## a minus sign. A voice counts the last ten seconds.
func show_time_left() -> void:
	if u16(RaceClock.TIME_LEFT) == 0:
		set16(TIME_LEFT_PALETTE, PALETTE_OVER)
		Text.draw_block(m, TIME_LEFT_LABEL, TIME_LEFT_LABEL_CELL, PALETTE_OVER)
	var left := s32(RaceClock.TIME_LEFT)
	var frames := ((absi(left) + 0x8000) & 0xFFFFFFFF) >> 16
	var seconds := frames / FRAMES_PER_SECOND
	set16(SECOND_DIGITS_LEFT, rom_u16(SECONDS_AS_DIGITS + mini(seconds, 100) * 2))
	set16(HUNDREDTH_DIGITS_LEFT, rom_u16(FRAMES_AS_DIGITS + frames % FRAMES_PER_SECOND * 2))
	var palette := u16(TIME_LEFT_PALETTE) & 0xF
	for index in 2:
		var large := rom_u32(LARGE_DIGITS + rom_s16(DIGIT_OFFSETS + u8(SECOND_DIGITS_LEFT + index) * 2))
		Text.draw_block(m, large, SECOND_CELLS[index], palette)
	for index in 2:
		var small := rom_u32(SMALL_DIGITS + rom_s16(DIGIT_OFFSETS + u8(HUNDREDTH_DIGITS_LEFT + index) * 2))
		Text.draw_block(m, small, HUNDREDTH_CELLS[index], palette)
	if s16(RaceClock.TIME_LEFT) < 0 and s16(TIME_LEFT_SHOWN) >= 0:
		Text.draw_block(m, MINUS_SIGN, MINUS_SIGN_CELL)
	set16(TIME_LEFT_SHOWN, u16(RaceClock.TIME_LEFT))
	m.set_sr(m.get_sr() & 0xF8FF)
	if seconds > 10:
		set32(SECONDS_COUNTED, 0)
	elif frames % FRAMES_PER_SECOND == 0:
		var counted := u16(SECONDS_COUNTED)
		if counted & (1 << seconds) == 0:
			set16(SECONDS_COUNTED, counted | (1 << seconds))
			m.d0 = with_low16(m.d0, rom_u16(COUNT_DOWN_SOUNDS + seconds * 2))
			m.call_routine(REQUEST_SOUND)


## $100D2: shows the speed in three digits.
func show_speed() -> void:
	var speed := Car._magnitude(s16(CAR_SPEED)) & 0xFFFF
	set32(SPEED_DIGITS, rom_u32(SPEED_AS_DIGITS + wrap16((speed >> 4) * 4)))
	for index in 3:
		var picture := rom_u32(SPEED_DIGIT_PICTURES + rom_s16(SPEED_DIGIT_OFFSETS + u8(SPEED_DIGITS + index) * 2))
		Text.draw_block(m, picture, SPEED_CELLS[index])
	m.set_sr(m.get_sr() & 0xF8FF)


## $FC9E: a warning comes on once the car in A6 has been on slow ground
## for a quarter of a second, and goes off as long after it has left it.
func show_slow_ground() -> void:
	var shown := u16(SLOW_SIGN)
	var on_slow_ground := u16(m.a6 + Car.SLOW_GROUND)
	if (shown == 0 and on_slow_ground == 1) or (shown != 0 and on_slow_ground == 0):
		var countdown := s16(SLOW_SIGN_COUNTDOWN) - 1
		if countdown < 0:
			countdown = SLOW_SIGN_FRAMES
			shown = 1 if shown == 0 else 0
			set16(SLOW_SIGN, shown)
		set16(SLOW_SIGN_COUNTDOWN, countdown)
	if shown != u16(SLOW_SIGN_BEFORE):
		set16(SLOW_SIGN_BEFORE, shown)
		m.d0 = with_low16(m.d0, shown)
		draw_slow_sign()


## $FD1C: draws the warning (D0 is 1) or blanks it (0).
func draw_slow_sign() -> void:
	Text.draw_block(m, rom_u32(SLOW_SIGN_PICTURES + wrap16(low16(m.d0) * 4)), SLOW_SIGN_CELL)
	m.set_sr(m.get_sr() & 0xF8FF)


## $19F82: the bar at the right edge shrinks as the car nears the next
## checkpoint; the marker at its end flashes now and then, and the label
## says which checkpoint is next.
func show_progress() -> void:
	var reached := u16(CHECKPOINTS_REACHED)
	var label := LABEL_NO_CHECKPOINTS
	if reached == 0:
		if u16(CHECKPOINT_COUNT) != 0:
			label = LABEL_FIRST
	elif reached == u16(CHECKPOINT_COUNT):
		label = LABEL_LAST_ODD if reached & 1 else LABEL_LAST_EVEN
	else:
		label = LABEL_ODD if reached & 1 else LABEL_EVEN
	Sprite.picture(m, u32(PROGRESS_LABEL), m.r32(m.r32(PICTURES) + label))
	# the bar's length, of $100, is the part of the stretch still to go
	var index := wrap16(reached * 2)
	var to_go := s16(CHECKPOINT_Y + index) - s16(CAR_Y)
	var length := 1
	if to_go >= 0:
		to_go = wrap16(to_go)
		length = 0x100
		if to_go <= s16(STRETCH_LENGTH + index):
			length = maxi(((to_go << 8) & 0xFFFFFFFF) / maxi(u16(STRETCH_LENGTH + index), 1), 1) & 0xFFFF
	var bar := u32(PROGRESS_BAR)
	Sprite.zoom(m, bar, 0x100, length)
	var gone := (length - 1) & 0xFFFF
	var top := (((gone & 0xFF00) | (~gone & 0xFF)) >> 2) + BAR_BOTTOM
	Sprite.place(m, bar, BAR_X, top)
	var marker := u32(PROGRESS_MARKER)
	Sprite.place(m, marker, BAR_X, top - 8)
	var frames := (u16(PROGRESS_FRAMES) + 1) & 0xFFFF
	set16(PROGRESS_FRAMES, frames)
	set16(marker + PALETTE_OVERRIDE, PALETTE_FLASH if frames & 0x7F == 0 or frames & 0x7F == 5 else 0)
	m.a0 = marker


# --- setting the HUD up ------------------------------------------------------

const COURSE := 0x101202
## Blocks of cells: what labels a race of the attract mode, the label of
## the practice course, that of the others and their
## numbers, and the frame of the speed.
const DEMO_LABEL := 0x27936
const DEMO_LABEL_CELL := 0x7045
const PRACTICE_LABEL := 0x277FE
const STAGE_LABEL := 0x2782E
const STAGE_NUMBERS := 0x27852
const COURSE_LABEL_CELL := 0x735A
const STAGE_NUMBER_CELL := 0x747A
const SPEED_FRAME := 0x277F2
const SPEED_FRAME_CELL := 0x711A
## Text: over the time taken, beside the time left, and for a paused game.
const TIME_TAKEN_LABEL := 0xFDFC
const TIME_TAKEN_LABEL_CELL := 0x7043
const TIME_TAKEN_FIRST_CELL := 0x70E3
const TIME_LEFT_UNIT := 0xFEC6
const TIME_LEFT_UNIT_CELL := 0x7424
const PAUSE_TEXT := 0xFD68
const PAUSE_BLANK := 0xFD6E
const PAUSE_CELL := 0x726E


## $FC74
func draw_demo_label() -> void:
	Text.draw_block(m, DEMO_LABEL, DEMO_LABEL_CELL)
	m.set_sr(m.get_sr() & 0xF8FF)


## $FC84
func reset_slow_sign() -> void:
	set16(SLOW_SIGN_COUNTDOWN, SLOW_SIGN_FRAMES)
	set16(SLOW_SIGN, 0)
	set16(SLOW_SIGN_BEFORE, 0)


## $FD74: which course this is, at the bottom right.
func draw_course_label() -> void:
	var course := u16(COURSE)
	if course == 0:
		Text.draw_block(m, PRACTICE_LABEL, COURSE_LABEL_CELL)
	else:
		Text.draw_block(m, STAGE_LABEL, COURSE_LABEL_CELL)
		Text.draw_block(m, rom_u32(STAGE_NUMBERS + wrap16(course * 4)), STAGE_NUMBER_CELL)
	m.set_sr(m.get_sr() & 0xF8FF)


## $FDB8
func set_up_time_taken() -> void:
	for index in 8:
		set32(TIME_TAKEN_TEXT + index * 4, 0)
	set16(TIME_TAKEN_CELL, TIME_TAKEN_FIRST_CELL)
	_write_text(TIME_TAKEN_LABEL, TIME_TAKEN_LABEL_CELL)


## $FE60
func set_up_time_left() -> void:
	set32(SECONDS_COUNTED, 0)
	set16(TIME_LEFT_SHOWN, u16(RaceClock.TIME_LEFT))
	set32(SECOND_DIGITS_LEFT, 0)
	set32(HUNDREDTH_DIGITS_LEFT, 0)
	set16(TIME_LEFT_PALETTE, PALETTE_RUNNING)
	Text.draw_block(m, TIME_LEFT_LABEL, TIME_LEFT_LABEL_CELL)
	_write_text(TIME_LEFT_UNIT, TIME_LEFT_UNIT_CELL)
	show_time_left()


## $100BE
func set_up_speed() -> void:
	Text.draw_block(m, SPEED_FRAME, SPEED_FRAME_CELL)
	show_speed()


## Writes the text at `text` in the program, up to a zero, in the small font.
func _write_text(text: int, cell: int) -> void:
	var characters := PackedByteArray()
	while m.r8(text) != 0:
		characters.append(m.r8(text))
		text += 1
	Text.write(m, characters, cell, PALETTE_WHITE, SMALL_FONT)
	m.set_sr(m.get_sr() & 0xF8FF)


## $19E38: the bar of a course: A3 has a count and then the y of the start,
## of each checkpoint and of the finish; D0 is the checkpoints reached, D1
## the car chosen and D2 the car's y.
func set_up_progress() -> void:
	var places := m.a3
	set16(PROGRESS_CAR, m.d1)
	var count := wrap16(m.r16(places) - 2)
	set16(CHECKPOINT_COUNT, count)
	set16(CHECKPOINTS_REACHED, m.d0)
	set16(CAR_Y, m.d2)
	for index in count + 1:
		var y := m.r16(places + 2 + index * 2)
		set16(CHECKPOINT_Y + index * 2, y)
		set16(STRETCH_LENGTH + index * 2, y - m.r16(places + 4 + index * 2))
	var label := Sprite.take_record(m)
	set32(PROGRESS_LABEL, label)
	set16(label + Sprite.DEPTH, 0x7001)
	Sprite.place(m, label, BAR_X, 0x40)
	var bar := Sprite.take_record(m)
	set32(PROGRESS_BAR, bar)
	set16(bar + Sprite.DEPTH, 0x7000)
	Sprite.picture(m, bar, m.r32(m.r32(PICTURES) + BAR_PICTURE))
	var marker := Sprite.take_record(m)
	set32(PROGRESS_MARKER, marker)
	set16(marker + Sprite.DEPTH, 0x7002)
	# the marker is the car chosen
	Sprite.picture(m, marker, m.r32(m.r32(PICTURES) + MARKER_PICTURES + mini(u16(PROGRESS_CAR), 2) * 4))
	set16(PROGRESS_FRAMES, 10)


## $19F42
func clear_progress() -> void:
	for sprite: int in [PROGRESS_MARKER, PROGRESS_BAR, PROGRESS_LABEL]:
		Sprite.free_record(m, u32(sprite))
