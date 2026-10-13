extends GameRoutines
## The part of the attract mode that lists the ten best games, five at a
## time: place, name and time.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Heap := preload("res://game/heap.gd")
const Text := preload("res://game/text.gd")

## The address of its 41 sprite objects: nine fixed things, then for each
## of five rows the eight characters of a time.
const SPRITES := 0x101162
const SPRITE_COUNT := 41
const ROW_SPRITES := 4
const ROWS := 5
const FRAMES := 0x101166
const FRAMES_A_PAGE := 299
const STATE := 0x101168
enum {FIRST_FIVE, SECOND_FIVE, DONE}
## The best games: the addresses of each one's time (frames, 16.16) and,
## after it, name.
const BESTS := 0x100002
## The address of its pictures, and what each sprite object shows: four
## words (picture, x, y, depth).
const PICTURES := 0x80030
const FIXED := 0x609A
## The backdrop, drawn as ground: where its map and its tiles are kept
## among the pictures.
const BACKDROP_MAP := 0x38
const BACKDROP_TILES := 0x40
## The places as text (four bytes each: "1ST" to "9TH"), and "10TH", which
## starts a character further left.
const PLACES := 0x61E2
const TENTH := 0x6206
const PLACE_CELL := 0x708A
const NAME_CELL := 0x73CA
const ROW_CELLS := 4
const TALL_FONT := 0x2823A
const PLACE_PALETTE := 8
const NAME_PALETTE := 7
## By frames of a second, its hundredths; and by what a time's character
## is (digit, the two marks, blank), its picture.
const HUNDREDTHS := 0x5E62
const TIME_PICTURES := 0x5EEC
const MINUTE_MARK := 0xA
const SECOND_MARK := 0xB
const BLANK := 0xC
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 8
const COLOURS := 0x5F1A
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E
const GROUND_OFF := 0x133FA
const REDRAW_GROUND := 0x1348E


func routines() -> Dictionary:
	return {
		0x5B96: set_up,
		0x5BDA: update,
		0x5BFE: first_five,
		0x5C4C: second_five,
		0x5CAE: done,
		0x5CD2: func() -> void: _take_list(low16(m.d0)),
		0x5CF8: func() -> void: _take_sprites(low16(m.d0)),
		0x5D16: set_up_sprites,
		0x5D3A: func() -> void:
			_set_up_sprite(m.a0, m.a6)
			m.a6 += 8,
		0x5D6C: draw_backdrop,
		0x5DA2: func() -> void: _show_rows(low16(m.d4)),
		0x5DE8: func() -> void: m.d2 = _time_characters(m.d0),
		0x5E9E: func() -> void: _show_time(low16(m.d4), m.d2),
		0x5EFA: load_colours,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "d4", "d7", "a0", "a1", "a3", "a4", "a5", "a6", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	for address: int in [0x5CD2, 0x5CF8, 0x5D16, 0x5D3A, 0x5D6C, 0x5DE8, 0x5E9E, 0x5EFA]:
		table[address] = ["ccr"]
	table[0x5DA2] = ["d0", "d1", "d2", "d3", "d4", "d7", "a0", "a1", "ccr"]
	return table


func _sprite(index: int) -> int:
	return u32(u32(SPRITES) + index * 4)


func _take_list(count: int) -> void:
	var heap := sibling(Heap) as Heap
	heap.reset()
	set32(SPRITES, 0)
	set32(SPRITES, heap.take(count * 4))


func _take_sprites(count: int) -> void:
	for index in count:
		set32(u32(SPRITES) + index * 4, Sprite.take_record(m))


## $5EFA
func load_colours() -> void:
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, 0x100)


## $5B96
func set_up() -> void:
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	load_colours()
	set16(FRAMES, FRAMES_A_PAGE)
	set16(STATE, FIRST_FIVE)
	_take_list(SPRITE_COUNT)
	_take_sprites(SPRITE_COUNT)
	draw_backdrop()
	set_up_sprites()
	m.call_routine(BUILD_SPRITES)
	m.d0 = with_low16(m.d0, 0)


