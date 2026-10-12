extends GameRoutines
## The course of a game, from choosing a car to the ending.
##
## Three state machines, one inside the other: the game, the courses of a
## game, and the race on a course. The main loop calls `run_game` once a
## frame; each machine calls the routine of its current state, which says
## in D0 whether it goes on (1) or is over (0). Most states come in pairs,
## one that sets a screen up and one that runs it until it is over.
##
## Routines named by their address alone are still translated and not yet
## looked into.

const RaceClock := preload("res://game/race_clock.gd")

## The state of each machine.
const GAME_STATE := 0x101224
const COURSES_STATE := 0x101226
const RACE_STATE := 0x101228
## What the main loop does next; set to this when the game is over.
const MAIN_STATE := 0x100426
const MAIN_GAME_OVER := 0xA

## The player (as the BIOS counts them), and the course driven.
const PLAYER := 0x1011FC
const COURSE := 0x101202
const LAST_COURSE := 6
## How the game ended (0 through the last course, $FFFF given up), how the
## last race ended (the same), copies of the two for the screens after, and
## the same again as the race itself leaves it.
const GAME_RESULT := 0x101204
const RACE_RESULT := 0x101206
const RACE_LOST := 0x101208
const GAME_RESULT_SHOWN := 0x10120A
const CONTINUE_DECLINED := 0x10120C
const RACE_RESULT_SHOWN := 0x10120E
## Where the game came in the list of best times.
const RANK := 0x101212
## What a finished course leaves for the list of best times.
const COURSE_RANK := 0x101214
const COURSE_TIME := 0x101216
const COURSE_ENTRY := 0x10121A
## 1 when other cars are on the course.
const RIVALS_PRESENT := 0x101222
## Not 0 on an arcade board, where a game is continued with credits.
const ARCADE := 0x10FD82
const CREDITS := 0x100408
const CONTINUES_LEFT := 0x100416
## 1 when a game goes on from where an earlier one stopped.
const RESUMING := 0x10042E
const RESUMED_GAME := 0x10349C

const GAME_STATES := 0xB076
const COURSES_STATES := 0xB2D0
const RACE_STATES := 0xB65A

# Game states.
const GAME_SET_UP_CAR_CHOICE := 0
const GAME_CHOOSE_CAR := 1
const GAME_START := 2
const GAME_COURSES := 3
const GAME_SET_UP_END := 4
const GAME_END := 5
const GAME_SET_UP_NAME_ENTRY := 6
const GAME_NAME_ENTRY := 7
const GAME_SET_UP_NAME_ENTRY_RANKED := 8
const GAME_NAME_ENTRY_RANKED := 9
const GAME_SET_UP_RANK_SHOWN := 10
const GAME_RANK_SHOWN := 11
const GAME_OVER := 12
# States of the courses.
const COURSES_SET_UP_INTRODUCTION := 0
const COURSES_INTRODUCTION := 1
const COURSES_SET_UP_RACE := 2
const COURSES_RACE := 3
const COURSES_SET_UP_RESULT := 4
const COURSES_RESULT := 5
const COURSES_SET_UP_CONTINUE := 6
const COURSES_CONTINUE := 7
const COURSES_SET_UP_CAR_CHOICE := 8
const COURSES_CHOOSE_CAR := 9
# States of a race.
const RACE_SET_UP_START := 0
const RACE_START := 1
const RACE_SET_UP_HUD := 2
const RACE_DRIVING := 3
const RACE_SET_UP_FINISH := 4
const RACE_FINISH := 5
const RACE_PAUSE := 6
const RACE_PAUSED := 7

const REQUEST_SOUND := 0x15256
const SOUND_04 := 0x04
const SOUND_06 := 0x06
const SOUND_07 := 0x07
const SOUND_09 := 0x09
const SOUND_22 := 0x22
const SOUND_23 := 0x23
const SOUND_2D := 0x2D
const SOUND_2E := 0x2E

