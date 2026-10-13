extends GameRoutines
## The text layer: 40 by 32 cells of 8 by 8 pixels over everything else,
## which the game writes the HUD and all its text on.
##
## A cell is a word of video RAM at CELLS + column * 32 + row: the tile in
## its low 12 bits, the palette in the top 4.

const CELLS := 0x7000
const COLUMN := 0x20
## The video hardware: the address in video RAM, the word there, and how
## far the address moves on after each word written.
const VIDEO_ADDRESS := 0x3C0000
const VIDEO_DATA := 0x3C0002
const VIDEO_STEP := 0x3C0004
## The tiles of a cell with nothing in it, and of one filled in.
const BLANK := 0x20
const FILLED := 0xFF


func routines() -> Dictionary:
	return {
		0xA26: clear,
		0x10052: draw_block_from_registers,
		0x10082: draw_coloured_block_from_registers,
		0x11A34: write_from_registers,
		0x11A02: func() -> void: copy_string(m.a0, m.a1),
		0x11A10: func() -> void: m.d0 = with_low16(m.d0, 0 if same_strings(m.a0, m.a1) else 0xFFFF),
		0x11A62: write_tall_from_registers,
		0x14AF0: write_at_from_registers,
		0x14B38: draw_rows_from_registers,
	}


func scratch() -> Dictionary:
	return {0x11A02: ["ccr"], 0x11A10: ["ccr"], 0x11A62: ["ccr"], 0x14AF0: ["ccr"], 0x14B38: ["ccr"],
			0xA26: ["ccr"], 0x10052: ["ccr"], 0x10082: ["ccr"], 0x11A34: ["d0", "ccr"]}


## $A26: clears the whole layer. The system ROM's routine for it leaves the
## cells of the 38 columns in the middle filled and blanks the first and
## last column; this blanks the top and bottom row as well.
func clear() -> void:
	m.w16(VIDEO_STEP, 1)
	m.w16(VIDEO_ADDRESS, CELLS + COLUMN)
	for cell in 38 * COLUMN:
		m.w16(VIDEO_DATA, FILLED)
	for cell in COLUMN:
		m.w16(VIDEO_DATA, BLANK)
	m.w16(VIDEO_ADDRESS, CELLS)
	for cell in COLUMN:
		m.w16(VIDEO_DATA, BLANK)
	m.w16(VIDEO_STEP, COLUMN)
	for row: int in [0, COLUMN - 1]:
		m.w16(VIDEO_ADDRESS, CELLS + COLUMN + row)
		for column in 38:
			m.w16(VIDEO_DATA, BLANK)
	m.a0 = VIDEO_DATA
	m.d0 = with_low16(m.d0, BLANK)
	m.d1 = with_low16(m.d1, 0xFFFF)


## $10052: draws the block of cells in A3 with its top left at D2.
func draw_block_from_registers() -> void:
	_draw_from_registers(-1)


## $10082: the same in palette D4.
func draw_coloured_block_from_registers() -> void:
	m.d4 = with_low16(m.d4, m.d4 << 12)
	_draw_from_registers((m.d4 >> 12) & 0xF)
	m.d5 = with_low16(m.d5, (m.r16(m.a3 - 2) & 0xFFF) | (m.d4 & 0xFFFF))


func _draw_from_registers(palette: int) -> void:
	var block := m.a3
	var width := m.r16(block)
	var height := m.r16(block + 2)
	draw_block(m, block, low16(m.d2), palette)
	m.a2 = VIDEO_DATA
	m.a3 = block + 4 + width * height * 2
	m.d0 = with_low16(m.d0, 0xFFFF)
	m.d1 = with_low16(m.d1, 0xFFFF)
	m.d2 = with_low16(m.d2, m.d2 + height)
	m.d3 = with_low16(m.d3, width - 1)
	# the original shuts interrupts out while it writes, and lets them all in after
	m.set_sr(m.get_sr() & 0xF8FF)


## $11A34: writes the characters at A0, up to a zero, from cell D0 to the
## right, in palette D1. D2 is added to each to make its tile.
func write_from_registers() -> void:
	var characters := PackedByteArray()
	var at := m.a0
	while m.r8(at) != 0:
		characters.append(m.r8(at))
		at += 1
	write(m, characters, low16(m.d0), low16(m.d1) & 0xF, low16(m.d2))
	m.a0 = at + 1
	m.a1 = VIDEO_DATA
	m.d1 = with_low16(m.d1, ((m.d1 & 0xFFFF) >> 4) | (m.d1 << 12))
	m.set_sr(m.get_sr() & 0xF8FF)


