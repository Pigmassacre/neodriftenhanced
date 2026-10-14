extends GameRoutines
## The two screens with a list of best times: the result after a course
## (the course's emblem assembles from tiles, its name flies in, and the
## six best times of the course scroll by) and the totals after the last
## course (the same without the emblem, with the eleven best games).
##
## Each is a row of scenes. A scene is three routines: one sets it up, one
## runs a frame of it and leaves in A0 what comes next (0 while it goes on,
## the next scene, or 1 after the last), and one clears it away.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const Text := preload("res://game/text.gd")
const Hud := preload("res://game/hud.gd")

const COURSE := 0x101202
const PLAYER := 0x1011FC
## Where this game came among the best of the course, and of all games.
const COURSE_RANK := 0x101214
const RANK := 0x101212
## The address after which the pictures of these screens are listed: the
## font of the lists, the large letters, the tiles of the emblem, and the
## backdrop as a map of ground and its tiles.
const PICTURES := 0x80008
const LIST_FONT := 0
const LETTERS := 4
const EMBLEM_TILES := 8
const BACKDROP_MAP := 0xC
const BACKDROP_TILES := 0x10
const REDRAW_GROUND := 0x1348E
const GROUND_OFF := 0x133FA
const SCROLL_GROUND := 0x13546
const BUILD_SPRITES := 0x1229E
const CLEAR_SPRITES := 0x120E0
const CLEAR_TEXT := 0xA26
const FIELD_1020A0 := 0x1020A0
const LAST_SCENE := 1

## What differs between the two screens.
const RESULT := {
	scene = 0x1004AE, skipping = 0x1004B2, clock = 0x1004AC, first_scene = 0x1F092,
	borders = 0x1F056, colours = 0x1EED6, shaded = [0x1EF36, 0x1EF66, 0x1EF06],
	letters = 0x10072C, title = 0x10076E, title_x = 0x30, after_title = 0x1F0AE,
	rows = 0x100782, row_count = 6, first_scroll = 0xD0, pause = 0x100996, flash = 0x100998,
	rank = COURSE_RANK, heights = 0x1ECD6, time_text = 0x100994, car = 0xA,
}
const TOTALS := {
	scene = 0x10099C, skipping = 0x1009A0, clock = 0x10099A, first_scene = 0x1F482,
	borders = 0x1F43A, colours = 0x1F2BA, shaded = [0x1F31A, 0x1F34A, 0x1F2EA],
	letters = 0x100C1A, title = 0x100C5C, title_x = 0x40, after_title = 0x1F492,
	rows = 0x100C70, row_count = 11, first_scroll = 0x148, pause = 0x10103C, flash = 0x10103E,
	rank = RANK, heights = 0x1F0BA, time_text = 0x10103A, car = 8,
}

# The emblem: 63 tiles in 7 rows of 9, each ten bytes.
const TILES := 0x1004B4
const TILE_SIZE := 10
const TILE_COUNT := 63
const AFTER_EMBLEM := 0x1F09E
## A thing that grows in: the clock's time at which it starts (negated),
## its sprite object, and where it belongs.
const DELAY := 0
const SPRITE := 2
const HOME_X := 6
const HOME_Y := 8
const LETTER_SIZE := 8
const LETTER_COUNT := 8

# The lists. A row is $58 bytes: how far down the list it is, its sprite
# object, and its picture: 18 columns of one tile.
const ROW_SIZE := 0x58
const ROW_PICTURE := 6
const ROW_COLUMNS := 18
const ROW_SPACING := 0x18
## The best times of each course (by course, the address of the addresses
## of six) and the best games (the addresses of eleven): the time in
## frames, the name at 4, and which car.
const COURSE_BESTS := 0x1000B2
const BESTS := 0x100002
const BEST_NAME := 4
const LIST_PAUSE := 60
const SOUND_BEST_THREE := 0x186C
## The emblem's columns are the backdrop's, which comes round every eight.
const EMBLEM_PERIOD := 8