const SET_UP_CAR_CHOICE := 0x15C20
const CHOOSE_CAR := 0x15C9C
const SET_UP_ENDING := 0x4B8A
const ENDING := 0x4CB4
const SET_UP_GAME_OVER := 0x1E39C
const GAME_OVER_SCREEN := 0x1E404
const SET_UP_NAME_ENTRY := 0x84DE
const NAME_ENTRY := 0x8628
const SET_UP_RANK_SHOWN := 0x55A2
const RANK_SHOWN := 0x5606
const SET_UP_INTRODUCTION := 0x1BE56
const INTRODUCTION := 0x1C374
const SET_UP_RESULT := 0x4150
const RESULT := 0x4248
const SET_UP_CONTINUE := 0x15282
const CONTINUE := 0x15354
const SET_UP_START := 0xB978
const START := 0xB98C
const SET_UP_FINISH := 0xBE50
const FINISH := 0xBE90
const RACE_FRAME := 0xB844
## Is the start button of the player in D0 pressed (D0 is 1)?
const START_PRESSED := 0x10DE2
const RIVALS_ON_COURSE := 0xD68C
const TOTAL_OF_COURSE := 0x16AE8
const TOTAL_OF_ALL_COURSES := 0x16AC4
const SHOW_PAUSE := 0xFD34
const HIDE_PAUSE := 0xFD4E
const DRAW_HUD_FRAME := 0xFD74
const SET_UP_TIME_TAKEN := 0xFDB8
const SET_UP_TIME_LEFT := 0xFE60
const SET_UP_SPEED := 0x100BE
const SHOW_CREDITS := 0x14F6


func routines() -> Dictionary:
	return {
		0xE20: run_game,
		0xB064: game_state,
		0xB0AA: game_set_up_car_choice,
		0xB0C4: game_choose_car,
		0xB0DE: game_start,
		0xB0F8: game_courses,
		0xB11C: game_set_up_end,
		0xB166: game_end,
		0xB1BA: game_set_up_name_entry,
		0xB1D4: game_name_entry,
		0xB1EE: game_set_up_name_entry_ranked,
		0xB208: game_name_entry_ranked,
		0xB222: game_set_up_rank_shown,
		0xB23C: game_rank_shown,
		0xB256: game_over,
		0xB270: start_game,
		0xB2BE: courses_state,
		0xB2F8: courses_set_up_introduction,
		0xB330: courses_introduction,
		0xB34A: courses_set_up_race,
		0xB364: courses_race,
		0xB41A: courses_set_up_result,
		0xB458: courses_result,
		0xB4D4: courses_set_up_continue,
		0xB564: courses_continue,
		0xB5D0: courses_set_up_car_choice,
		0xB60E: courses_choose_car,
		0xB628: set_up_race,
		0xB648: race_state,
		0xB67A: race_set_up_start,
		0xB6A8: race_start,
		0xB6C4: race_set_up_hud,
		0xB6E0: race_driving,
		0xB78C: race_set_up_finish,
		0xB7BC: race_finish,
		0xB7EC: race_pause,
		0xB800: race_paused,
		0xB826: set_up_hud,
	}


func scratch() -> Dictionary:
	var all := {}
	for address: int in routines():
		all[address] = ["ccr"]
	return all


## $E20: a frame of the game.
func run_game() -> void:
	game_state()
	if low16(m.d0) == 0:
		set16(MAIN_STATE, MAIN_GAME_OVER)


## $B064
func game_state() -> void:
	_run_state(GAME_STATES, GAME_STATE)


## $B2BE
func courses_state() -> void:
	_run_state(COURSES_STATES, COURSES_STATE)


## $B648
func race_state() -> void:
	_run_state(RACE_STATES, RACE_STATE)


func _run_state(table: int, state: int) -> void:
	m.d0 = with_low16(m.d0, u16(state) * 4)
	m.a0 = rom_u32(table + low16(m.d0))
	m.call_routine(m.a0)


## Calls `routine`; once it says it is over, the machine goes to `next`.
func _run(routine: int, state: int, next: int) -> void:
	m.call_routine(routine)
	if low16(m.d0) == 0:
		set16(state, next)
	m.d0 = with_low16(m.d0, 1)


func _request_sound(sound: int) -> void:
	m.d0 = with_low16(m.d0, sound)
	m.call_routine(REQUEST_SOUND)


