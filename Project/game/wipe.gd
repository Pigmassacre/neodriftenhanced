extends GameRoutines
## The curtain that opens on a race and closes after it: cells of the text
## layer that cover the picture, taken away or put back along diagonals
## from two corners at once.

const Text := preload("res://game/text.gd")

## Which diagonal is next (0 to $23), which way it goes (1 opening, 0
## closing), frames to wait until the next step and between steps, and 1
## while it runs.
const DIAGONAL := 0x1016F0
const FRAMES_TO_STEP := 0x1016F2
const FRAMES_A_STEP := 0x1016F4
const OPENING := 0x1016F6
const RUNNING := 0x1016F8
const LAST_DIAGONAL := 0x23
## Cells that cover the picture, cells that let it through, and the two
## edges of the curtain.
const COVER := 0x4020
const CLEAR := 0x40FF
const EDGES: Array[int] = [0x437F, 0x437B]
## For each diagonal from either corner: its first cell and how many cells
## it has, less one.
const DIAGONALS: Array[int] = [0x117CA, 0x1185A]
## From a cell to the next of a diagonal: a column back, a row down.
const ALONG := -0x1F
## One more diagonal, covered when a closing curtain has gone past the last.
const EXTRA_DIAGONAL := 0x7460
const EXTRA_LENGTH := 0x20


func routines() -> Dictionary:
	return {
		0x11602: func() -> void: start(m.d0 & 1 != 0, low16(m.d1)),
		0x11646: func() -> void: fill(m.d0 & 1 != 0),
		0x11694: step,
		0x118EA: blank_border,
	}


func scratch() -> Dictionary:
	return {0x11602: ["ccr"], 0x11646: ["ccr"], 0x11694: ["ccr"], 0x118EA: ["ccr"]}


## $11602: starts opening or closing, a diagonal every `frames` + 1 frames.
func start(opening: bool, frames: int) -> void:
	set16(DIAGONAL, LAST_DIAGONAL if opening else 0)
	set16(OPENING, 1 if opening else 0)
	set16(FRAMES_A_STEP, frames)
	set16(FRAMES_TO_STEP, frames)
	set16(RUNNING, 1)
	m.d0 = with_low16(m.d0, 0)


## $11646: the whole layer clear or covering.
func fill(clear: bool) -> void:
	m.w16(Text.VIDEO_ADDRESS, Text.CELLS)
	m.w16(Text.VIDEO_STEP, 1)
	for cell in 0x500:
		m.w16(Text.VIDEO_DATA, CLEAR if clear else COVER)
	var saved := [m.d1, m.a0]
	blank_border()
	m.d1 = saved[0]; m.a0 = saved[1]
	m.set_sr(m.get_sr() & 0xF8FF)
	m.d0 = with_low16(m.d0, 0)


## $11694: a frame of the curtain. Leaves 1 in D0 while it runs.
func step() -> void:
	var running := u16(RUNNING)
	if running != 0:
		if u16(FRAMES_TO_STEP) != 0:
			set16(FRAMES_TO_STEP, u16(FRAMES_TO_STEP) - 1)
		else:
			set16(FRAMES_TO_STEP, u16(FRAMES_A_STEP))
			running = 1 if _move() else 0
		set16(RUNNING, running)
	m.d0 = with_low16(m.d0, running)
	var saved := m.d1
	blank_border()
	m.d1 = saved
	m.set_sr(m.get_sr() & 0xF8FF)


## Moves the curtain on by a diagonal. Returns false at its end.
func _move() -> bool:
	var opening := u16(OPENING) & 1 != 0
	var diagonal := u16(DIAGONAL)
	var next := wrap16(diagonal + (-1 if opening else 1))
	m.w16(Text.VIDEO_STEP, ALONG & 0xFFFF)
	for corner in 2:
		_draw_diagonal(DIAGONALS[corner] + wrap16(diagonal * 4), CLEAR if opening else COVER)
		_draw_diagonal(DIAGONALS[corner] + wrap16(diagonal * 4) + (next - diagonal) * 4, EDGES[corner])
	set16(DIAGONAL, next)
	if next == 0:
		return false
	if (next & 0xFFFF) <= LAST_DIAGONAL - 1:
		return true
	m.w16(Text.VIDEO_ADDRESS, EXTRA_DIAGONAL)
	for cell in EXTRA_LENGTH:
		m.w16(Text.VIDEO_DATA, COVER)
	return false


func _draw_diagonal(entry: int, tile: int) -> void:
	m.w16(Text.VIDEO_ADDRESS, m.r16(entry))
	for cell in m.r16(entry + 2) + 1:
		m.w16(Text.VIDEO_DATA, tile)


## $118EA: blanks the cells around the edge of the layer.
func blank_border() -> void:
	m.w16(Text.VIDEO_STEP, Text.COLUMN)
	for row: int in [0, Text.COLUMN - 1]:
		m.w16(Text.VIDEO_ADDRESS, Text.CELLS + Text.COLUMN + row)
		for column in 38:
			m.w16(Text.VIDEO_DATA, Text.BLANK)
	m.w16(Text.VIDEO_STEP, 1)
	for column: int in [0, 39]:
		m.w16(Text.VIDEO_ADDRESS, Text.CELLS + column * Text.COLUMN)
		for row in Text.COLUMN:
			m.w16(Text.VIDEO_DATA, Text.BLANK)
	m.a0 = Text.VIDEO_DATA
	m.d1 = with_low16(m.d1, Text.BLANK)