## In a picture wider than the original's, the emblem's tiles to either
## side of it: [record, column, row, delay].
var _side_tiles: Array = []


func routines() -> Dictionary:
	return {
		0x4150: set_up.bind(RESULT),
		0x4248: update.bind(RESULT),
		0x4B8A: set_up.bind(TOTALS),
		0x4CB4: update.bind(TOTALS),
		0x12296: func() -> void: set16(FIELD_1020A0, m.d0),
		0x433E: func() -> void: _set_up_tile(m.a1, low16(m.d4), low16(m.d0), low16(m.d2), m.r32(m.a2)),
		0x4366: func() -> void: _grow_tile(m.a1, low16(m.d1)),
		0x43D2: func() -> void: Sprite.free_record(m, u32(m.a1 + SPRITE)),
		0x43E6: set_up_emblem,
		0x4446: grow_emblem,
		0x4498: clear_emblem,
		0x44F0: func() -> void: _set_up_letter(m.a1, low16(m.d1), low16(m.d0), m.d2 & 0xFF),
		0x4530: func() -> void: _grow_letter(m.a1, low16(m.d1)),
		0x45C2: set_up_title.bind(RESULT),
		0x4666: grow_title.bind(RESULT),
		0x46B8: nothing,
		0x46C6: func() -> void: _set_up_row(RESULT, m.a1, low16(m.d0)),
		0x471A: func() -> void: Sprite.free_record(m, u32(m.a1 + SPRITE)),
		0x472E: func() -> void: _show_row(RESULT, m.a1, low16(m.d0), low16(m.d3)),
		0x4A56: set_up_list.bind(RESULT),
		0x4AE4: scroll_list.bind(RESULT),
		0x4B64: clear_list.bind(RESULT),
		0x4F5C: func() -> void: _set_up_letter(m.a1, low16(m.d1), low16(m.d0), m.d2 & 0xFF),
		0x4F9C: func() -> void: _grow_letter(m.a1, low16(m.d1)),
		0x502E: set_up_title.bind(TOTALS),
		0x50A2: grow_title.bind(TOTALS),
		0x50F4: nothing,
		0x5102: func() -> void: _set_up_row(TOTALS, m.a1, low16(m.d0)),
		0x5148: func() -> void: Sprite.free_record(m, u32(m.a1 + SPRITE)),
		0x515C: func() -> void: _show_row(TOTALS, m.a1, low16(m.d0), low16(m.d3)),
		0x5490: set_up_list.bind(TOTALS),
		0x54C8: scroll_list.bind(TOTALS),
		0x557C: clear_list.bind(TOTALS),
	}


func scratch() -> Dictionary:
	var table := {}
	for address: int in routines():
		table[address] = ["ccr"]
	return table


func _pictures(which: int) -> int:
	return m.r32(m.r32(m.r32(PICTURES) - 4) + which)


func _request_sound(sound: int) -> void:
	(sibling(SoundRequests) as SoundRequests).request(sound)


# --- the screen --------------------------------------------------------------

## $4150 and $4B8A
func set_up(screen: Dictionary) -> void:
	var saved := _registers()
	m.call_routine(CLEAR_TEXT)
	Text.draw_rows(m, screen.borders, Text.CELLS + 1 * Text.COLUMN + 2)
	Text.draw_rows(m, screen.borders, Text.CELLS + 0x26 * Text.COLUMN + 2)
	m.call_routine(CLEAR_SPRITES)
	set16(FIELD_1020A0, 9)
	m.call_routine(GROUND_OFF)
	var palettes := sibling(Palettes) as Palettes
	palettes.queue(0x80, 8, screen.colours, 0x100)
	palettes.choose_shades(1)
	for index in 3:
		_queue_shaded(0x90 + index * 0x10, screen.shaded[index])
	if screen == TOTALS:
		_draw_backdrop()
	set32(screen.scene, screen.first_scene)
	m.call_routine(m.r32(screen.first_scene))
	set16(screen.skipping, 0)
	_restore(saved)
	m.d0 = with_low16(m.d0, 0)


