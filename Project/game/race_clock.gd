extends GameRoutines
## The clock of a race: the time left, which checkpoints extend, and the
## times taken, which are kept per course.
##
## Times are in frames, 16.16 fixed point.

## Which course is being driven, and the checkpoints reached on it.
const COURSE := 0x101202
const CHECKPOINTS := 0x101502
## 1 once the time has run out: the race then ends at the next gate.
const TIME_UP := 0x103332
const TIME_LEFT := 0x103334
## How much time passes in a frame.
const TIME_STEP := 0x103338
## The time taken so far, for the display.
const TIME_TAKEN := 0x10333C
## For each of the seven courses the address of its times: seven for the
## stretches between checkpoints, then the whole course.
const COURSE_TIMES := 0x103340
const COURSE_COUNT := 7
const TIMES := 0x10335C
const TIMES_SIZE := 0x22
## By difficulty and by what machine it is: how much time passes in a
## frame, and the address of the times gained by course (14 words).
const DIFFICULTY := 0x1011F8
const MACHINE := 0x101506
const CLOCKS := 0x2DEB4
const WHOLE_COURSE := 0x1C
## Time gained at each checkpoint of this course.
const TIME_GAINED := 0x10344A
## Frames left of showing that a checkpoint was reached.
const CHECKPOINT_SIGN_FRAMES := 0x1032A0
## How long after the time has run out the race is given up: 20 seconds.
const GIVE_UP_AT := -1200


func routines() -> Dictionary:
	return {
		0x169A8: set_up_course_times,
		0x169C4: set_up,
		0x16A44: count_down,
		0x16AA8: gain_time,
		0x16AC4: total_of_all_courses,
		0x16AE8: total_of_course,
		0x149BA: show_checkpoint_sign,
	}


func scratch() -> Dictionary:
	return {
		0x169A8: ["d7", "a0", "a1", "ccr"],
		0x169C4: ["d0", "d1", "d7", "a0", "a1", "ccr"],
		0x16A44: ["d1", "d2", "a0", "ccr"],
		0x16AA8: ["ccr"],
		0x16AC4: ["d7", "ccr"],
		0x16AE8: ["ccr"],
		0x149BA: ["ccr"],
	}


## $16A44: one frame passes. D0 is $FFFF when the race is given up, else 0.
func count_down() -> void:
	var times := u32(COURSE_TIMES + wrap16(u16(COURSE) * 4))
	var stretch := times + wrap16(u16(CHECKPOINTS) * 4)
	var step := u32(TIME_STEP)
	set32(stretch, u32(stretch) + step)
	set32(times + WHOLE_COURSE, u32(times + WHOLE_COURSE) + step)
	set32(TIME_TAKEN, u32(times + WHOLE_COURSE))
	set32(TIME_LEFT, u32(TIME_LEFT) - step)
	if s32(TIME_LEFT) <= 0:
		set16(TIME_UP, 1)
	m.d0 = with_low16(m.d0, 0xFFFF if s16(TIME_LEFT) <= GIVE_UP_AT else 0)


## $16AA8: a checkpoint gives more time.
func gain_time() -> void:
	m.a0 = TIME_GAINED
	m.d0 = u32(TIME_GAINED + wrap16(u16(CHECKPOINTS) * 4))
	set32(TIME_LEFT, u32(TIME_LEFT) + m.d0)


## $16AC4: the time taken on all courses together, in D0.
func total_of_all_courses() -> void:
	var total := 0
	for course in COURSE_COUNT:
		total += u32(u32(COURSE_TIMES + course * 4) + WHOLE_COURSE)
	m.d0 = total & 0xFFFFFFFF


## $16AE8: the time taken on the course in D0, in D0.
func total_of_course() -> void:
	m.d0 = u32(u32(COURSE_TIMES + wrap16(low16(m.d0) * 4)) + WHOLE_COURSE)


## $149BA
func show_checkpoint_sign() -> void:
	set16(CHECKPOINT_SIGN_FRAMES, 0x3C)


## $169A8: where each course's times are.
func set_up_course_times() -> void:
	for course in COURSE_COUNT:
		set32(COURSE_TIMES + course * 4, TIMES + course * TIMES_SIZE)


## $169C4: the clock at the start of a race.
func set_up() -> void:
	set16(TIME_UP, 0)
	var times := u32(COURSE_TIMES + wrap16(u16(COURSE) * 4))
	for index in TIMES_SIZE / 2:
		set16(times + index * 2, 0)
	var clock := m.r32(m.r32(CLOCKS + wrap16(u16(DIFFICULTY) * 4)) + wrap16(u16(MACHINE) * 4))
	set32(TIME_STEP, m.r32(clock))
	var gained := m.r32(m.r32(clock + 4) + wrap16(u16(COURSE) * 4))
	for index in 14:
		set16(TIME_GAINED + index * 2, m.r16(gained + index * 2))
	set32(TIME_LEFT, u32(TIME_GAINED))