# --- the game ----------------------------------------------------------------

## $B0AA
func game_set_up_car_choice() -> void:
	_run(SET_UP_CAR_CHOICE, GAME_STATE, GAME_CHOOSE_CAR)


## $B0C4
func game_choose_car() -> void:
	_run(CHOOSE_CAR, GAME_STATE, GAME_START)


## $B0DE
func game_start() -> void:
	start_game()
	if low16(m.d0) == 0:
		set16(GAME_STATE, GAME_COURSES)
	m.d0 = with_low16(m.d0, 1)


## $B270: a game starts with the practice course, or where the game that
## is taken up again had got to.
func start_game() -> void:
	m.call_routine(0x169A8)
	if u16(RESUMING) == 1:
		m.a0 = RESUMED_GAME
		set16(COURSE, u16(RESUMED_GAME + 0x18))
		m.a0 = RESUMED_GAME + 0x14
		m.a1 = 0x1011FE
		m.call_routine(0x11A02)
		m.call_routine(0x16950)
	else:
		set16(COURSE, 0)
	set16(COURSES_STATE, COURSES_SET_UP_INTRODUCTION)
	m.d0 = with_low16(m.d0, 0)


## $B0F8: the courses, one after the other.
func game_courses() -> void:
	courses_state()
	if low16(m.d0) == 0:
		set16(GAME_RESULT_SHOWN, u16(GAME_RESULT))
		set16(GAME_STATE, GAME_SET_UP_END)
	m.d0 = with_low16(m.d0, 1)


## $B11C: the ending after the last course, or "game over".
func game_set_up_end() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	_request_sound(SOUND_2D)
	_run(SET_UP_ENDING if u16(GAME_RESULT_SHOWN) == 0 else SET_UP_GAME_OVER, GAME_STATE, GAME_END)


## $B166: after the ending a name is asked for, differently for one of the
## three best times.
func game_end() -> void:
	var completed := u16(GAME_RESULT_SHOWN) == 0
	m.call_routine(ENDING if completed else GAME_OVER_SCREEN)
	if low16(m.d0) == 0:
		if not completed:
			set16(GAME_STATE, GAME_OVER)
		elif u16(RANK) < 3:
			set16(GAME_STATE, GAME_SET_UP_NAME_ENTRY_RANKED)
		else:
			set16(GAME_STATE, GAME_SET_UP_NAME_ENTRY)
	m.d0 = with_low16(m.d0, 1)


## $B1BA
func game_set_up_name_entry() -> void:
	_run(SET_UP_NAME_ENTRY, GAME_STATE, GAME_NAME_ENTRY)


## $B1D4
func game_name_entry() -> void:
	_run(NAME_ENTRY, GAME_STATE, GAME_OVER)


## $B1EE
func game_set_up_name_entry_ranked() -> void:
	_run(SET_UP_NAME_ENTRY, GAME_STATE, GAME_NAME_ENTRY_RANKED)


## $B208
func game_name_entry_ranked() -> void:
	_run(NAME_ENTRY, GAME_STATE, GAME_SET_UP_RANK_SHOWN)


## $B222
func game_set_up_rank_shown() -> void:
	_run(SET_UP_RANK_SHOWN, GAME_STATE, GAME_RANK_SHOWN)


## $B23C
func game_rank_shown() -> void:
	_run(RANK_SHOWN, GAME_STATE, GAME_OVER)


## $B256
func game_over() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	m.d0 = with_low16(m.d0, 0)


# --- the courses -------------------------------------------------------------

## $B2F8
func courses_set_up_introduction() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	_request_sound(SOUND_23)
	_run(SET_UP_INTRODUCTION, COURSES_STATE, COURSES_INTRODUCTION)


## $B330
func courses_introduction() -> void:
	_run(INTRODUCTION, COURSES_STATE, COURSES_SET_UP_RACE)


## $B34A
func courses_set_up_race() -> void:
	set_up_race()
	if low16(m.d0) == 0:
		set16(COURSES_STATE, COURSES_RACE)
	m.d0 = with_low16(m.d0, 1)


