extends GameRoutines
## Going on with a game kept on a memory card, and keeping one there.
##
## An arcade board can have a slot for a card. This port has none: the
## system says so whenever it is asked, and the screens that would follow
## ($1A118, $1A1CA) are never come to.

## What the game asks the system for: the command, and the number the
## game is known by (from the program's header).
const COMMAND := 0x10FDC4
const GAME_NUMBER := 0x10FDCE
const GAME_NUMBER_IN_HEADER := 0x108
const ASK_FOR_GAMES := 1
## The system's answer: $80 when there is no card.
const ANSWER := 0x10FDC6
const NO_CARD := 0x80
## What the system notes for itself while it looks.
const SYSTEM_BUSY := 0x10FCF4
const SYSTEM_STACK := 0x10FD00
const CARD_SERVICE := 0xC00468
## What `ask` leaves behind for the original's code after it.
const WORK := 0x108000
const SAVING := 0x1034F8


func routines() -> Dictionary:
	return {
		0x1A094: func() -> void: _look(false),
		0x1A14A: func() -> void: _look(true),
		0x1A860: ask,
		CARD_SERVICE: answer,
	}


func scratch() -> Dictionary:
	return {0x1A094: ["ccr"], 0x1A14A: ["ccr"], 0x1A860: ["ccr"], CARD_SERVICE: ["ccr"]}


## $1A094 and $1A14A: looks for a card before a game, to go on with one
## kept on it, and after one, to keep it. Leaves 0 in D0 (it is over at
## once) and $FFFF in D1 (there is nothing to show).
func _look(saving: bool) -> void:
	if saving:
		set8(SAVING, 0xFF)
	# as far down the stack as the original is when it asks
	var stack := m.a7
	var a5 := m.a5
	m.a7 = (stack - 58) & 0xFFFFFFFF
	ask()
	m.a7 = stack
	m.a5 = a5
	m.d1 = with_low16(m.d1, 0xFFFF)
	m.d0 = with_low16(m.d0, 0)


## $1A860
func ask() -> void:
	set8(COMMAND, ASK_FOR_GAMES)
	set16(GAME_NUMBER, rom_u16(GAME_NUMBER_IN_HEADER))
	var stack := m.a7
	m.a7 = (stack - 4) & 0xFFFFFFFF
	answer()
	m.a7 = stack
	m.a5 = WORK


## The system's service ($C00468) on a board without a slot.
func answer() -> void:
	set32(SYSTEM_STACK, m.a7 - 4)
	set8(SYSTEM_BUSY, 0xFF)
	set8(ANSWER, NO_CARD)
	m.a5 = 0x10F300
	m.d0 = (m.d0 & 0xFFFFFF00) | 0x30
