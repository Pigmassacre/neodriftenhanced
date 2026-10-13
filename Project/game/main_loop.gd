extends GameRoutines
## The top of the game: how it is set going, what it does on every frame,
## and the states it goes through from its attract mode to a game and back.
##
## The original is set going by the board's system, waits in a loop for
## each frame to begin and then calls the routine of the state it is in.
## An interrupt at the start of every frame sends the hardware what was
## got ready for it and tells the loop to go on. `frame` here is all of
## that for one frame, for a machine without the translated program
## (NeoGeoMachine.native); with it, the routines listed in `routines`
## replace their originals as those of the other files do.

const System := preload("res://game/system.gd")
const Random := preload("res://game/random.gd")
const Heap := preload("res://game/heap.gd")
const Palettes := preload("res://game/palettes.gd")
const SoundRequests := preload("res://game/sound_requests.gd")
const CreditsLine := preload("res://game/credits_line.gd")
const StartPrompt := preload("res://game/start_prompt.gd")
const Text := preload("res://game/text.gd")

## The state: which of STATES the loop calls.
const STATE := 0x100426
enum {
	SET_UP_ATTRACT, ATTRACT, SET_UP_HOW_TO_PLAY, HOW_TO_PLAY, LOOK_FOR_KEPT_GAME, CHOOSE_KEPT_GAME,
	SET_UP_GAME, GAME, SET_UP_CLOSING, CLOSING, KEEP_GAME, KEEPING_GAME, SET_UP_TITLE, TITLE,
	HOME_14, HOME_15, HOME_16, HOME_17, SET_UP_NAME_ENTRY, NAME_ENTRY,
}
## Set to 1 by the interrupt when a frame begins, cleared by the loop when
## it has done the frame's work.
const FRAME_BEGUN := 0x100424
## The interrupt lets the loop go on only every so many frames: one more
## than PACE. Frames counted towards that, and all frames counted.
const PACE := 0x100400
const PACE_COUNT := 0x100402
const FRAME_COUNT := 0x100404
## The board's settings as words: the level of difficulty first.
const SETTINGS := 0x100406
const SETTING_COUNT := 6
const SYSTEM_SETTINGS := 0x10FD8A
const DEMO_SOUND := 0x10040A
const HOW_TO_PLAY_SHOWN := 0x100410
const LEVEL_TIMES_TWO := 0x1011F8
## The address of the credits, the credits the loop last saw there, and 1
## on a frame they changed.
const CREDITS_ADDRESS := 0x100412
const CREDITS_SEEN := 0x100418
const CREDITS_CHANGED := 0x100420
const SYSTEM_CREDITS := 0xD00034
const TEST_CREDITS := 0x10FE00
## Continues left on a home console, for each player.
const CONTINUES := 0x100416
const CONTINUES_AT_FIRST := 4
## For each player, 1 once they have started a game.
const STARTED := 0x10041A
## 1 while no game is played.
const ATTRACTING := 0x10041C
## 1 when the board is being tested.
const TESTING := 0x100422
const SYSTEM_TESTING := 0x10FE80
const TEST_SOUND := 0x10FE1C
const BOARD_SOUND_OFF := 0xD00046
## What part of the world the board is for, and what follows from it: the
## language (3: English) and 1 for a picture of 50 frames a second.
const REGION := 0x10FD83
const LANGUAGE := 0x100428
const FIFTY_HERTZ := 0x10042A
const LANGUAGES := [0, 1]
const VIDEO_STATUS := 0x3C0006
## 1 while a demonstration is driven.
const DEMO := 0x10042C
## 1 when the game goes on from one kept on a memory card.
const RESUMING := 0x10042E
## The player who plays, and 1 from the attract mode's start until a game.
const PLAYER := 0x1011FC
const IN_ATTRACT := 0x101210
## Bit 7 is set while the game has the screen, and what the system is told
## the game is at: 1 its attract mode, 2 a game.
const GAME_RUNNING := 0x10FD80
const GAME_MODE := 0x10FDAF
const MODE_ATTRACT := 1
const MODE_GAME := 2
## What the system is told of each player: 1 when playing.
const PLAYERS_PLAYING := 0x10FDB6
## Who presses start, from the system; the game leaves the bits of those
## it lets in.
const STARTING := 0x10FDB4
## Work RAM cleared when the game is set going, in long words.
const WORK := 0x100374
const WORK_LAST := 0x103610
const FIELD_1032A2 := 0x1032A2
const TITLE_ASKED_FOR := 0x10FEC5
## The texts of the credits line, in the program and where they are kept.
const CREDIT_TEXT := 0x13DA
const CREDIT_TEXTS := [0x100434, 0x100440]
const LEVEL_TEXT := 0x149E
const LEVEL_TEXT_KEPT := 0x10044C
const INTERRUPTS := 0x3C000C
const STACK := 0x10F300
## What the system asks of the game when it sets it going: 2 its attract
## mode, 3 its title.
const REQUEST := 0x10FDAE
const REQUEST_ATTRACT := 2
const REQUEST_TITLE := 3

