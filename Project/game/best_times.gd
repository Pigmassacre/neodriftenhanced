extends GameRoutines
## The lists of best times: one of whole games and one for each course.
##
## A list is a table of addresses of its entries, kept in order of time,
## with one entry more than is shown: a new time is written to the last
## and the table sorted, which puts it in its place or leaves it last. An
## entry starts with its time (a long word, less is better).

const Text := preload("res://game/text.gd")
const Car := preload("res://game/car.gd")

## What the board keeps of the game's memory while it is off: the lists,
## and two words of the sound's that are not worth keeping.
const KEPT := 0x100000
const KEPT_SIZE := 0x370
const KEPT_END := 0x100374

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
const COURSE_COUNT := 7
## Where the lists' entries are, and the size of an entry of either list.
const GAME_ENTRY_STORE := 0x10002E
const ENTRY_SIZE := 12
const COURSE_TABLES := 0x1000CE
const COURSE_ENTRY_STORE := 0x100176
const COURSE_ENTRY_GRADE := 10
## By the part of the world the board is for: the entries the list of
## whole games starts out with, and for each course those of its list.
const COUNTRY := 0x10FD83
const FIRST_GAMES := 0x1E97E
const FIRST_COURSES := 0x1EA0E
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


## What the game does the first time the board is switched on with it
## ($706): the lists as the program has them, every time graded.
func first_run() -> void:
	for address in range(KEPT, KEPT_END):
		m.w8(address, 0)
	var country := u8(COUNTRY)
	for index in GAME_ENTRIES:
		m.w32(GAMES + index * 4, GAME_ENTRY_STORE + index * ENTRY_SIZE)
	var games := rom_u32(FIRST_GAMES + country * 4)
	for offset in range(0, GAME_ENTRIES * ENTRY_SIZE, 2):
		m.w16(GAME_ENTRY_STORE + offset, m.r16(games + offset))
	var entry := COURSE_ENTRY_STORE
	for course in COURSE_COUNT:
		var table := COURSE_TABLES + course * COURSE_ENTRIES * 4
		m.w32(COURSES + course * 4, table)
		var first := rom_u32(rom_u32(FIRST_COURSES + country * 4) + course * 4)
		for index in COURSE_ENTRIES:
			m.w32(table + index * 4, entry)
			for offset in range(0, ENTRY_SIZE, 2):
				m.w16(entry + offset, m.r16(first + index * ENTRY_SIZE + offset))
			entry += ENTRY_SIZE
	sibling(Car).machine_into_register()
	var machine := low16(m.d0)
	for index in GAME_ENTRIES - 1:
		var game := m.r32(GAMES + index * 4)
		m.w16(game + ENTRY_GRADE, _grade(rom_u32(GAME_GRADES + machine * 4), 5, m.r32(game)))
	for course in COURSE_COUNT:
		var grades := rom_u32(rom_u32(COURSE_GRADES + machine * 4) + course * 4)
		for index in COURSE_ENTRIES - 1:
			var time := m.r32(m.r32(COURSES + course * 4) + index * 4)
			m.w16(time + COURSE_ENTRY_GRADE, _grade(grades, 4, m.r32(time)))


## The lists as bytes, to keep while the game is not running.
func kept() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(KEPT_SIZE)
	for index in KEPT_SIZE:
		bytes[index] = m.r8(KEPT + index)
	return bytes


## Puts back what `kept` gave. False, and nothing done, when `bytes` are
## not lists of this game's.
func restore(bytes: PackedByteArray) -> bool:
	if bytes.size() != KEPT_SIZE:
		return false
	# every entry of every table has to be where an entry can be
	for index in GAME_ENTRIES:
		var entry := bytes.decode_u32(GAMES - KEPT + index * 4)
		if _swapped(entry) < GAME_ENTRY_STORE or _swapped(entry) > COURSE_TABLES - ENTRY_SIZE:
			return false
	for course in COURSE_COUNT:
		if _swapped(bytes.decode_u32(COURSES - KEPT + course * 4)) != COURSE_TABLES + course * COURSE_ENTRIES * 4:
			return false
	for index in COURSE_COUNT * COURSE_ENTRIES:
		var entry := _swapped(bytes.decode_u32(COURSE_TABLES - KEPT + index * 4))
		if entry < COURSE_ENTRY_STORE or entry > KEPT + KEPT_SIZE - ENTRY_SIZE:
			return false
	for address in range(KEPT, KEPT_END):
		m.w8(address, bytes[address - KEPT] if address - KEPT < KEPT_SIZE else 0)
	return true


## A long word read with its bytes the wrong way round, put right.
static func _swapped(value: int) -> int:
	return ((value & 0xFF) << 24) | ((value & 0xFF00) << 8) | ((value >> 8) & 0xFF00) | (value >> 24)


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