## One set of colours in 16 palettes, from nearly black to full.
func _queue_shaded(first: int, colours: int) -> void:
	for step in 16:
		(sibling(Palettes) as Palettes).queue(first + step, 1, colours, (step + 1) * 0x10)


func _draw_backdrop() -> void:
	m.d0 = with_low16(m.d0, 0x10)
	m.d1 = with_low16(m.d1, 0)
	m.d2 = with_low16(m.d2, 0x100)
	m.d3 = with_low16(m.d3, 0x100)
	m.a4 = _pictures(BACKDROP_MAP)
	m.a5 = _pictures(BACKDROP_TILES)
	m.call_routine(REDRAW_GROUND)


func _registers() -> Array[int]:
	return [m.d0, m.d1, m.d2, m.d3, m.d4, m.d5, m.d6, m.d7, m.a0, m.a1, m.a2, m.a3, m.a4, m.a5, m.a6, m.get_sr()]


func _restore(saved: Array[int]) -> void:
	m.d0 = saved[0]; m.d1 = saved[1]; m.d2 = saved[2]; m.d3 = saved[3]
	m.d4 = saved[4]; m.d5 = saved[5]; m.d6 = saved[6]; m.d7 = saved[7]
	m.a0 = saved[8]; m.a1 = saved[9]; m.a2 = saved[10]; m.a3 = saved[11]
	m.a4 = saved[12]; m.a5 = saved[13]; m.a6 = saved[14]
	m.set_sr(saved[15])


## $4248 and $4CB4: a frame of the screen. Leaves 0 in D0 when it is over.
## A button ends it, once it has been let go of.
func update(screen: Dictionary) -> void:
	var joystick := sibling(Joystick) as Joystick
	var player := u16(PLAYER)
	if not joystick.held(player, Joystick.BUTTON_A) and not joystick.held(player, Joystick.BUTTON_B):
		set16(screen.skipping, 1)
	elif u16(screen.skipping) != 0:
		_end()
		return
	var saved := _registers()
	var scene := u32(screen.scene)
	m.call_routine(m.r32(scene + 4))
	var next := m.a0
	m.call_routine(BUILD_SPRITES)
	m.call_routine(SCROLL_GROUND)
	if next != 0:
		set32(screen.scene, 0)
		m.call_routine(m.r32(scene + 8))
		if next != LAST_SCENE:
			set32(screen.scene, next)
			m.call_routine(m.r32(next))
	_restore(saved)
	if u32(screen.scene) == 0:
		_end()
	else:
		m.d0 = with_low16(m.d0, 1)


func _end() -> void:
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	m.d0 = with_low16(m.d0, 0)


## $46B8 and $50F4
func nothing() -> void:
	pass


# --- the emblem --------------------------------------------------------------

## $43E6
func set_up_emblem() -> void:
	var pictures := _pictures(EMBLEM_TILES)
	for row in 7:
		for column in 9:
			var index := row * 9 + column
			_set_up_tile(TILES + index * TILE_SIZE, row * 0x60 - index * 0x10, 0x10 + column * 0x20,
					0x20 + row * 0x20, m.r32(pictures + index * 4))
	set16(RESULT.clock, 0)
	_side_tiles.clear()
	if m.view_margin > 0:
		_widen_emblem(pictures)


## For a picture wider than the original's (the machine's `view_margin`):
## more tiles carry the emblem on to the picture's edges, as far as there
## are records for them, and the tiles grow one after the other across all
## of it in the time they took across the original's.
func _widen_emblem(pictures: int) -> void:
	var first := floori((-m.view_margin - 0x30) / 32.0) + 1
	var last := ceili((0x130 + m.view_margin) / 32.0) - 1
	var columns := []
	for way in maxi(-first, last - 8):
		for column: int in [-1 - way, 9 + way]:
			if column >= first and column <= last:
				columns.append(column)
	for column: int in columns:
		for row in 7:
			var sprite := Sprite.take_record(m)
			if sprite == 0:
				return
			Sprite.picture(m, sprite, m.r32(pictures + (row * 9 + posmod(column, EMBLEM_PERIOD)) * 4))
			Sprite.show(m, sprite, false)
			m.open_records[sprite & 0xFFFF] = true
			_side_tiles.append([sprite, column, row, _wide_delay(row, column, first, last)])
	for index in TILE_COUNT:
		set16(TILES + index * TILE_SIZE + DELAY, _wide_delay(index / 9, index % 9, first, last))


