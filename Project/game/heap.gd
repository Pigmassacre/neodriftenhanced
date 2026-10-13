extends GameRoutines
## Memory that screens ask for and give back: one stretch of work RAM cut
## into blocks, each behind a header of 16 bytes.

## The address of the first block.
const FIRST := 0x1016E2
const HEAP := 0x103610
## A header: 1 when the block is taken, its size in units of 16 bytes with
## the header, and the blocks before and after it (0 for none).
const TAKEN := 0x00
const UNITS := 0x02
const BEFORE := 0x04
const AFTER := 0x08
const HEADER := 0x10
const UNIT := 0x10
## The header of the one free block there is at first.
const FIRST_HEADER := 0x10FBC


func routines() -> Dictionary:
	return {
		0x10F96: reset,
		0x10FCC: func() -> void: m.a0 = take(low16(m.d0)),
		0x110A2: func() -> void: give_back(m.a0),
	}


func scratch() -> Dictionary:
	return {0x10F96: ["ccr"], 0x10FCC: ["ccr"], 0x110A2: ["ccr"]}


## $10F96: all of it is free again.
func reset() -> void:
	set32(FIRST, HEAP)
	for index in 4:
		set32(HEAP + index * 4, m.r32(FIRST_HEADER + index * 4))


## $10FCC: the address of `size` bytes, or 0 when there is no room.
func take(size: int) -> int:
	var units := (wrap16(size + UNIT - 1) >> 4) + 1
	var block := u32(FIRST)
	while u16(block + TAKEN) == 1 or units > s16(block + UNITS):
		if u16(block + AFTER) == 0:
			return 0
		block = u32(block + AFTER)
	set16(block + TAKEN, 1)
	if units == s16(block + UNITS):
		return block + HEADER
	# the rest of the block becomes a free block of its own
	var rest := block + ((units << 4) & 0xFFFF)
	set16(rest + TAKEN, 0)
	set16(rest + UNITS, u16(block + UNITS) - units)
	set16(block + UNITS, units)
	set32(rest + BEFORE, block)
	set32(rest + AFTER, u32(block + AFTER))
	set32(block + AFTER, rest)
	if u32(rest + AFTER) != 0:
		set32(u32(rest + AFTER) + BEFORE, rest)
	return block + HEADER


## $110A2: gives the bytes at `address` back, joining free neighbours.
func give_back(address: int) -> void:
	var block := address - HEADER
	set16(block + TAKEN, 0)
	var before := u32(block + BEFORE)
	if before != 0 and u16(before + TAKEN) == 0:
		set16(before + UNITS, u16(before + UNITS) + u16(block + UNITS))
		set32(before + AFTER, u32(block + AFTER))
		if u32(block + AFTER) != 0:
			set32(u32(block + AFTER) + BEFORE, before)
		block = before
	var after := u32(block + AFTER)
	if after != 0 and u16(after + TAKEN) == 0:
		set16(block + UNITS, u16(block + UNITS) + u16(after + UNITS))
		set32(block + AFTER, u32(after + AFTER))
		if u32(after + AFTER) != 0:
			set32(u32(after + AFTER) + BEFORE, block)
