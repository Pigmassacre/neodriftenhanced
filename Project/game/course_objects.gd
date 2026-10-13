extends GameRoutines
## Things on the course: scenery beside the road, and short-lived effects
## such as sparks and smoke.
##
## There is room for 24 at a time (and for more with the machine's
## `more_room`). A course has far more scenery than that,
## so only what lies in a window around the camera exists: as the camera
## moves, the strip of course that comes into the window is searched for
## scenery, and what falls out of the window is removed. Effects are added
## where they happen and remove themselves when their animation ends.
##
## Each thing draws itself with a sprite object (sprite_object.gd), placed
## from its position on the course by `place`.

const Sprite := preload("res://game/sprite_object.gd")

# --- a thing, in A1 ----------------------------------------------------------

const SLOTS := 0x102C0C
const SLOT_COUNT := 24
const SLOT_SIZE := 0x40
## More slots, in work RAM the original never uses, for when the machine
## has `more_room`: a wider picture shows more of the course.
const MORE_SLOTS := 0x108000
const MORE_SLOT_COUNT := 40
## Where the original, setting a course up, has set up its 24 slots
## ($14072), and where it has cleared them away again ($1410E).
const SLOTS_SET_UP := 0x14102
const SLOTS_CLEARED := 0x1413C
## Routine run for it every frame (0 when the slot is free), and the one
## run when it is removed.
const UPDATE := 0x00
const REMOVE := 0x04
const SPRITE := 0x08
## Where it is on the course.
const X := 0x0C
const Y := 0x0E
## Scenery: where its picture's top left is from there, what to add to its
## depth, and a frame count for the kinds that move.
const OFFSET_X := 0x10
const OFFSET_Y := 0x12
const DEPTH := 0x14
const TICKS := 0x16
## Effects: the pictures of the animation, its length and its speed (8.8
## frames, and 8.8 frames a frame), how far it has played, and where the
## picture's top left is.
const PICTURES := 0x10
const LENGTH := 0x14
const SPEED := 0x16
const PLAYED := 0x18
const EFFECT_OFFSET_X := 0x1A
const EFFECT_OFFSET_Y := 0x1C

# --- the course's scenery ----------------------------------------------------

## The course is cut into cells of 256 by 256 pixels: how many across and
## down, and the map giving each cell's number.
const CELLS_ACROSS := 0x10320C
const CELLS_DOWN := 0x10320E
const CELL_MAP := 0x103210
## By cell number, the address of its list of scenery: four bytes each
## (kind as a word, x and y within the cell), ended by a zero kind.
const CELL_LISTS := 0x103216
## By kind, the address of three routines: set up, remove, update.
const KINDS := 0x10321C
## How many lists and kinds there are; nothing reads them.
const CELL_LIST_COUNT := 0x103214
const KIND_COUNT := 0x10321A

## The camera: the course position at the screen's top left, and the zoom
## across and down (8.8). The same a frame ago.
const CAMERA := 0x103220
const CAMERA_BEFORE := 0x103228
const CAMERA_X := 0
const CAMERA_Y := 2
const ZOOM_X := 4
const ZOOM_Y := 6
## The window things exist in, now and a frame ago, and the strip being
## searched: left, top, right, bottom.
const WINDOW := 0x103230
const WINDOW_BEFORE := 0x103238
const STRIP := 0x103240
const SLOTS_TO_GO := 0x103248
## How far the window reaches left of and above the camera, and its size
## less one.
const WINDOW_LEFT := 0x28
const WINDOW_ABOVE := 0x54
const WINDOW_SPAN := 0x1FF
## The furthest the camera zooms out (8.8), for how much of the course a
## wider picture shows.
const FURTHEST_ZOOM := 0xB8

# --- effects -----------------------------------------------------------------

const EFFECT_COUNT := 0x10324A
const EFFECT_LIMIT := 10
## The three routines of an effect, as KINDS has them for scenery.
const EFFECT_KIND := 0x2A15A
## By kind of effect, four words: first picture, length in frames, offsets.
const EFFECTS := 0x29EF2
## The address of the table of all effect pictures, and of all scenery pictures.
const EFFECT_PICTURES := 0x80004
const SCENERY_PICTURES := 0x8000C


