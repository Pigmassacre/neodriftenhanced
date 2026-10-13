extends GameRoutines
## The lists of best times: one of whole games and one for each course.
##
## A list is a table of addresses of its entries, kept in order of time,
## with one entry more than is shown: a new time is written to the last
## and the table sorted, which puts it in its place or leaves it last. An
## entry starts with its time (a long word, less is better).

const Text := preload("res://game/text.gd")

## The list of whole games: eleven entries of a time, a name of three
## letters, the grade the time is worth and the car driven.
const GAMES := 0x100002
const GAME_ENTRIES := 11
const ENTRY_NAME := 4
const ENTRY_GRADE := 8
const ENTRY_CAR := 10
## The lists of the courses, by course: six entries of twelve bytes.
const COURSES := 0x1000B2
const COURSE_ENTRIES := 6
const COURSE_ENTRY_SIZE := 12
## The game being played: the car chosen, the name entered, the course,
## where the game came in the list of games and the course in its list,
## the entry the course leaves, and what kind of machine the car is.
const CAR := 0x1011FA
const NAME := 0x1011FE
const COURSE := 0x101202
const RANK := 0x101212
const COURSE_RANK := 0x101214
const COURSE_ENTRY := 0x101216
const MACHINE := 0x101506
## The times a grade takes, by machine: six for a whole game, and by
## course five for a course.
const GAME_GRADES := 0x7DC8
const COURSE_GRADES := 0x7AFC
## By course, a record of the course as driven; the grade of its time.
const COURSE_RESULTS := 0x103340
const RESULT_GRADE := 0x20


func routines() -> Dictionary:
	return {
		0x113A: func() -> void: _sort(m.a0, low16(m.d0)),
		0x117C: find_name,
		0x11A8: add_game,
		0x11CE: sign_game,
		0x12AC: add_course,
		0x12FA: write_course_entry,
		0x7A6C: grade_course,
		0x7AC4: func() -> void: m.d1 = with_low16(m.d1, _grade(rom_u32(rom_u32(COURSE_GRADES + low16(m.d2) * 4) + low16(m.d0) * 4), 4, m.d1)),
		0x7D54: grade_game,
		0x7D98: func() -> void: m.d1 = with_low16(m.d1, _grade(rom_u32(GAME_GRADES + low16(m.d2) * 4), 5, m.d1)),
	}


func scratch() -> Dictionary:
	return {
		0x113A: ["ccr"], 0x117C: ["a0", "a1", "ccr"], 0x11A8: ["ccr"], 0x11CE: ["d0", "a0", "a1", "ccr"],
		0x12AC: ["ccr"], 0x12FA: ["ccr"], 0x7A6C: ["ccr"], 0x7AC4: ["ccr"], 0x7D54: ["ccr"], 0x7D98: ["ccr"],
	}


## $113A: puts the `count` addresses at `table` in order of the times they
## point to, by insertion.
func _sort(table: int, count: int) -> void:
	var end := wrap16(count * 4)
	var at := 4
	var before := 0
	while at < end:
		before = at - 4
		while before >= 0:
			var first := m.r32(table + before)
			var second := m.r32(table + before + 4)
			m.a1 = first
			m.a2 = second
			m.d3 = m.r32(second)
			if m.d3 >= m.r32(first):
				break
			m.w32(table + before + 4, first)
			m.w32(table + before, second)
			before -= 4
		at += 4
	m.d0 = with_low16(m.d0, end)
	m.d1 = at
	if at > 4:
		m.d2 = with_low16(m.d2, before)


## $117C: which entry of the table at A0 has the name at A1, into D0; 10
## when none of the first eleven has.
func find_name() -> void:
	var table := m.a0
	m.a2 = table
	var name := m.a1
	var at := 0
	while at <= 0x28:
		if sibling(Text).same_strings(m.r32(table + at) + ENTRY_NAME, name):
			m.d1 = at >> 2
			m.d0 = with_low16(m.d0, at >> 2)
			return
		at += 4
	m.d1 = at
	m.d0 = with_low16(m.d0, 10)


## $11A8: puts the time in D0 in the list of whole games, under a name
## that no player can enter (`sign_game` writes the player's over it).
func add_game() -> void:
	var entry := m.r32(GAMES + (GAME_ENTRIES - 1) * 4)
	m.w32(entry, m.d0)
	m.w32(entry + ENTRY_NAME, 0xFFFFFF00)
	m.a0 = GAMES
	m.d0 = with_low16(m.d0, GAME_ENTRIES)
	_sort(GAMES, GAME_ENTRIES)


## $11CE: the player's car and name to where the game came in the list.
func sign_game() -> void:
	var entry := m.r32(GAMES + u16(RANK) * 4)
	m.w16(entry + ENTRY_CAR, u16(CAR))
	sibling(Text).copy_string(NAME, entry + ENTRY_NAME)


## $12AC: puts the time in D0 in the list of the course driven; where it
## came into D0, 5 when it is not among the five best.
func add_course() -> void:
	var time := m.d0
	var table := m.r32(COURSES + u16(COURSE) * 4)
	m.w32(m.r32(table + (COURSE_ENTRIES - 1) * 4), time)
	m.a0 = table
	m.d0 = with_low16(m.d0, COURSE_ENTRIES)
	_sort(table, COURSE_ENTRIES)
	var left := COURSE_ENTRIES - 1
	var at := table
	while true:
		m.a1 = m.r32(at)
		at += 4
		if m.r32(m.a1) == time:
			break
		left -= 1
		if left < 0:
			break
	m.a0 = at
	m.d1 = with_low16(m.d1, left)
	m.d0 = with_low16(time, COURSE_ENTRIES - 1 - left)


## $12FA: the entry the course left to where it came in the course's list.
func write_course_entry() -> void:
	var entry := m.r32(m.r32(COURSES + u16(COURSE) * 4) + u16(COURSE_RANK) * 4)
	for index in COURSE_ENTRY_SIZE:
		m.w8(entry + index, u8(COURSE_ENTRY + index))


## The grade a time is worth: `last` + 1 for one better than every time
## of the table, 0 for one that is none of them.
func _grade(table: int, last: int, time: int) -> int:
	var grade := last
	while grade >= 0 and time <= rom_u32(table + grade * 4):
		grade -= 1
	return grade + 1


## $7A6C: grades the time the course came to in its list, into D1 and the
## record of the course.
func grade_course() -> void:
	var course := u16(COURSE)
	var time := m.r32(m.r32(m.r32(COURSES + course * 4) + u16(COURSE_RANK) * 4))
	var grade := _grade(rom_u32(rom_u32(COURSE_GRADES + u16(MACHINE) * 4) + course * 4), 4, time)
	m.w16(m.r32(COURSE_RESULTS + course * 4) + RESULT_GRADE, grade)
	m.d1 = with_low16(time, grade)


## $7D54: grades the time the game came to in the list of whole games.
func grade_game() -> void:
	var entry := m.r32(GAMES + u16(RANK) * 4)
	m.w16(entry + ENTRY_GRADE, _grade(rom_u32(GAME_GRADES + u16(MACHINE) * 4), 5, m.r32(entry)))
