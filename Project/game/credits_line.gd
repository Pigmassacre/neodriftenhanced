extends GameRoutines
## The line at the bottom of the screen that says how many credits there
## are, and the difficulty level beside it.

const Text := preload("res://game/text.gd")

## 1 while the line is not shown.
const HIDDEN := 0x100432
## Not 0 on an arcade board.
const ARCADE := 0x10FD82
const SHOWN_ON_ARCADE := 0x10040E
const BOTH_PLAYERS := 0x100428
## The address of the credits, one byte for each player, two decimal
## digits in each.
const CREDITS_ADDRESS := 0x100412
## "CREDIT  00" for each player, and where on screen.
const TEXTS: Array[int] = [0x100434, 0x100440]
const LEFT_CELL := 0x707D
const RIGHT_CELL := 0x737D
const PLURAL := 6
const DIGITS := 8
## "LEVEL-0" and where; shown when LEVEL_SHOWN is not 0.
const LEVEL_SHOWN := 0x10040C
const LEVEL := 0x100406
const LEVEL_TEXT := 0x10044C
const LEVEL_DIGIT := 6
const LEVEL_CELL := 0x721D
const PALETTE := 9
const FONT := 0x300


func routines() -> Dictionary:
	return {
		0x1336: hide,
		0x1340: show,
		0x1352: func() -> void: _write_digits(m.a0, m.d0 & 0xFF, low16(m.d1) != 0),
		0x137E: func() -> void: _draw(m.a0, m.a1, low16(m.d0)),
		0x13E6: draw_credits,
		0x14A6: draw_level,
	}


func scratch() -> Dictionary:
	var free := ["d0", "d1", "d2", "d3", "a0", "a1", "ccr"]
	return {0x1336: ["ccr"], 0x1340: free, 0x1352: free, 0x137E: free, 0x13E6: free, 0x14A6: free}


## $1336
func hide() -> void:
	set16(HIDDEN, 1)


## $1340
func show() -> void:
	set16(HIDDEN, 0)
	draw_credits()
	draw_level()


## $13E6: an arcade board shows the credits of the one player, or of both
## when two can play; a home console always shows both.
func draw_credits() -> void:
	if u16(HIDDEN) != 0:
		return
	var credits := u32(CREDITS_ADDRESS)
	if u8(ARCADE) != 0:
		if u16(SHOWN_ON_ARCADE) == 0:
			return
		if u16(BOTH_PLAYERS) != 1:
			_draw(credits, TEXTS[0], RIGHT_CELL)
			return
	_draw(credits, TEXTS[0], LEFT_CELL)
	_draw(credits + 1, TEXTS[1], RIGHT_CELL)


## $137E: writes the text at `text` with the credits at `credits` in it.
func _draw(credits: int, text: int, cell: int) -> void:
	var count := m.r8(credits)
	set8(text + PLURAL, 0x53 if count >= 2 else 0x20)
	_write_digits(text + DIGITS, count, false)
	_write(text, cell)


## $1352: two decimal digits as characters, with a blank for a leading
## zero if `blanked`.
func _write_digits(to: int, digits: int, blanked: bool) -> void:
	set8(to + 1, (digits & 0xF) + 0x30)
	if not blanked:
		set8(to, (digits >> 4) + 0x30)
	else:
		set8(to, 0x20 if digits >> 4 == 0 else (digits >> 4) + 0x30)


func _write(text: int, cell: int) -> void:
	var characters := PackedByteArray()
	while u8(text) != 0:
		characters.append(u8(text))
		text += 1
	Text.write(m, characters, cell, PALETTE, FONT)
	# as the original's routine for it leaves the interrupts
	m.set_sr(m.get_sr() & 0xF8FF)


## $14A6
func draw_level() -> void:
	if u16(HIDDEN) != 0 or u8(ARCADE) == 0 or u16(LEVEL_SHOWN) == 0:
		return
	set8(LEVEL_TEXT + LEVEL_DIGIT, u16(LEVEL) + 0x31)
	_write(LEVEL_TEXT, LEVEL_CELL)