## What `_wider` was a frame ago; -1 before the first.
var _wider_before := -1


func routines() -> Dictionary:
	return {
		0x14072: set_up,
		0x1410E: clear_away,
		0x14144: camera_from_registers,
		0x14152: zoom_from_registers,
		0x14160: update_all,
		0x141AA: place,
		0x141FA: add,
		0x14240: remove,
		0x14256: keep_window,
		0x143DC: search_by_column,
		0x144B0: search_by_row,
		0x14584: forget_effects,
		0x1458C: add_effect,
		0x145B2: set_up_effect,
		0x145F8: effect_removed,
		0x14600: play_effect,
		0x16B2C: stand,
		0x16B4E: flutter,
		0x16B9C: sway,
	}


func scratch() -> Dictionary:
	var everything := ["d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7",
			"a0", "a1", "a2", "a3", "a4", "a5", "a6", "ccr"]
	var drawing := ["d0", "d1", "d2", "d3", "a0", "a3", "ccr"]
	return {
		0x14144: ["ccr"],
		0x14152: ["ccr"],
		0x141AA: ["d0", "d2", "a0", "ccr"],
		0x141FA: drawing,
		0x14240: ["ccr"],
		0x14256: everything,
		0x143DC: everything,
		0x144B0: everything,
		0x14584: ["ccr"],
		0x1458C: ["ccr"],
		0x145B2: ["d0", "a0", "a3", "ccr"],
		0x145F8: ["ccr"],
		0x14600: drawing,
		0x16B2C: drawing,
		0x16B4E: drawing,
		0x16B9C: drawing,
	}


func room_hooks() -> Dictionary:
	return {SLOTS_SET_UP: _set_up_more_slots, SLOTS_CLEARED: _clear_more_slots}


func _slot_count() -> int:
	return SLOT_COUNT + (MORE_SLOT_COUNT if m.more_room else 0)


func _slot(index: int) -> int:
	if index < SLOT_COUNT:
		return SLOTS + index * SLOT_SIZE
	return MORE_SLOTS + (index - SLOT_COUNT) * SLOT_SIZE


## Each slot keeps a sprite object for as long as the course lasts. One
## without (the game was started in mid-course) is never used.
func _set_up_more_slots() -> void:
	for index in range(SLOT_COUNT, _slot_count()):
		var slot := _slot(index)
		var sprite := Sprite.take_record(m)
		set32(slot + UPDATE, 0)
		set32(slot + SPRITE, sprite)
		if sprite != 0:
			Sprite.show(m, sprite, false)


func _clear_more_slots() -> void:
	for index in range(SLOT_COUNT, _slot_count()):
		var slot := _slot(index)
		var sprite := u32(slot + SPRITE)
		if sprite == 0:
			continue
		if u32(slot + UPDATE) != 0:
			m.a1 = slot
			remove()
		Sprite.free_record(m, sprite)
		set32(slot + SPRITE, 0)


## $14072: sets up the scenery of a course, seen by a camera at D0, D1
## with zoom D2, D3. A4 is the course's map of cells (cells across, cells
## down, then a word for each cell), A5 its lists of scenery by cell and
## A6 the kinds of scenery (each a count and then addresses). Changes no
## register.
func set_up() -> void:
	set16(CAMERA + CAMERA_X, m.d0)
	set16(CAMERA + CAMERA_Y, m.d1)
	set16(CAMERA + ZOOM_X, m.d2)
	set16(CAMERA + ZOOM_Y, m.d3)
	# a camera a frame ago far enough off for everything to count as new
	set16(CAMERA_BEFORE + CAMERA_X, m.d0)
	set16(CAMERA_BEFORE + CAMERA_Y, m.d1 + WINDOW_SPAN + 1)
	set16(CAMERA_BEFORE + ZOOM_X, m.d2)
	set16(CAMERA_BEFORE + ZOOM_Y, m.d3)
	set16(CELLS_ACROSS, m.r16(m.a4))
	set16(CELLS_DOWN, m.r16(m.a4 + 2))
	set32(CELL_MAP, m.a4 + 4)
	set16(CELL_LIST_COUNT, m.r16(m.a5))
	set32(CELL_LISTS, m.a5 + 2)
	set16(KIND_COUNT, m.r16(m.a6))
	set32(KINDS, m.a6 + 2)
	for index in SLOT_COUNT:
		var slot := _slot(index)
		var sprite := Sprite.take_record(m)
		set32(slot + UPDATE, 0)
		set32(slot + SPRITE, sprite)
		if sprite != 0:
			Sprite.show(m, sprite, false)
	if m.more_room:
		_set_up_more_slots()
	update_all()


