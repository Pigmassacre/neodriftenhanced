extends GameRoutines
## What the game has of the arcade board's system program, written anew:
## the players' sticks and buttons, coins and credits, the start of a
## game, and the few services the game calls.
##
## The original's system does a good deal more (it keeps accounts of coins
## and playing time, tests the board, shows its own screens); none of that
## is here. With the translated program loaded the system's own code runs
## instead, and only the services listed in `routines` are replaced.

const Text := preload("res://game/text.gd")
const SoundRequests := preload("res://game/sound_requests.gd")

## Bit 7 is set while the game has the screen.
const GAME_RUNNING := 0x10FD80
## What the game says it is at: 0 setting up, 1 its title or attract mode,
## 2 a game.
const GAME_MODE := 0x10FDAF
const MODE_TITLE := 1
## For each player six bytes: whether a stick is there, what was held the
## frame before, what is held, what was pressed on this frame, the same
## but again and again while it stays held, and the frames to the next
## time.
const PLAYERS := [0x10FD94, 0x10FD9A]
const HELD_BEFORE := 1
const HELD := 2
const PRESSED := 3
const REPEATED := 4
const REPEAT_WAIT := 5
const FIRST_REPEAT := 0x10
const NEXT_REPEAT := 8
## A third stick, which no board of this kind has.
const NO_PLAYER := 0x10FDA0
## Copies of the players' six bytes.
const PLAYER_COPIES := [0x10FEE8, 0x10FEEE]
## The start buttons held and pressed: bit 0 is player 1's, bit 2 player
## 2's. The system keeps the same of all four of its buttons.
const START_HELD := 0x10FDAC
const START_PRESSED := 0x10FDAD
const BUTTONS_HELD := 0x10FEDC
const BUTTONS_PRESSED := 0x10FEDD
## Who starts a game: bit 0 player 1, bit 1 player 2. The game clears the
## bits of those it does not let in.
const STARTING := 0x10FDB4
## What each of the two players needs of credits to go on ($C00450).
const CREDITS_NEEDED := 0x10FDB0
## Seconds left to press start in with a credit in, as two decimal digits,
## and the frames left of the second.
const SECONDS_LEFT := 0x10FDDA
const FRAMES_LEFT := 0x10FDDB
const FRAMES_PER_SECOND := 0x3B
## In the memory the board keeps: the credits (two decimal digits), how
## many coins a credit takes and how many credits they give, the seconds
## to press start in, and 0 unless that time is not kept.
const CREDITS := 0xD00034
const COINS_NEEDED := 0xD0003A
const CREDITS_GIVEN := 0xD0003B
const SECONDS_TO_START := 0xD00044
const UNTIMED := 0xD00043
const MOST_CREDITS := 0x99
## The game's entries: it sets itself up and runs ($122), is told who
## pressed start ($128) and that a coin went in ($134).
const PLAYER_START := 0x128
const COIN_SOUND := 0x134
## The text layer: 40 columns of 32 rows, with the system's blank.
const TEXT_LAYER := 0x7000
const TEXT_CELLS := 0x500
const TEXT_ROWS := 0x20
const SYSTEM_BLANK := 0x20
const GAME_BLANK := 0xFF
const VIDEO_ADDRESS := 0x3C0000
const VIDEO_DATA := 0x3C0002
const VIDEO_STEP := 0x3C0004
## Bit 6 is clear when a switch on the board makes games free.
const SWITCHES := 0x300001
const SPRITE_TILES := 0
## The hardware's sprites: their zooms, then their places down and across.
const SPRITE_ZOOMS := 0x8000
const SPRITE_COUNT := 0x200

## Coins taken that the game has not yet sounded.
var _coins_to_sound := 0
## What the coin slots showed one and two frames ago.
var _coins_before := 0
var _coins_earlier := 0
## Coins towards the next credit.
var _coins := 0
## Frames after a game's start in which the start buttons are left alone.
var _start_wait := 0
## True when the system wants the screen back from the game's attract
## mode, to have it show its title instead: a credit is in.
var wants_title := false
## True from then until the game gives the screen back by itself.
var _title_asked := false