## $B628
func set_up_race() -> void:
	m.d0 = with_low16(m.d0, u16(COURSE))
	m.call_routine(RIVALS_ON_COURSE)
	set16(RIVALS_PRESENT, m.d0)
	set16(RACE_STATE, RACE_SET_UP_START)
	m.d0 = with_low16(m.d0, 0)


## $B364: the race. A finished course is followed by its result. Out of
## time, the practice course is simply followed by the first course; on any
## other the game is over, unless it can be continued.
func courses_race() -> void:
	race_state()
	if low16(m.d0) != 0:
		return
	m.call_routine(0xDFAC)
	m.call_routine(0xDFC0)
	set16(RACE_RESULT_SHOWN, u16(RACE_RESULT))
	if u16(RACE_RESULT) == 0:
		set16(COURSES_STATE, COURSES_SET_UP_RESULT)
	elif u16(COURSE) == 0:
		set16(RACE_RESULT, 0)
		set16(COURSE, 1)
		set16(COURSES_STATE, COURSES_SET_UP_INTRODUCTION)
	elif u8(ARCADE) != 0 or u16(CONTINUES_LEFT) != 0:
		set16(COURSES_STATE, COURSES_SET_UP_CONTINUE)
	else:
		_give_up()
		return
	m.d0 = with_low16(m.d0, 1)


## The game ends here, without the ending.
func _give_up() -> void:
	m.d0 = with_low16(m.d0, 0)
	m.call_routine(0x9F4)
	m.d0 = with_low16(m.d0, 3)
	m.d1 = with_low16(m.d1, u16(PLAYER))
	m.call_routine(0x9D6)
	set16(GAME_RESULT, 0xFFFF)
	m.d0 = with_low16(m.d0, 0)


## $B41A
func courses_set_up_result() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	_request_sound(SOUND_2D)
	m.call_routine(0xA26)
	_run(SET_UP_RESULT, COURSES_STATE, COURSES_RESULT)


## $B458: after the result comes the next course. After the last one the
## game is over, and its total time is ranked among the best.
func courses_result() -> void:
	m.call_routine(RESULT)
	if low16(m.d0) != 0:
		return
	if s16(COURSE) < LAST_COURSE:
		set16(COURSE, u16(COURSE) + 1)
		set16(COURSES_STATE, COURSES_SET_UP_INTRODUCTION)
		m.d0 = with_low16(m.d0, 1)
		return
	m.d0 = with_low16(m.d0, 3)
	m.d1 = with_low16(m.d1, u16(PLAYER))
	m.call_routine(0x9D6)
	m.call_routine(TOTAL_OF_ALL_COURSES)
	m.call_routine(0x11A8)
	m.a0 = 0x100002
	m.a1 = 0xB4D0
	m.call_routine(0x117C)
	set16(RANK, m.d0)
	m.call_routine(0x7D54)
	m.call_routine(0x11CE)
	set16(GAME_RESULT, 0)
	m.d0 = with_low16(m.d0, 0)


## $B4D4: without a credit the game is over; with one, the player is asked
## whether to continue.
func courses_set_up_continue() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	if u16(CREDITS) == 0:
		_give_up()
		return
	_request_sound(SOUND_2E)
	m.call_routine(SET_UP_CONTINUE)
	if low16(m.d0) == 0:
		m.d0 = with_low16(m.d0, 1)
		m.call_routine(0x9F4)
		m.d0 = with_low16(m.d0, 2)
		m.d1 = with_low16(m.d1, u16(PLAYER))
		m.call_routine(0x9D6)
		m.call_routine(0x15B6)
		m.call_routine(SHOW_CREDITS)
		set16(COURSES_STATE, COURSES_CONTINUE)
	m.d0 = with_low16(m.d0, 1)