## $1410E: removes everything and gives the slots' sprite objects back.
## Changes no register.
func clear_away() -> void:
	var saved := [m.d0, m.a0, m.a1]
	for index in SLOT_COUNT:
		var slot := _slot(index)
		if u32(slot + UPDATE) != 0:
			m.a1 = slot
			remove()
		Sprite.free_record(m, u32(slot + SPRITE))
	if m.more_room:
		_clear_more_slots()
	m.d0 = saved[0]; m.a0 = saved[1]; m.a1 = saved[2]


## $14144: the camera's place in D0 and D2.
func camera_from_registers() -> void:
	set16(CAMERA + CAMERA_X, m.d0)
	set16(CAMERA + CAMERA_Y, m.d2)


## $14152: its zoom in D0 and D2.
func zoom_from_registers() -> void:
	set16(CAMERA + ZOOM_X, m.d0)
	set16(CAMERA + ZOOM_Y, m.d2)


## $14160: one frame of everything on the course. Changes no register.
func update_all() -> void:
	var saved := [m.d0, m.d1, m.d2, m.d3, m.d4, m.d5, m.d6, m.d7,
			m.a0, m.a1, m.a2, m.a3, m.a4, m.a5, m.a6, m.fn, m.fz, m.fv, m.fc, m.fx]
	keep_window()
	var count := _slot_count()
	for index in count:
		var slot := _slot(index)
		var routine := u32(slot + UPDATE)
		if routine != 0:
			m.a0 = routine
			m.a1 = slot
			m.a4 = CAMERA
			m.d0 = routine
			m.d4 = with_low16(m.d4, SLOT_SIZE)
			m.d5 = count - 1 - index
			m.call_routine(routine)
	set32(CAMERA_BEFORE, u32(CAMERA))
	set32(CAMERA_BEFORE + ZOOM_X, u32(CAMERA + ZOOM_X))
	m.d0 = saved[0]; m.d1 = saved[1]; m.d2 = saved[2]; m.d3 = saved[3]
	m.d4 = saved[4]; m.d5 = saved[5]; m.d6 = saved[6]; m.d7 = saved[7]
	m.a0 = saved[8]; m.a1 = saved[9]; m.a2 = saved[10]; m.a3 = saved[11]
	m.a4 = saved[12]; m.a5 = saved[13]; m.a6 = saved[14]
	m.fn = saved[15]; m.fz = saved[16]; m.fv = saved[17]; m.fc = saved[18]; m.fx = saved[19]


## $141AA: puts the thing in A1 on screen, as seen by the camera in A4. Its
## picture's top left is D0 and D2 from its position; D1 is added to its depth.
func place() -> void:
	var slot := m.a1
	var camera := m.a4
	var sprite := u32(slot + SPRITE)
	var zoom_x := s16(camera + ZOOM_X)
	var zoom_y := s16(camera + ZOOM_Y)
	var x := wrap16(u16(slot + X) - m.d0 - u16(camera + CAMERA_X)) * zoom_x >> 8
	var y := wrap16(u16(slot + Y) - m.d2 - u16(camera + CAMERA_Y)) * zoom_y >> 8
	Sprite.place(m, sprite, x, y)
	Sprite.zoom(m, sprite, zoom_x, zoom_y)
	var down := wrap16(u16(slot + Y) - u16(camera + CAMERA_Y)) * zoom_y >> 8
	set16(sprite + Sprite.DEPTH, down + m.d1)
	m.a0 = sprite


