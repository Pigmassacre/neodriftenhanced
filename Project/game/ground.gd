extends GameRoutines
## What the course is made of: for every 8 by 8 pixels a code saying what a
## car finds there (a wall and its angle, an edge, or a kind of open ground;
## car.gd's `sense_ground` tells them apart).
##
## The codes are stored packed, in blocks of 128 by 128 pixels (16 by 16
## codes), four to each of the course's cells of 256 by 256 pixels. The last
## four blocks asked for are kept unpacked in work RAM.

## How many cells the course is across and down, the map giving each cell's
## number, and by cell number the addresses of its four packed blocks.
const CELLS_ACROSS := 0x102BFE
const CELLS_DOWN := 0x102C00
const CELL_MAP := 0x102C02
const CELL_COUNT := 0x102C06
const CELL_BLOCKS := 0x102C08
## The unpacked blocks, most recently used first: for each the course
## position of its top left (y, then x) and the address of its 256 codes.
const UNPACKED := 0x1027DE
const UNPACKED_COUNT := 4
const BLOCK_CODES := 0x100
const UNPACKED_CODES := 0x1027FE
## In a packed block a byte below $80 is a code, $80 ends the block, and
## any other byte says how many times the byte after it is repeated.
const PACKED_END := 0x80


func routines() -> Dictionary:
	return {
		0x13E14: func() -> void: set_up(m.a4, m.a5),
		0x13E74: code_at_registers,
	}


func scratch() -> Dictionary:
	return {0x13E14: ["ccr"], 0x13E74: ["ccr"]}


## $13E14: the course's cells are those of the map at `map` and the list of
## blocks at `blocks`, and nothing is unpacked.
func set_up(map: int, blocks: int) -> void:
	set16(CELLS_ACROSS, m.r16(map))
	set16(CELLS_DOWN, m.r16(map + 2))
	set32(CELL_MAP, map + 4)
	set16(CELL_COUNT, m.r16(blocks))
	set32(CELL_BLOCKS, blocks + 2)
	for index in UNPACKED_COUNT:
		set32(UNPACKED + index * 8, 0xFFFFFFFF)
		set32(UNPACKED + index * 8 + 4, UNPACKED_CODES + index * BLOCK_CODES)


## $13E74: the code at D0, D2 on the course, left in the low byte of D0.
func code_at_registers() -> void:
	m.d0 = with_low16(m.d0, code_at(m.d0 & 0xFFFF, m.d2 & 0xFFFF))


func code_at(x: int, y: int) -> int:
	var block := _unpacked_block(x, y)
	return u8(block + ((x >> 3) & 0xF) + ((y << 1) & 0xF0))


## The address of the unpacked block that has x, y, which becomes the most
## recently used.
func _unpacked_block(x: int, y: int) -> int:
	var position := ((y & 0xFF80) << 16) | (x & 0xFF80)
	var found := UNPACKED_COUNT - 1
	for index in UNPACKED_COUNT:
		if u32(UNPACKED + index * 8) == position:
			found = index
			break
	var hit := u32(UNPACKED + found * 8) == position
	# on a miss the block used longest ago gives up its place
	var codes := u32(UNPACKED + found * 8 + 4)
	for index in range(found, 0, -1):
		set32(UNPACKED + index * 8, u32(UNPACKED + index * 8 - 8))
		set32(UNPACKED + index * 8 + 4, u32(UNPACKED + index * 8 - 4))
	set32(UNPACKED, position)
	set32(UNPACKED + 4, codes)
	if not hit:
		_unpack(x, y, codes)
	return codes


func _unpack(x: int, y: int, codes: int) -> void:
	var across := u16(CELLS_ACROSS)
	var column := (x >> 8) % across
	var row := (y >> 8) % u16(CELLS_DOWN)
	var cell := m.r16(u32(CELL_MAP) + (((row * across + column) * 2) & 0xFFFF))
	var blocks := m.r32(u32(CELL_BLOCKS) + ((cell * 4) & 0xFFFF))
	var packed := m.r32(blocks + ((x & 0x80) >> 5) + ((y & 0x80) >> 4))
	var to := codes
	while true:
		var byte := m.r8(packed)
		packed += 1
		if byte < 0x80:
			set8(to, byte)
			to += 1
		elif byte == PACKED_END:
			return
		else:
			var code := m.r8(packed)
			packed += 1
			for count in byte & 0x7F:
				set8(to, code)
				to += 1
