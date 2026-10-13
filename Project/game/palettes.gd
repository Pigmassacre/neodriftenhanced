extends GameRoutines
## Colours. The game keeps its colours as three bytes each (red, green and
## blue, 0 to 31) and hands them to the video hardware a palette of 16 at a
## time, at any brightness: that is how every screen fades in and out.
##
## Palettes are not written at once but queued, and the vertical blank
## interrupt writes what is queued (`send`).

## The queue: 29 entries of the palette's address in the hardware (0 while
## the entry is free) and its 16 colours as the hardware wants them.
const QUEUE := 0x101700
const QUEUE_END := 0x101B14
const ENTRY_SIZE := 0x24
const NEXT_FREE := 0x101B14
const NEXT_SENT := 0x101B18
## For each brightness (0 to $100 in steps of 8) 32 bytes: what each
## strength of a colour becomes. There are two sets of them; SHADES is the
## address of the one in use.
const SHADES := 0x101B1C
const SHADE_SETS := 0x28A4A
const FIRST_SHADES := 0x28A52
const PALETTE_RAM := 0x400000
const PALETTE_SIZE := 0x20
## Sets of colours by number: each the address of a list of addresses,
## ended by 0, of the number of a first palette, a count, and the colours.
const SETS := 0x2A3B4


func routines() -> Dictionary:
	return {
		0x11EEE: reset,
		0x11F22: choose_shades_from_register,
		0x11F3E: send,
		0x12036: queue_from_registers,
		0x1690E: func() -> void: load_set(low16(m.d0)),
		0x16932: func() -> void: _load(m.a3),
	}


func scratch() -> Dictionary:
	return {0x1690E: ["ccr"], 0x16932: ["ccr"], 0x11EEE: ["ccr"], 0x11F22: ["ccr"], 0x11F3E: ["ccr"], 0x12036: ["ccr"]}


## $11EEE: empties the queue.
func reset() -> void:
	for entry in range(QUEUE, QUEUE_END, ENTRY_SIZE):
		set32(entry, 0)
	set32(NEXT_FREE, QUEUE)
	set32(NEXT_SENT, QUEUE)
	set32(SHADES, FIRST_SHADES)


## $11F22: the set of shades in D0 from now on.
func choose_shades_from_register() -> void:
	choose_shades(low16(m.d0))


func choose_shades(shade_set: int) -> void:
	set32(SHADES, m.r32(SHADE_SETS + wrap16(shade_set * 4)))


## $11F3E: writes the queued palettes; called in the vertical blank.
func send() -> void:
	var entry := u32(NEXT_SENT)
	while u32(entry) != 0:
		var palette := u32(entry)
		set32(entry, 0)
		for colour in 16:
			m.w16(palette + colour * 2, u16(entry + 4 + colour * 2))
		entry += ENTRY_SIZE
		if entry == QUEUE_END:
			entry = QUEUE
	set32(NEXT_SENT, entry)
	m.w16(PALETTE_RAM, 0)


## $12036: queues D1 palettes from number D0 on with the colours at A3, at
## brightness D2.
func queue_from_registers() -> void:
	queue(low16(m.d0), low16(m.d1), m.a3, low16(m.d2))


func queue(first: int, count: int, colours: int, brightness: int) -> void:
	var shades := u32(SHADES) + wrap16((brightness & 0xFFF8) * 4)
	var palette := PALETTE_RAM + wrap16(first * PALETTE_SIZE)
	var entry := u32(NEXT_FREE)
	for index in count:
		if u32(entry) != 0:
			# the queue is full: the original waits here for the vertical blank
			send()
		for colour in 16:
			var red := m.r8(shades + (m.r8(colours) & 0x1F))
			var green := m.r8(shades + (m.r8(colours + 1) & 0x1F))
			var blue := m.r8(shades + (m.r8(colours + 2) & 0x1F))
			colours += 3
			# the hardware has the lowest bit of each apart from the rest
			set16(entry + 4 + colour * 2, ((red >> 1) << 8) | ((red & 1) << 14)
					| ((green >> 1) << 4) | ((green & 1) << 13) | (blue >> 1) | ((blue & 1) << 12))
		set32(entry, palette)
		palette += PALETTE_SIZE
		entry += ENTRY_SIZE
		if entry == QUEUE_END:
			entry = QUEUE
	set32(NEXT_FREE, entry)


## $1690E: queues a set of colours at full brightness.
func load_set(number: int) -> void:
	var list := m.r32(SETS + wrap16(number * 4))
	while m.r32(list) != 0:
		_load(m.r32(list))
		list += 4


## $16932
func _load(colours: int) -> void:
	queue(m.r16(colours), m.r16(colours + 2), colours + 4, 0x100)