## $141FA: adds a thing at D0, D2 on the course. A2 is the address of its
## three routines. Leaves it in A1, or 0 there when every slot is taken.
func add() -> void:
	var kind := m.a2
	m.d3 = with_low16(m.d3, SLOT_SIZE)
	var count := _slot_count()
	for index in count:
		var slot := _slot(index)
		if u32(slot + UPDATE) != 0 or (index >= SLOT_COUNT and u32(slot + SPRITE) == 0):
			continue
		set32(slot + UPDATE, m.r32(kind + 8))
		set32(slot + REMOVE, m.r32(kind + 4))
		set16(slot + X, m.d0)
		set16(slot + Y, m.d2)
		Sprite.show(m, u32(slot + SPRITE), true)
		m.a1 = slot
		m.d0 = 1
		m.d1 = with_low16(m.d1, count - 1 - index)
		m.a0 = m.r32(kind)
		m.call_routine(m.a0)
		return
	m.d1 = with_low16(m.d1, 0xFFFF)
	m.a1 = 0


## $14240: removes the thing in A1.
func remove() -> void:
	var slot := m.a1
	m.a0 = u32(slot + REMOVE)
	m.call_routine(m.a0)
	var sprite := u32(slot + SPRITE)
	Sprite.show(m, sprite, false)
	set32(slot + UPDATE, 0)
	m.a0 = sprite
	m.d0 = with_low16(m.d0, 0)


## $14256: moves the window with the camera: removes what is now outside
## it and searches the strips that came into it.
func keep_window() -> void:
	_show_more_of_course()
	_set_window(WINDOW, CAMERA)
	_set_window(WINDOW_BEFORE, CAMERA_BEFORE)
	var left := s16(WINDOW)
	var top := s16(WINDOW + 2)
	var right := s16(WINDOW + 4)
	var bottom := s16(WINDOW + 6)
	m.d4 = with_low16(m.d4, left)
	m.d5 = with_low16(m.d5, top)
	m.d6 = with_low16(m.d6, right)
	m.d7 = with_low16(m.d7, bottom)
	m.a4 = SLOT_SIZE
	m.a5 = SLOTS_TO_GO
	var count := _slot_count()
	for index in count:
		var slot := _slot(index)
		set16(SLOTS_TO_GO, count - index)
		if u32(slot + UPDATE) != 0:
			var x := s16(slot + X)
			var y := s16(slot + Y)
			if x < left or x > right or y < top or y > bottom:
				m.a1 = slot
				remove()
	set16(SLOTS_TO_GO, 0)
	m.a6 = STRIP
	var left_before := s16(WINDOW_BEFORE)
	if left != left_before:
		if left > left_before:
			set16(STRIP, u16(WINDOW_BEFORE + 4) + 1)
			set16(STRIP + 4, right)
		else:
			set16(STRIP, left)
			set16(STRIP + 4, left_before - 1)
		set16(STRIP + 2, u16(WINDOW_BEFORE + 2))
		set16(STRIP + 6, u16(WINDOW_BEFORE + 6))
		search_by_column()
	var top_before := s16(WINDOW_BEFORE + 2)
	if top != top_before:
		if top > top_before:
			set16(STRIP + 2, u16(WINDOW_BEFORE + 6) + 1)
			set16(STRIP + 6, bottom)
		else:
			set16(STRIP + 2, top)
			set16(STRIP + 6, top_before - 1)
		set16(STRIP, left)
		set16(STRIP + 4, right)
		search_by_row()


## How much further the window reaches to each side for a picture wider
## than the original's.
func _wider() -> int:
	return (m.view_margin << 8) / FURTHEST_ZOOM


