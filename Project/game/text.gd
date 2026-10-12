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


func routines() -> Dictionary:
	return {
		0x10052: draw_block_from_registers,
		0x10082: draw_coloured_block_from_registers,
		0x11A34: write_from_registers,
	}


func scratch() -> Dictionary:
	return {0x10052: ["ccr"], 0x10082: ["ccr"], 0x11A34: ["d0", "ccr"]}


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