func routines() -> Dictionary:
	return {
		0xC00450: check_credits,
		0xC004C2: clear_text,
		0xC004C8: clear_sprites,
	}


func scratch() -> Dictionary:
	return {0xC00450: ["d0", "d1", "d2", "a0", "a5", "ccr"], 0xC004C2: ["ccr"], 0xC004C8: ["d0.high", "ccr"]}


func _credits() -> int:
	return m.sram[(CREDITS & 0xFFFF) ^ 1]


func _set_credits(credits: int) -> void:
	m.sram[(CREDITS & 0xFFFF) ^ 1] = credits


func _free_play() -> bool:
	return m.r8(SWITCHES) & 0x40 == 0


func _stored(address: int) -> int:
	return m.sram[(address & 0xFFFF) ^ 1]


## A number of two decimal digits as a number, and back.
static func _from_digits(digits: int) -> int:
	return (digits >> 4) * 10 + (digits & 0xF)


static func _to_digits(number: int) -> int:
	return ((number / 10) << 4) | (number % 10)


## $C00450: the game puts in CREDITS_NEEDED what each player needs; what
## the credits do not cover is cleared, player 1 first.
func check_credits() -> void:
	set16(CREDITS_NEEDED + 2, 0)
	if _free_play():
		return
	var credits := _from_digits(_credits())
	for player in 2:
		var needed := _from_digits(u8(CREDITS_NEEDED + player))
		if needed > credits:
			set8(CREDITS_NEEDED + player, 0)
		else:
			credits -= needed


## $C004C2: blanks the text layer; the system's own blank in the columns
## at either side, which no picture shows.
func clear_text() -> void:
	m.w16(VIDEO_STEP, 1)
	m.w16(VIDEO_ADDRESS, TEXT_LAYER + TEXT_ROWS)
	for cell in TEXT_CELLS - 2 * TEXT_ROWS:
		m.w16(VIDEO_DATA, GAME_BLANK)
	for cell in TEXT_ROWS:
		m.w16(VIDEO_DATA, SYSTEM_BLANK)
	m.w16(VIDEO_ADDRESS, TEXT_LAYER)
	for cell in TEXT_ROWS:
		m.w16(VIDEO_DATA, SYSTEM_BLANK)
	_leave_registers(SYSTEM_BLANK)


## $C004C8: takes every sprite of the hardware off the screen.
func clear_sprites() -> void:
	m.w16(VIDEO_STEP, 1)
	m.w16(VIDEO_ADDRESS, SPRITE_ZOOMS)
	for value: int in [0xFFF, 0, 0xBE00]:
		for sprite in SPRITE_COUNT:
			m.w16(VIDEO_DATA, value)
	m.w16(VIDEO_ADDRESS, SPRITE_TILES)
	m.w16(VIDEO_STEP, 2)
	for row in 0x20:
		m.w16(VIDEO_DATA, GAME_BLANK)
	_leave_registers(GAME_BLANK)


## What the system's code leaves in the registers, which the game's own
## clearing of the text ($A26) goes on from.
func _leave_registers(written: int) -> void:
	m.a0 = VIDEO_DATA
	m.d0 = with_low16(m.d0, written)
	m.d1 = with_low16(m.d1, 0xFFFF)


## Once a frame: reads the sticks, buttons and coin slots, and starts a
## game when a start button is pressed with a credit in.
func every_frame() -> void:
	_take_coins()
	_read_players()
	if _start_wait > 0:
		_start_wait -= 1
	elif u8(GAME_RUNNING) & 0x80:
		_start_games()
		if _start_wait == 0 and u8(GAME_MODE) == MODE_TITLE and not _title_asked and _credits() != 0 \
				and _stored(UNTIMED) == 0:
			_title_asked = true
			wants_title = true