## When the picture has become wider since the last frame, searches the
## two strips of course that the window has grown by.
func _show_more_of_course() -> void:
	var wider := _wider()
	var grown := wider - _wider_before
	var first := _wider_before < 0
	_wider_before = wider
	if first or grown <= 0:
		return
	_set_window(WINDOW_BEFORE, CAMERA_BEFORE)
	var left := s16(WINDOW_BEFORE)
	var right := s16(WINDOW_BEFORE + 4)
	for strip_left: int in [left, right - grown + 1]:
		set16(STRIP, strip_left)
		set16(STRIP + 2, u16(WINDOW_BEFORE + 2))
		set16(STRIP + 4, strip_left + grown - 1)
		set16(STRIP + 6, u16(WINDOW_BEFORE + 6))
		m.a6 = STRIP
		search_by_column()


func _set_window(window: int, camera: int) -> void:
	var wider := _wider()
	set16(window, u16(camera + CAMERA_X) - WINDOW_LEFT - wider)
	set16(window + 2, u16(camera + CAMERA_Y) - WINDOW_ABOVE)
	set16(window + 4, u16(window) + WINDOW_SPAN + wider * 2)
	set16(window + 6, u16(window + 2) + WINDOW_SPAN)


## $143DC: adds the scenery in the strip in A6, cell by cell: down each
## column of cells, the columns from left to right.
func search_by_column() -> void:
	var strip := m.a6
	var across := u16(CELLS_ACROSS)
	var down := u16(CELLS_DOWN)
	var cell_x := u16(strip) & 0xFF00
	var column := (cell_x >> 8) % across
	while true:
		var cell_y := u16(strip + 2) & 0xFF00
		var row := (cell_y >> 8) % down
		while true:
			_search_cell(strip, column, row, cell_x, cell_y)
			row = (row + 1) % down
			cell_y = (cell_y + 0x100) & 0xFF00
			if wrap16(cell_y) > s16(strip + 6):
				break
		column = (column + 1) % across
		cell_x = (cell_x + 0x100) & 0xFF00
		if wrap16(cell_x) > s16(strip + 4):
			break


## $144B0: the same along each row of cells, the rows from the top down.
func search_by_row() -> void:
	var strip := m.a6
	var across := u16(CELLS_ACROSS)
	var down := u16(CELLS_DOWN)
	var cell_y := u16(strip + 2) & 0xFF00
	var row := (cell_y >> 8) % down
	while true:
		var cell_x := u16(strip) & 0xFF00
		var column := (cell_x >> 8) % across
		while true:
			_search_cell(strip, column, row, cell_x, cell_y)
			column = (column + 1) % across
			cell_x = (cell_x + 0x100) & 0xFF00
			if wrap16(cell_x) > s16(strip + 4):
				break
		row = (row + 1) % down
		cell_y = (cell_y + 0x100) & 0xFF00
		if wrap16(cell_y) > s16(strip + 6):
			break


## Adds the scenery of one cell that lies in the strip.
func _search_cell(strip: int, column: int, row: int, cell_x: int, cell_y: int) -> void:
	var number := m.r16(u32(CELL_MAP) + (((row * u16(CELLS_ACROSS) + column) * 2) & 0xFFFF))
	var entry := m.r32(u32(CELL_LISTS) + ((number * 4) & 0xFFFF))
	while true:
		var kind := m.r16(entry)
		if kind == 0:
			return
		var x := wrap16(cell_x | m.r8(entry + 2))
		var y := wrap16(cell_y | m.r8(entry + 3))
		if x >= s16(strip) and x <= s16(strip + 4) and y >= s16(strip + 2) and y <= s16(strip + 6):
			m.a2 = m.r32(u32(KINDS) + ((kind * 4) & 0xFFFF))
			m.a4 = entry
			m.a6 = strip
			m.d0 = with_low16(m.d0, x)
			m.d2 = with_low16(m.d2, y)
			m.d4 = with_low16(m.d4, x)
			m.d6 = with_low16(m.d6, y)
			add()
		entry += 4


## $14584
func forget_effects() -> void:
	set16(EFFECT_COUNT, 0)


