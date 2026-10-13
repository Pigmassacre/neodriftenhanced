extends GameRoutines
## The title with a credit in: the game's name, and the seconds left to
## press start in, which the system counts down.

const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")

## Not 0 once a game has been started.
const STARTED := 0x10041A
## The seconds left, in decimal digits a nibble each.
const SECONDS_LEFT := 0x10FDDA
const SECONDS_TEXT := 0x10045E
## The addresses of the three sprite objects of the name.
const SPRITES := 0x100462
const SPRITE_COUNT := 3
## Of each: its picture, where it is across and down.
const PARTS := [[0x1DFE, 0, 0], [0x1BBA, 0x10, 0x28], [0x2302, 0x18, 0xC8]]
const COLOURS := [0x40, 0x10, 0x18BA]
const FULLY_LIT := 0x100
## The writing, and where: a column and a row of the text layer.
const TIME := [0x174E, 0x12, 0x17]
const COPYRIGHT := [0x1753, 0x10, 0x1A]
const RIGHTS := [0x1766, 0x10, 0x1B]
const SECONDS_AT := [0x13, 0x18]
const TEXT_PALETTE := 0x93
const FRAME := 0x1EC2E
const FRAME_AT := [3, 4]
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E
const WRITE_AT := 0x14AF0
const DRAW_ROWS := 0x14B38


func routines() -> Dictionary:
	return {
		0x16DE: set_up,
		0x177C: update,
		0x17E0: set_up_name,
		0x18A2: remove_name,
	}


func scratch() -> Dictionary:
	var free := ["d0.high", "d1", "d2", "d3", "a0", "a1", "a3", "ccr"]
	return {0x16DE: free, 0x177C: free, 0x17E0: free + ["d0"], 0x18A2: ["d0", "a0", "a1", "ccr"]}


## $16DE; leaves 0 in D0.
func set_up() -> void:
	m.call_routine(CLEAR_SPRITES)
	sibling(Palettes).load_set(0)
	for line: Array in [TIME, COPYRIGHT, RIGHTS]:
		_write(line[0], line[1], line[2])
	set_up_name()
	m.d0 = with_low16(m.d0, 0)


func _write(text: int, column: int, row: int) -> void:
	m.a3 = text
	m.d0 = with_low16(m.d0, column)
	m.d2 = with_low16(m.d2, row)
	m.d1 = with_low16(m.d1, 0xFFFF)
	m.d3 = with_low16(m.d3, TEXT_PALETTE)
	m.call_routine(WRITE_AT)


## $17E0
func set_up_name() -> void:
	sibling(Palettes).queue(COLOURS[0], COLOURS[1], COLOURS[2], FULLY_LIT)
	for index in SPRITE_COUNT:
		var part: Array = PARTS[index]
		var sprite := Sprite.take_record(m)
		set32(SPRITES + index * 4, sprite)
		Sprite.place(m, sprite, part[1], part[2])
		m.w16(sprite + Sprite.DEPTH, 0)
		Sprite.picture(m, sprite, part[0])
	m.d0 = with_low16(m.d0, FRAME_AT[0])
	m.d2 = with_low16(m.d2, FRAME_AT[1])
	m.a3 = FRAME
	m.call_routine(DRAW_ROWS)
	m.call_routine(BUILD_SPRITES)


## $177C: 1 in D0 until a game is started, then 0.
func update() -> void:
	if u16(STARTED) != 0:
		remove_name()
		m.d0 = with_low16(m.d0, 0)
		return
	var seconds := u8(SECONDS_LEFT)
	set8(SECONDS_TEXT, 0x30 + (seconds >> 4))
	set8(SECONDS_TEXT + 1, 0x30 + (seconds & 0xF))
	set8(SECONDS_TEXT + 2, 0)
	_write(SECONDS_TEXT, SECONDS_AT[0], SECONDS_AT[1])
	m.d0 = with_low16(m.d0, 1)


## $18A2
func remove_name() -> void:
	for index in SPRITE_COUNT:
		Sprite.free_record(m, u32(SPRITES + index * 4))