## When the tile at `row` and `column` starts to grow, the columns from
## `first` to `last` taking the time the original's nine take.
static func _wide_delay(row: int, column: int, first: int, last: int) -> int:
	return wrap16(-row * 0x30 - (column - first) * 8 * 0x10 / (last - first))


## $433E
func _set_up_tile(tile: int, delay: int, x: int, y: int, picture: int) -> void:
	set16(tile + DELAY, delay)
	var sprite := Sprite.take_record(m)
	set32(tile + SPRITE, sprite)
	Sprite.picture(m, sprite, picture)
	set16(tile + HOME_X, x)
	set16(tile + HOME_Y, y)


## $4446: the tiles grow from flat lines, one after the other.
func grow_emblem() -> void:
	var clock := u16(RESULT.clock)
	for index in TILE_COUNT:
		_grow_tile(TILES + index * TILE_SIZE, wrap16(clock))
	for tile: Array in _side_tiles:
		_grow_side_tile(tile, wrap16(clock))
	set16(RESULT.clock, clock + 0x10)
	var last := TILES + (TILE_COUNT - 1) * TILE_SIZE
	m.a0 = AFTER_EMBLEM if wrap16(clock + u16(last + DELAY)) > 0x100 else 0


## $4366
func _grow_tile(tile: int, clock: int) -> void:
	var sprite := u32(tile + SPRITE)
	var height := wrap16(clock + u16(tile + DELAY))
	if height < 1:
		Sprite.show(m, sprite, false)
		return
	height = mini(height, 0x100)
	Sprite.zoom(m, sprite, 0x100, height)
	Sprite.place(m, sprite, u16(tile + HOME_X), u16(tile + HOME_Y) - (height >> 4))
	set16(sprite + Sprite.PALETTE, 0xFFB0 + mini(height >> 4, 0xF))
	Sprite.show(m, sprite, true)


## A tile of `_side_tiles` as `_grow_tile` grows those of the original.
func _grow_side_tile(tile: Array, clock: int) -> void:
	var sprite: int = tile[0]
	var height := wrap16(clock + tile[3])
	if height < 1:
		Sprite.show(m, sprite, false)
		return
	height = mini(height, 0x100)
	Sprite.zoom(m, sprite, 0x100, height)
	Sprite.place(m, sprite, 0x10 + tile[1] * 0x20, 0x20 + tile[2] * 0x20 - (height >> 4))
	set16(sprite + Sprite.PALETTE, 0xFFB0 + mini(height >> 4, 0xF))
	Sprite.show(m, sprite, true)


## $4498: the emblem's sprite objects make way for the same picture drawn
## as ground.
func clear_emblem() -> void:
	var saved := _registers()
	_draw_backdrop()
	_restore(saved)
	for index in TILE_COUNT:
		Sprite.free_record(m, u32(TILES + index * TILE_SIZE + SPRITE))
	for tile: Array in _side_tiles:
		Sprite.free_record(m, tile[0])
		m.open_records.erase(tile[0] & 0xFFFF)
	_side_tiles.clear()


# --- the title ---------------------------------------------------------------

## $45C2 and $502E: the eight letters of the title.
func set_up_title(screen: Dictionary) -> void:
	var title := " TOTAL  "
	if screen == RESULT:
		title = "PRACTICE" if u16(COURSE) == 0 else " STAGE%s " % char(0x30 + (u16(COURSE) & 0xFF))
	for index in LETTER_COUNT:
		var character := title.unicode_at(index) & 0xFF
		set8(screen.title + index, character)
		_set_up_letter(screen.letters + index * LETTER_SIZE, -index * 0x20, screen.title_x + index * 0x20, character)
	set16(screen.clock, 0)