const SOUND_04 := 0x04
const SOUND_07 := 0x07
const SOUND_21 := 0x21
const SOUND_22 := 0x22
const SOUND_2B := 0x2B
const REQUEST_SOUND := 0x15256
const SET_DEMO_PLAYING := 0xD704
const SET_UP_ATTRACT_MODE := 0x2336
const ATTRACT_MODE := 0x2416
const SET_UP_HOW := 0x620C
const HOW := 0x641A
const SET_UP_CLOCK := 0x169A8
const LOOK_FOR_GAME := 0x1A094
const SET_UP_NEW_GAME := 0xB044
const RUN_GAME := 0xE20
const SET_UP_CLOSING_PICTURE := 0x994C
const CLOSING_PICTURE := 0x9A82
const KEEP := 0x1A14A
const GAME_WAS_LAST := 0x1696C
const SET_UP_TITLE_SCREEN := 0x16DE
const TITLE_SCREEN := 0x177C
const SET_UP_ENTRY := 0x1C876
const ENTRY := 0x1CA78
const CLEAR_SPRITES := 0x120E0
const GROUND_OFF := 0x133FA
const CLEAR_TEXT := 0xA26

## True when the game is to be set going anew: at first, and when it has
## given the screen back to the system.
var _to_set_going := true
## What the system asks of the game when it next sets it going.
var _request := REQUEST_ATTRACT


func routines() -> Dictionary:
	return {
		0x128: player_start,
		0x134: func() -> void: m.call_routine(0x15146),
		0x200: func() -> void: _set_pace_words(0),
		0x20E: func() -> void: set_pace(low16(m.d0)),
		0x966: take_screen,
		0x9BC: _reset_continues,
		0x9D6: func() -> void: set_playing(low16(m.d1), m.d0 & 0xFF),
		0x9F4: func() -> void: set16(ATTRACTING, m.d0),
		0x9FC: func() -> void: m.d0 = with_low16(m.d0, u16(ATTRACTING)),
		0xA04: clear_work,
		0xAA8: read_settings,
		0xFC8: _load_colours,
		0xFE8: _note_testing,
		0x1004: note_region,
		0x1040: func() -> void: m.d0 = with_low16(m.d0, _english()),
		0x1076: note_credits,
		0x10B0: func() -> void: set16(DEMO, m.d0),
		0x13B4: _copy_credit_texts,
		0x148A: _copy_level_text,
		0x14BA8: func() -> void: set16(FIELD_1032A2, 0),
		0xBFA: set_up_attract,
		0xD34: set_up_how_to_play,
		0xD82: func() -> void: _run(HOW, LOOK_FOR_KEPT_GAME),
		0xD9A: look_for_kept_game,
		0xDF6: set_up_game,
		0xE38: set_up_closing,
		0xE9C: keep_game,
		0xEE0: set_up_title,
		0xEFC: title,
		0xF98: func() -> void: _run(SET_UP_ENTRY, NAME_ENTRY),
		0xFB0: func() -> void: _run(ENTRY, SET_UP_GAME),
	}