## $B564: to continue, the player chooses a car again and repeats the course.
func courses_continue() -> void:
	m.call_routine(SHOW_CREDITS)
	m.call_routine(CONTINUE)
	if low16(m.d0) != 0:
		return
	if u16(CONTINUE_DECLINED) != 0:
		_give_up()
		return
	m.d0 = with_low16(m.d0, 0)
	m.call_routine(0x9F4)
	m.d0 = with_low16(m.d0, 1)
	m.d1 = with_low16(m.d1, u16(PLAYER))
	m.call_routine(0x9D6)
	set16(COURSES_STATE, COURSES_SET_UP_CAR_CHOICE)
	m.d0 = with_low16(m.d0, 1)


## $B5D0
func courses_set_up_car_choice() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	_request_sound(SOUND_22)
	m.call_routine(0xA26)
	_run(SET_UP_CAR_CHOICE, COURSES_STATE, COURSES_CHOOSE_CAR)


## $B60E
func courses_choose_car() -> void:
	_run(CHOOSE_CAR, COURSES_STATE, COURSES_SET_UP_INTRODUCTION)


# --- the race ----------------------------------------------------------------

## $B67A
func race_set_up_start() -> void:
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	_run(SET_UP_START, RACE_STATE, RACE_START)


## $B6A8
func race_start() -> void:
	_run(START, RACE_STATE, RACE_SET_UP_HUD)


## $B6C4
func race_set_up_hud() -> void:
	set_up_hud()
	if low16(m.d0) == 0:
		set16(RACE_STATE, RACE_DRIVING)
	m.d0 = with_low16(m.d0, 1)


## $B826
func set_up_hud() -> void:
	m.call_routine(DRAW_HUD_FRAME)
	m.call_routine(SET_UP_TIME_TAKEN)
	m.call_routine(SET_UP_TIME_LEFT)
	m.call_routine(SET_UP_SPEED)
	m.d0 = with_low16(m.d0, 0)


## $B6E0: the driving, until the race is over. A course finished in time
## is entered in the list of best times. A home console pauses the race
## with the start button.
func race_driving() -> void:
	if u8(ARCADE) == 0:
		m.d0 = with_low16(m.d0, u16(PLAYER))
		m.call_routine(START_PRESSED)
		if low16(m.d0) == 1:
			set16(RACE_STATE, RACE_PAUSE)
			return
	m.call_routine(RACE_FRAME)
	if low16(m.d0) != 0:
		return
	if u16(RACE_LOST) == 0:
		m.d0 = with_low16(m.d0, u16(COURSE))
		m.call_routine(TOTAL_OF_COURSE)
		set32(COURSE_TIME, m.d0)
		m.call_routine(0x12AC)
		set16(COURSE_RANK, m.d0)
		m.call_routine(0x7A6C)
		set16(COURSE_ENTRY + 6, m.d1)
		set16(COURSE_ENTRY + 4, u16(0x1011FA))
		m.a0 = 0x1011FE
		m.a1 = COURSE_ENTRY
		m.call_routine(0x11A02)
		m.call_routine(0x12FA)
		set16(RACE_RESULT, 0)
	else:
		set16(RACE_RESULT, 0xFFFF)
	set16(RACE_STATE, RACE_SET_UP_FINISH)
	m.d0 = with_low16(m.d0, 1)


## $B78C
func race_set_up_finish() -> void:
	_request_sound(SOUND_06)
	_request_sound(SOUND_09)
	_run(SET_UP_FINISH, RACE_STATE, RACE_FINISH)


## $B7BC
func race_finish() -> void:
	m.call_routine(FINISH)
	if low16(m.d0) != 0:
		m.d0 = with_low16(m.d0, 1)
		return
	_request_sound(SOUND_04)
	_request_sound(SOUND_07)
	m.d0 = with_low16(m.d0, 0)


## $B7EC
func race_pause() -> void:
	m.call_routine(SHOW_PAUSE)
	set16(RACE_STATE, RACE_PAUSED)
	m.d0 = with_low16(m.d0, 1)


## $B800: until the start button is pressed again.
func race_paused() -> void:
	m.d0 = with_low16(m.d0, u16(PLAYER))
	m.call_routine(START_PRESSED)
	if low16(m.d0) == 1:
		m.call_routine(HIDE_PAUSE)
		set16(RACE_STATE, RACE_DRIVING)
	m.d0 = with_low16(m.d0, 1)