## $1458C: adds an effect of kind D3 at D0, D2 on the course, playing at
## speed D1 ($100 is one picture a frame). No more than ten at a time.
func add_effect() -> void:
	if u16(EFFECT_COUNT) == EFFECT_LIMIT:
		return
	var saved := [m.d0, m.d1, m.d2, m.d3, m.d4, m.d5, m.a0, m.a1, m.a2, m.a3]
	m.d4 = with_low16(m.d4, m.d1)
	m.d5 = with_low16(m.d5, m.d3)
	m.a2 = EFFECT_KIND
	add()
	m.d0 = saved[0]; m.d1 = saved[1]; m.d2 = saved[2]; m.d3 = saved[3]
	m.d4 = saved[4]; m.d5 = saved[5]
	m.a0 = saved[6]; m.a1 = saved[7]; m.a2 = saved[8]; m.a3 = saved[9]


## $145B2: sets up the effect in A1, of kind D5 and with speed D4.
func set_up_effect() -> void:
	var slot := m.a1
	set16(EFFECT_COUNT, u16(EFFECT_COUNT) + 1)
	set16(slot + SPEED, m.d4)
	var effect := EFFECTS + wrap16(low16(m.d5) << 3)
	set32(slot + PICTURES, m.r32(EFFECT_PICTURES) + wrap16(m.r16(effect) * 4))
	set16(slot + LENGTH, m.r16(effect + 2) << 8)
	set16(slot + PLAYED, 0)
	set16(slot + EFFECT_OFFSET_X, m.r16(effect + 4))
	set16(slot + EFFECT_OFFSET_Y, m.r16(effect + 6))


## $145F8
func effect_removed() -> void:
	set16(EFFECT_COUNT, u16(EFFECT_COUNT) - 1)


## $14600: one frame of the effect in A1: its next picture, or the end of it.
func play_effect() -> void:
	var slot := m.a1
	var played := (u16(slot + PLAYED) + u16(slot + SPEED)) & 0xFFFF
	if played >= u16(slot + LENGTH):
		remove()
		return
	set16(slot + PLAYED, played)
	var picture := m.r32(u32(slot + PICTURES) + ((played >> 6) & 0xFFFC))
	Sprite.picture(m, u32(slot + SPRITE), picture)
	m.a3 = picture
	m.d0 = with_low16(m.d0, u16(slot + EFFECT_OFFSET_X))
	m.d2 = with_low16(m.d2, u16(slot + EFFECT_OFFSET_Y))
	# drawn over what is at the same depth, except the one six frames long
	m.d1 = with_low16(m.d1, 0x1F if u16(slot + LENGTH) == 0x600 else 0xFFDF)
	place()


## $16B2C: scenery that stands still.
func stand() -> void:
	var slot := m.a1
	m.d0 = with_low16(m.d0, u16(slot + OFFSET_X))
	m.d2 = with_low16(m.d2, u16(slot + OFFSET_Y))
	m.d1 = with_low16(m.d1, u16(slot + DEPTH))
	place()


## $16B4E: scenery with two pictures, swapped every eight frames. For these
## the field at DEPTH is the first picture.
func flutter() -> void:
	var slot := m.a1
	var ticks := (u16(slot + TICKS) + 1) & 0xFFFF
	set16(slot + TICKS, ticks)
	_show_scenery(slot, (ticks >> 3) & 1)


## $16B9C: scenery with four pictures, played forwards and back.
func sway() -> void:
	var slot := m.a1
	var ticks := (u16(slot + TICKS) + 1) & 0xFFFF
	set16(slot + TICKS, ticks)
	var step := (ticks >> 1) % 6
	_show_scenery(slot, 6 - step if step >= 4 else step)


func _show_scenery(slot: int, step: int) -> void:
	var number := wrap16(step + u16(slot + DEPTH))
	var picture := m.r32(m.r32(SCENERY_PICTURES) + wrap16(number * 4))
	Sprite.picture(m, u32(slot + SPRITE), picture)
	m.a3 = picture
	m.d0 = with_low16(m.d0, u16(slot + OFFSET_X))
	m.d2 = with_low16(m.d2, u16(slot + OFFSET_Y))
	m.d1 = with_low16(m.d1, 0)
	place()