## $44F0 and $4F5C
func _set_up_letter(letter: int, delay: int, x: int, character: int) -> void:
	set16(letter + DELAY, delay)
	var sprite := Sprite.take_record(m)
	set32(letter + SPRITE, sprite)
	set16(letter + HOME_X, x)
	Sprite.picture(m, sprite, m.r32(_pictures(LETTERS) + character * 4))


## $4666 and $50A2: the letters grow out of the middle of the screen, one
## after the other.
func grow_title(screen: Dictionary) -> void:
	var clock := u16(screen.clock)
	for index in LETTER_COUNT:
		_grow_letter(screen.letters + index * LETTER_SIZE, wrap16(clock))
	set16(screen.clock, clock + 0x20)
	var last: int = screen.letters + (LETTER_COUNT - 1) * LETTER_SIZE
	m.a0 = screen.after_title if wrap16(clock + u16(last + DELAY)) > 0x100 else 0


## $4530 and $4F9C
func _grow_letter(letter: int, clock: int) -> void:
	var sprite := u32(letter + SPRITE)
	var size := wrap16(clock + u16(letter + DELAY))
	if size < 1:
		Sprite.show(m, sprite, false)
		return
	size = mini(size, 0x100)
	Sprite.zoom(m, sprite, size, size)
	set16(sprite + Sprite.PALETTE, 0xFF90 + mini(size >> 4, 0xF))
	var x := (wrap16((s16(letter + HOME_X) - 0xA0) * size) >> 8) + 0xA0
	var y := (wrap16(-0x40 * size) >> 8) + 0x80
	Sprite.place(m, sprite, x - (size >> 4), y - (size >> 4))
	Sprite.show(m, sprite, true)


# --- the list ----------------------------------------------------------------

## $4A56 and $5490
func set_up_list(screen: Dictionary) -> void:
	if screen == RESULT:
		(sibling(Palettes) as Palettes).choose_shades(0)
		_queue_shaded(0x90, screen.shaded[0])
		_queue_shaded(0xA0, screen.shaded[1])
	for row: int in screen.row_count:
		_set_up_row(screen, screen.rows + row * ROW_SIZE, row)
	set16(screen.clock, screen.first_scroll)
	set16(screen.pause, 0)


## The best time shown in a row.
func _best(screen: Dictionary, row: int) -> int:
	if screen == RESULT:
		return u32(u32(COURSE_BESTS + wrap16(u16(COURSE) * 4)) + row * 4)
	return u32(BESTS + row * 4)


## $46C6 and $5102: a row's picture: its place, the name, the time and the
## letter of the car.
func _set_up_row(screen: Dictionary, entry: int, row: int) -> void:
	set16(entry + DELAY, row * ROW_SPACING)
	var best := _best(screen, row)
	var characters := PackedByteArray()
	characters.append_array(_place_characters(row))
	characters.append(0)
	characters.append_array(_name_characters(best + BEST_NAME))
	characters.append(0)
	characters.append_array(_time_characters(screen, u16(best)))
	characters.append(0)
	characters.append(_car_character(u16(best + screen.car)))
	characters.append(0)
	var picture := entry + ROW_PICTURE
	set16(picture, ROW_COLUMNS)
	set16(picture + 2, 1)
	_write_columns(picture + 4, characters)
	var sprite := Sprite.take_record(m)
	set32(entry + SPRITE, sprite)
	Sprite.picture(m, sprite, picture)


## Writes the column of the list's font for each character.
func _write_columns(to: int, characters: PackedByteArray) -> int:
	var font := m.r32(_pictures(LIST_FONT))
	for character in characters:
		m.w32(to, m.r32(font + 4 + character * 8))
		to += 4
	return to


## $487E and $52B8: a place in the list (from 0) as two characters.
func _place_characters(row: int) -> PackedByteArray:
	var place := (row + 1) & 0xFFFF
	return PackedByteArray([0 if place / 10 == 0 else (place / 10 + 0x30) & 0xFF, place % 10 + 0x30])