func scratch() -> Dictionary:
	var free := ["d0", "d1", "d2", "d3", "d7", "a0", "a1", "a3", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	for address: int in [0x9F4, 0x9FC, 0x10B0, 0x14BA8, 0x200, 0x20E, 0x9BC, 0xFE8, 0x1040]:
		table[address] = ["ccr"]
	table[0x9D6] = ["d1", "a0", "ccr"]
	return table


# --- a frame ---------------------------------------------------------------

## One frame of the game, for a machine without the translated program.
func frame() -> void:
	if _to_set_going:
		set_going()
	begin_frame()
	if _to_set_going:
		set_going()
	elif u16(FRAME_BEGUN) != 0:
		turn()
	# the original steps its random numbers for as long as it waits for the
	# next frame, which no two frames make the same
	for step in 32 + (m.input_p1 & 0x1F) + (u16(FRAME_COUNT) & 7):
		Random.advance(m)


## What the original's interrupt does when a frame begins ($22C).
func begin_frame() -> void:
	var system: System = sibling(System)
	if u8(GAME_RUNNING) & 0x80 == 0:
		system.every_frame()
		return
	sibling(SoundRequests).send_next()
	system.every_frame()
	if system.wants_title:
		system.wants_title = false
		set8(GAME_RUNNING, u8(GAME_RUNNING) & 0x7F)
		_request = REQUEST_TITLE
		_to_set_going = true
		return
	set16(PACE_COUNT, u16(PACE_COUNT) + 1)
	if s16(PACE_COUNT) <= s16(PACE):
		return
	set16(PACE_COUNT, 0)
	sibling(Palettes).send()
	set16(FRAME_COUNT, u16(FRAME_COUNT) + 1)
	if u16(FRAME_BEGUN) == 0:
		set16(FRAME_BEGUN, 1)


## A turn of the original's loop ($B80): the state's routine, then the
## credits line.
func turn() -> void:
	note_credits()
	match u16(STATE):
		SET_UP_ATTRACT:
			set_up_attract()
		ATTRACT:
			attract()
		SET_UP_HOW_TO_PLAY:
			set_up_how_to_play()
		HOW_TO_PLAY:
			_run(HOW, LOOK_FOR_KEPT_GAME)
		LOOK_FOR_KEPT_GAME:
			look_for_kept_game()
		SET_UP_GAME:
			set_up_game()
		GAME:
			m.call_routine(RUN_GAME)
		SET_UP_CLOSING:
			set_up_closing()
		CLOSING:
			closing()
		KEEP_GAME:
			keep_game()
		SET_UP_TITLE:
			set_up_title()
		TITLE:
			title()
		SET_UP_NAME_ENTRY:
			_run(SET_UP_ENTRY, NAME_ENTRY)
		NAME_ENTRY:
			_run(ENTRY, SET_UP_GAME)
		_:
			# the states of a home console and of a memory card, which
			# an arcade board without a slot for one never comes to
			push_error("main loop: state %d" % u16(STATE))
			_to_set_going = true
	if _to_set_going:
		return
	sibling(CreditsLine).draw_credits()
	sibling(CreditsLine).draw_level()
	set16(FRAME_BEGUN, 0)


# --- setting the game going ------------------------------------------------

## What the system and the game do between them when the game is given
## the screen ($122, $744, $B34): everything is cleared and set up for the
## attract mode.
func set_going() -> void:
	_to_set_going = false
	m.a7 = STACK
	set8(GAME_RUNNING, u8(GAME_RUNNING) & 0x7F)
	set8(REQUEST, _request)
	clear_work()
	set32(PLAYERS_PLAYING, 0)
	set16(FRAME_BEGUN, 0)
	set16(STARTED, 0)
	set16(ATTRACTING, 1)
	_set_pace_words(0)
	set_pace(0)
	sibling(Palettes).reset()
	m.call_routine(CLEAR_SPRITES)
	m.call_routine(GROUND_OFF)
	m.call_routine(CLEAR_TEXT)
	sibling(System).clear_sprites()
	_note_testing()
	_reset_continues()
	take_screen()
	if _request == REQUEST_TITLE:
		set8(TITLE_ASKED_FOR, 1)
		set16(STATE, SET_UP_TITLE)
	else:
		set16(STATE, SET_UP_ATTRACT)
	_request = REQUEST_ATTRACT
	sibling(Heap).reset()
	set16(FIELD_1032A2, 0)
	note_region()
	_load_colours()
	sibling(StartPrompt).reset()
	_copy_credit_texts()
	_copy_level_text()
	sibling(CreditsLine).show()
	sibling(CreditsLine).draw_credits()
	sibling(CreditsLine).draw_level()


## Gives the screen back to the system, which sets the game going anew.
func _give_screen_back() -> void:
	set8(GAME_RUNNING, u8(GAME_RUNNING) & 0x7F)
	sibling(System).screen_given_back()
	_to_set_going = true


## $A04
func clear_work() -> void:
	for address in range(WORK, WORK_LAST + 4, 4):
		set32(address, 0)
	m.a0 = WORK_LAST + 4


func _set_pace_words(pace: int) -> void:
	set16(PACE, pace)
	set16(PACE_COUNT, 0)


## $20E: the loop goes on once in `pace` + 1 frames.
func set_pace(pace: int) -> void:
	set16(PACE_COUNT, 0)
	set16(PACE, pace)
	set8(GAME_RUNNING, u8(GAME_RUNNING) | 0x80)


## $FE8
func _note_testing() -> void:
	set16(TESTING, 1 if u16(SYSTEM_TESTING) != 0 else 0)


## $9BC
func _reset_continues() -> void:
	set8(CONTINUES, CONTINUES_AT_FIRST)
	set8(CONTINUES + 1, CONTINUES_AT_FIRST)


## $966: takes the screen from the system.
func take_screen() -> void:
	set8(GAME_RUNNING, u8(GAME_RUNNING) & 0x7F)
	m.w16(VIDEO_STATUS, 0)
	m.w16(INTERRUPTS, 7)
	m.set_sr(0x2000 | (m.get_sr() & 0xFF))
	set8(GAME_MODE, MODE_ATTRACT)
	set8(GAME_RUNNING, u8(GAME_RUNNING) | 0x80)
	m.d0 = with_low16(m.d0, 1)
	sibling(SoundRequests).reset()
	read_settings()


## $AA8
func read_settings() -> void:
	for index in SETTING_COUNT:
		set16(SETTINGS + index * 2, u8(SYSTEM_SETTINGS + index))
	set16(LEVEL_TIMES_TWO, u16(SETTINGS) << 1)
	set32(CREDITS_ADDRESS, SYSTEM_CREDITS if u16(SYSTEM_TESTING) == 0 else TEST_CREDITS)


## $1004
func note_region() -> void:
	set16(FIFTY_HERTZ, 0)
	var region := u8(REGION)
	set16(LANGUAGE, LANGUAGES[region] if region < 2 else _english())


## $1040
func _english() -> int:
	if m.r16(VIDEO_STATUS) & 8 == 0:
		return 3
	set16(FIFTY_HERTZ, 1)
	return 2


## $FC8
func _load_colours() -> void:
	for number: int in [0, 0x10, 0x11]:
		sibling(Palettes).load_set(number)


## $13B4
func _copy_credit_texts() -> void:
	for kept: int in CREDIT_TEXTS:
		sibling(Text).copy_string(CREDIT_TEXT, kept)


## $148A
func _copy_level_text() -> void:
	sibling(Text).copy_string(LEVEL_TEXT, LEVEL_TEXT_KEPT)


## $1076
func note_credits() -> void:
	set16(CREDITS_CHANGED, 0)
	var credits := m.r16(u32(CREDITS_ADDRESS))
	if u16(CREDITS_SEEN) != credits:
		set16(CREDITS_SEEN, credits)
		set16(CREDITS_CHANGED, 1)


## $9D6: tells the system whether `player` plays.
func set_playing(player: int, playing: int) -> void:
	set16(PLAYERS_PLAYING, 0)
	set8(PLAYERS_PLAYING + (0 if player == 0 else 1), playing)
	m.a0 = PLAYERS_PLAYING
	m.d1 = with_low16(m.d1, 0 if player == 0 else 1)


## $128, called by the system when a start button is pressed with a credit
## in: player 1 is let in unless a game is on. (A board for America lets
## either player in, at $806, and a home console at $88A.)
func player_start() -> void:
	if u16(ATTRACTING) == 0:
		set8(STARTING, 0)
		return
	var starting := u8(STARTING)
	var let_in := 0
	if starting & 2 == 0 and starting & 1 != 0 and u8(STARTED) == 0:
		set8(STARTED, 1)
		let_in = 1
		set8(GAME_MODE, MODE_GAME)
		set16(PLAYER, 0)
	set8(STARTING, let_in)
	if let_in != 0:
		set16(ATTRACTING, 0)


# --- the states ------------------------------------------------------------

func _sound(sound: int) -> void:
	m.d0 = with_low16(m.d0, sound)
	m.call_routine(REQUEST_SOUND)


## Calls the routine of a screen; when that leaves 0 in D0 the screen is
## over and the state becomes `next`.
func _run(routine: int, next: int) -> bool:
	m.call_routine(routine)
	if low16(m.d0) != 0:
		return false
	set16(STATE, next)
	return true


## $BFA
func set_up_attract() -> void:
	set16(IN_ATTRACT, 1)
	var silent := u8(TEST_SOUND) != 0 if u16(TESTING) == 1 else m.r8(BOARD_SOUND_OFF) != 0
	_sound(SOUND_04 if silent or u16(DEMO_SOUND) == 0 else SOUND_07)
	_sound(SOUND_21)
	m.d0 = with_low16(m.d0, 1)
	m.call_routine(SET_DEMO_PLAYING)
	sibling(StartPrompt).reset()
	sibling(StartPrompt).update()
	m.call_routine(SET_UP_ATTRACT_MODE)
	if low16(m.d0) != 0:
		return
	set16(DEMO, 0)
	if u16(STARTED) != 0:
		set_playing(u16(PLAYER), 1)
		set16(IN_ATTRACT, 0)
		set16(STATE, SET_UP_HOW_TO_PLAY)
	else:
		set16(STATE, ATTRACT)


## $CC6: the attract mode until it is over or a game is started. Over, the
## system gets the screen back.
func attract() -> void:
	sibling(StartPrompt).update()
	m.call_routine(ATTRACT_MODE)
	if low16(m.d0) != 0:
		return
	if u16(STARTED) == 0:
		_give_screen_back()
		return
	set_playing(u16(PLAYER), 1)
	sibling(CreditsLine).show()
	set16(IN_ATTRACT, 0)
	set16(STATE, SET_UP_HOW_TO_PLAY)


## $D34
func set_up_how_to_play() -> void:
	_sound(SOUND_04)
	_sound(SOUND_07)
	_sound(SOUND_22)
	if u16(HOW_TO_PLAY_SHOWN) == 0:
		set16(STATE, LOOK_FOR_KEPT_GAME)
		return
	m.call_routine(SET_UP_CLOCK)
	_run(SET_UP_HOW, HOW_TO_PLAY)


## $D9A
func look_for_kept_game() -> void:
	set16(RESUMING, 0)
	m.call_routine(LOOK_FOR_GAME)
	if low16(m.d0) != 0:
		return
	set16(STATE, CHOOSE_KEPT_GAME if low16(m.d1) == 0 else SET_UP_NAME_ENTRY)


## $DF6
func set_up_game() -> void:
	set16(DEMO, 1)
	m.d0 = with_low16(m.d0, 0)
	m.call_routine(SET_DEMO_PLAYING)
	_run(SET_UP_NEW_GAME, GAME)


## $E38
func set_up_closing() -> void:
	_sound(SOUND_04)
	_sound(SOUND_07)
	_sound(SOUND_2B)
	_run(SET_UP_CLOSING_PICTURE, CLOSING)


## $E6E: over, the system gets the screen back.
func closing() -> void:
	m.call_routine(CLOSING_PICTURE)
	if low16(m.d0) != 0:
		return
	set16(STATE, SET_UP_ATTRACT)
	set_playing(u16(PLAYER), 0)
	_give_screen_back()


## $E9C
func keep_game() -> void:
	m.call_routine(KEEP)
	if low16(m.d0) != 0:
		return
	m.call_routine(GAME_WAS_LAST)
	set16(STATE, KEEPING_GAME if low16(m.d1) == 0 else SET_UP_CLOSING)


## $EE0
func set_up_title() -> void:
	sibling(StartPrompt).update()
	_run(SET_UP_TITLE_SCREEN, TITLE)


## $EFC
func title() -> void:
	sibling(StartPrompt).update()
	m.call_routine(TITLE_SCREEN)
	if low16(m.d0) != 0:
		return
	set_playing(u16(PLAYER), 1)
	set16(STATE, SET_UP_HOW_TO_PLAY)