## Draws a block of cells with its top left at `cell`. At `block` in the
## program ROM are its width, its height and then its cells, row by row.
## With a `palette`, the block's own are replaced by it.
static func draw_block(machine: NeoGeoMachine, block: int, cell: int, palette := -1) -> void:
	var width := machine.r16(block)
	var height := machine.r16(block + 2)
	var at := block + 4
	machine.w16(VIDEO_STEP, COLUMN)
	for row in height:
		machine.w16(VIDEO_ADDRESS, (cell + row) & 0xFFFF)
		for column in width:
			var value := machine.r16(at)
			if palette >= 0:
				value = (value & 0xFFF) | (palette << 12)
			machine.w16(VIDEO_DATA, value)
			at += 2


## Writes characters from `cell` to the right. `first_tile` is the tile of
## character 0 of the font used.
static func write(machine: NeoGeoMachine, characters: PackedByteArray, cell: int, palette: int,
		first_tile: int) -> void:
	machine.w16(VIDEO_ADDRESS, cell & 0xFFFF)
	machine.w16(VIDEO_STEP, COLUMN)
	for character in characters:
		machine.w16(VIDEO_DATA, ((character | (palette << 12)) + first_tile) & 0xFFFF)


## $11A02: copies the characters at `from`, up to and with a zero.
func copy_string(from: int, to: int) -> void:
	while true:
		var character := m.r8(from)
		m.w8(to, character)
		if character == 0:
			return
		from += 1
		to += 1


## $11A10
func same_strings(first: int, second: int) -> bool:
	while true:
		var character := m.r8(first)
		if character != m.r8(second):
			return false
		if character == 0:
			return true
		first += 1
		second += 1
	return false


## $11A62: writes the characters at A0, up to a zero, from cell D0 to the
## right in palette D1, each two cells wide and high. A1 has four words for
## each character: its tiles top left, top right, bottom left, bottom right.
func write_tall_from_registers() -> void:
	var palette := (m.d1 & 0xF) << 12 | (m.d1 & 0xFFF0) >> 4
	var at := m.a0
	m.w16(VIDEO_ADDRESS, m.d0 & 0xFFFF)
	while m.r8(at) != 0:
		var tiles := m.a1 + m.r8(at) * 8
		for tile: int in [0, 4, 2, 6]:
			m.w16(VIDEO_STEP, 1 if tile < 4 else COLUMN - 1)
			m.w16(VIDEO_DATA, m.r16(tiles + tile) | palette)
		at += 1
	m.set_sr(m.get_sr() & 0xF8FF)


## $14AF0: writes D1 characters at A3 (or, if D1 is 0, as many as there are
## up to a zero) from column D0 and row D2 to the right. D3 is the top half
## of each cell: the palette and the font.
func write_at_from_registers() -> void:
	var count := low16(m.d1)
	var at := m.a3
	var top := (m.d3 << 8) & 0xFF00
	m.w16(VIDEO_ADDRESS, (CELLS + (m.d0 << 5) + m.d2) & 0xFFFF)
	m.w16(VIDEO_STEP, COLUMN)
	if count > 0:
		for index in count:
			m.w16(VIDEO_DATA, top | m.r8(at + index))
	else:
		while m.r8(at) != 0:
			m.w16(VIDEO_DATA, top | m.r8(at))
			at += 1
	m.set_sr(m.get_sr() & 0xF8FF)


## $14B38: draws the block of cells at A3 with its top left at column D0
## and row D2. Unlike `draw_block`'s, its cells are kept row by row.
func draw_rows_from_registers() -> void:
	draw_rows(m, m.a3, (CELLS + (m.d0 << 5) + m.d2) & 0xFFFF)
	m.set_sr(m.get_sr() & 0xF8FF)


static func draw_rows(machine: NeoGeoMachine, block: int, cell: int) -> void:
	var width := machine.r16(block)
	var height := machine.r16(block + 2)
	var at := block + 4
	machine.w16(VIDEO_STEP, COLUMN)
	for row in height:
		machine.w16(VIDEO_ADDRESS, (cell + row) & 0xFFFF)
		for column in width:
			machine.w16(VIDEO_DATA, machine.r16(at))
			at += 2