## $5D6C
func draw_backdrop() -> void:
	var saved := [m.d0, m.d1, m.d2, m.d3, m.a4, m.a5]
	m.a4 = m.r32(PICTURES) + BACKDROP_MAP
	m.a5 = m.r32(PICTURES) + BACKDROP_TILES
	m.d0 = with_low16(m.d0, 0x10)
	m.d1 = with_low16(m.d1, 0)
	m.d2 = with_low16(m.d2, 0x100)
	m.d3 = with_low16(m.d3, 0x100)
	m.call_routine(REDRAW_GROUND)
	m.d0 = saved[0]; m.d1 = saved[1]; m.d2 = saved[2]; m.d3 = saved[3]; m.a4 = saved[4]; m.a5 = saved[5]


## $5D16
func set_up_sprites() -> void:
	for index in SPRITE_COUNT:
		_set_up_sprite(_sprite(index), FIXED + index * 8)


## $5D3A
func _set_up_sprite(sprite: int, entry: int) -> void:
	Sprite.picture(m, sprite, m.r32(m.r32(PICTURES) + wrap16(m.r16(entry) * 4)))
	Sprite.place(m, sprite, m.r16(entry + 2), m.r16(entry + 4))
	set16(sprite + Sprite.DEPTH, m.r16(entry + 6))


## $5BDA: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	match u16(STATE):
		FIRST_FIVE: first_five()
		SECOND_FIVE: second_five()
		DONE: done()
	m.call_routine(BUILD_SPRITES)


func _write_tall(text: int, cell: int, palette: int) -> void:
	m.a0 = text
	m.a1 = TALL_FONT
	m.d0 = with_low16(m.d0, cell)
	m.d1 = with_low16(m.d1, palette)
	(sibling(Text) as Text).write_tall_from_registers()


## $5BFE
func first_five() -> void:
	for row in ROWS:
		_write_tall(PLACES + row * 4, PLACE_CELL + row * ROW_CELLS, PLACE_PALETTE)
	_show_rows(0)
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) < 0:
		set16(FRAMES, FRAMES_A_PAGE)
		set16(STATE, SECOND_FIVE)
	m.d0 = with_low16(m.d0, 1)


## $5C4C
func second_five() -> void:
	for row in ROWS - 1:
		_write_tall(PLACES + (ROWS + row) * 4, PLACE_CELL + row * ROW_CELLS, PLACE_PALETTE)
	_write_tall(TENTH, PLACE_CELL + (ROWS - 1) * ROW_CELLS - 2 * Text.COLUMN, PLACE_PALETTE)
	_show_rows(ROWS)
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) < 0:
		set16(STATE, DONE)
	m.d0 = with_low16(m.d0, 1)


## $5CAE
func done() -> void:
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	(sibling(Heap) as Heap).give_back(u32(SPRITES))
	m.call_routine(CLEAR_TEXT)
	m.d0 = with_low16(m.d0, 0)


## $5DA2: five games from place `first` on: the times and the names.
func _show_rows(first: int) -> void:
	for row in ROWS:
		var best := u32(BESTS + wrap16((first + row) * 4))
		_show_time(first + row, _time_characters(u32(best)))
		_write_tall(best + 4, NAME_CELL + row * ROW_CELLS, NAME_PALETTE)


## $5DE8: a time as eight characters of four bits, the first lowest:
## minutes (a blank for no tens), seconds and hundredths, with their marks.
func _time_characters(time: int) -> int:
	var frames := ((time + 0x8000) >> 16) & 0xFFFF
	var hundredths := m.r8(HUNDREDTHS + frames % 60)
	var seconds := frames / 60 % 60
	var minutes := (frames / 3600) & 0xFFFF
	var characters := [BLANK if minutes / 10 == 0 else minutes / 10, minutes % 10, MINUTE_MARK,
			seconds / 10, seconds % 10, SECOND_MARK, hundredths / 10, hundredths % 10]
	var packed := 0
	for index in 8:
		packed |= (characters[index] & 0xF) << (index * 4)
	return packed


## $5E9E: shows the time of a game in the row for its place.
func _show_time(place: int, characters: int) -> void:
	var row := place - ROWS if place >= ROWS else place
	for index in 8:
		var picture := m.r8(TIME_PICTURES + ((characters >> (index * 4)) & 0xF))
		Sprite.picture(m, u32(u32(SPRITES) + wrap16(row * 32 + ROW_SPRITES) + index * 4),
				m.r32(m.r32(PICTURES) + picture * 4))