## $48BA and $52F4: the three characters of a name. A name that ends early
## is cut off there for good.
func _name_characters(name: int) -> PackedByteArray:
	if u8(name) == 0:
		set8(name + 1, 0)
		set8(name + 2, 0)
	elif u8(name + 1) == 0:
		set8(name + 2, 0)
	return PackedByteArray([u8(name), u8(name + 1), u8(name + 2)])


## $491A and $5354: a time as eight characters.
func _time_characters(screen: Dictionary, frames: int) -> PackedByteArray:
	set16(screen.time_text, frames)
	var text := (sibling(Hud) as Hud)._time_as_text(frames).slice(0, 8)
	for index in text.size():
		if text[index] == 0x20:
			# the original takes the byte at address 0 for a blank
			text[index] = m.r8(0)
	return text


## $4A30 and $546A: the car, as a letter.
func _car_character(car: int) -> int:
	return 0x53 if car == 0 else (car + 0x40) & 0xFF


## $4AE4 and $54C8: the list scrolls up through the middle of the screen,
## and stops for a second with this game's row in the middle.
func scroll_list(screen: Dictionary) -> void:
	var scroll := s16(screen.clock)
	for row: int in screen.row_count:
		_show_row(screen, screen.rows + row * ROW_SIZE, scroll, row)
	if scroll > wrap16(u16(screen.rank) * ROW_SPACING):
		scroll -= 1
	else:
		set16(screen.flash, 0)
		var pause := u16(screen.pause)
		if pause >= LIST_PAUSE:
			scroll -= 1
		else:
			set16(screen.pause, pause + 1)
			set16(screen.flash, 1)
	set16(screen.clock, scroll)
	if screen == TOTALS and u16(screen.pause) == 1 and u16(RANK) < 3:
		_request_sound(SOUND_BEST_THREE)
		_request_sound(SOUND_BEST_THREE)
	m.a0 = LAST_SCENE if wrap16(scroll) < -0x40 else 0


## $472E and $515C: a row as it passes: it is tall in the middle of the
## screen and flat at the top and bottom, as if on a drum.
func _show_row(screen: Dictionary, entry: int, scroll: int, row: int) -> void:
	var sprite := u32(entry + SPRITE)
	var turned := wrap16(u16(entry + DELAY) - scroll)
	if turned < -0x40 or turned > 0x40:
		Sprite.show(m, sprite, false)
		return
	var top := (m.r16(screen.heights + ((maxi(turned - 7, -0x40) & 0xFF) * 2)) * 0x30) & 0xFFFF
	var bottom := (m.r16(screen.heights + ((mini(turned + 7, 0x40) & 0xFF) * 2)) * 0x30) & 0xFFFF
	var height := ((bottom - top) & 0xFFFF) / 0x10
	if height == 0:
		height = 1
	height = mini(height, 0x100)
	Sprite.zoom(m, sprite, 0x100, height)
	var palette := 0
	if screen == RESULT:
		palette = 0xF ^ mini(0x10 - (height >> 4), 0xF)
	else:
		var faded := height
		for times in 5:
			faded = (faded * height) >> 8
		palette = mini(0x10 - (faded >> 4), 0xF)
	if row != u16(screen.rank):
		palette = palette + 0xFF90 if screen == RESULT else 0xFF9F
	elif screen == TOTALS or u16(screen.flash) != 0:
		# this game's row is brightest while the list stops at it (on the
		# totals screen the original tests for that and then forgets to)
		palette = 0xFFAF
	else:
		palette += 0xFFA0
	set16(sprite + Sprite.PALETTE, palette)
	Sprite.place(m, sprite, 0x10, ((top + 0xA080) & 0xFFFF) >> 8)
	Sprite.show(m, sprite, true)


## $4B64 and $557C
func clear_list(screen: Dictionary) -> void:
	for row: int in screen.row_count:
		Sprite.free_record(m, u32(screen.rows + row * ROW_SIZE + SPRITE))