## Call when the game gives the screen back by itself.
func screen_given_back() -> void:
	_title_asked = false


func _take_coins() -> void:
	var slots := m.input_coin & 3
	var taken := slots & ~(_coins_before | _coins_earlier)
	_coins_earlier = _coins_before
	_coins_before = slots
	for slot in 2:
		if taken & (1 << slot) == 0:
			continue
		_coins += 1
		var needed := maxi(_stored(COINS_NEEDED + slot * 2), 1)
		if _coins < needed:
			continue
		_coins -= needed
		var given := _from_digits(_stored(CREDITS_GIVEN + slot * 2))
		_set_credits(_to_digits(mini(_from_digits(_credits()) + given, 99)))
		set8(SECONDS_LEFT, _stored(SECONDS_TO_START))
		set8(FRAMES_LEFT, _stored(SECONDS_TO_START + 1))
		_coins_to_sound += 1
	if _coins_to_sound > 0 and _start_wait == 0 and u8(GAME_RUNNING) & 0x80:
		_coins_to_sound -= 1
		m.call_routine(COIN_SOUND)


func _read_players() -> void:
	var held_now := [m.input_p1 & 0xFF, m.input_p2 & 0xFF]
	for player in 2:
		var at: int = PLAYERS[player]
		var held: int = held_now[player]
		var before := u8(at + HELD)
		if held != before:
			set8(at + REPEAT_WAIT, FIRST_REPEAT)
			set8(at + REPEATED, held)
		else:
			var wait := s8(at + REPEAT_WAIT) - 1
			if wait >= 0:
				set8(at + REPEAT_WAIT, wait)
				set8(at + REPEATED, 0)
			else:
				set8(at + REPEAT_WAIT, NEXT_REPEAT)
				set8(at + REPEATED, held)
		set8(at + HELD_BEFORE, before)
		set8(at + HELD, held)
		set8(at + PRESSED, held & ~before)
		for index in 6:
			set8(PLAYER_COPIES[player] + index, u8(at + index))
	var buttons := m.input_start & 0xF
	var pressed := buttons & ~u8(BUTTONS_HELD)
	set8(BUTTONS_HELD, buttons)
	set8(BUTTONS_PRESSED, pressed)
	set8(START_HELD, buttons & 5)
	set8(START_PRESSED, pressed & 5)


func _start_games() -> void:
	var mode := u8(GAME_MODE)
	if mode == 0:
		return
	var pressed := u8(START_PRESSED)
	var starting := (pressed & 1) | ((pressed >> 1) & 2)
	var free := _free_play()
	if starting == 0:
		# with a credit in, the title waits only so long
		if mode != MODE_TITLE or _credits() == 0 or _stored(UNTIMED) != 0 or not _time_is_up():
			return
		starting = 1
	if not free:
		var credits := _from_digits(_credits())
		if starting == 3 and credits < 2:
			starting = 0
		elif credits < 1:
			starting = 0
	set8(STARTING, starting)
	if starting == 0:
		return
	m.call_routine(PLAYER_START)
	var started := u8(STARTING) & 3
	if started == 0:
		return
	_start_wait = 1
	set16(SECONDS_LEFT, 0)
	if not free:
		var players := (started & 1) + (started >> 1)
		_set_credits(_to_digits(maxi(_from_digits(_credits()) - players, 0)))


## Counts the seconds to press start in down; true when none is left.
func _time_is_up() -> bool:
	var seconds := u8(SECONDS_LEFT)
	if seconds == 0:
		return true
	var frames := s8(FRAMES_LEFT) - 1
	if frames >= 0:
		set8(FRAMES_LEFT, frames)
		return false
	set8(FRAMES_LEFT, FRAMES_PER_SECOND)
	seconds = _to_digits(_from_digits(seconds) - 1)
	set8(SECONDS_LEFT, seconds)
	return seconds == 0
