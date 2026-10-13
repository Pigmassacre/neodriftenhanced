extends GameRoutines
## "INSERT COIN" or "PUSH 1P START BUTTON", blinking at the bottom of the
## screen while no game is played.

const System := preload("res://game/system.gd")
const Text := preload("res://game/text.gd")

## 1 while no game is played, and not 0 while the credits line is hidden.
const ATTRACTING := 0x10041C
const HIDDEN := 0x100432
const ARCADE := 0x10FD82
## What the system is asked: 1 for each player who would need a credit.
const CREDITS_NEEDED := 0x10FDB0
const CHECK_CREDITS := 0xC00450
## Which text is shown, $FFFF while it is blanked, and the frames left
## until that changes.
const SHOWN := 0x100458
const BLANKED := 0x10045A
const FRAMES := 0x10045C
const FRAMES_SHOWN := 0x28
const FRAMES_BLANKED := 0x14
## The texts, by how many players have a credit, and the blank.
const TEXTS := 0x1650
const BLANK := 0x16C2
const CELL := 0x70F5
const PALETTE := 9
const FONT := 0x300


func routines() -> Dictionary:
	return {
		0x14E8: reset,
		0x14F6: update,
		0x15B6: _restart,
		0x15D0: func() -> void: _draw(low16(m.d0)),
	}


func scratch() -> Dictionary:
	var free := ["d0", "d1", "d2", "d3", "d7", "a0", "a1", "a5", "ccr"]
	return {0x14E8: ["ccr"], 0x14F6: free, 0x15B6: ["ccr"], 0x15D0: free}


## $14E8
func reset() -> void:
	set16(SHOWN, 0)
	_restart()


## $15B6: blanked, and to be shown at once.
func _restart() -> void:
	set16(BLANKED, 0xFFFF)
	set16(FRAMES, 0)


## $14F6: what an arcade board shows for the rest of the world (America
## and a home console have texts of their own).
func update() -> void:
	set32(CREDITS_NEEDED, 0x01010000)
	m.call_routine(CHECK_CREDITS)
	var text := 0 if u32(CREDITS_NEEDED) == 0 else 1
	if text != u16(SHOWN):
		_restart()
	set16(SHOWN, text)
	_draw(text)


## $15D0
func _draw(text: int) -> void:
	if u16(HIDDEN) != 0:
		return
	if u16(ATTRACTING) == 0:
		_write(BLANK)
		return
	set16(FRAMES, u16(FRAMES) - 1)
	if s16(FRAMES) >= 0:
		return
	if u16(BLANKED) == 0:
		set16(FRAMES, FRAMES_SHOWN)
		_write(rom_u32(TEXTS + text * 4))
	else:
		set16(FRAMES, FRAMES_BLANKED)
		_write(BLANK)
	set16(BLANKED, u16(BLANKED) ^ 0xFFFF)


func _write(text: int) -> void:
	var characters := PackedByteArray()
	while rom_u8(text) != 0:
		characters.append(rom_u8(text))
		text += 1
	Text.write(m, characters, CELL, PALETTE, FONT)
	# as the original's routine for it leaves the interrupts
	m.set_sr(m.get_sr() & 0xF8FF)
