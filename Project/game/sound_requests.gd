extends GameRoutines
## Sounds on their way to the sound board.
##
## The game asks for a sound by number; the vertical blank interrupt hands
## the sound board one byte every other frame, so requests wait in a queue
## of eight. The original stops and waits when the queue is full. Here the
## requests that do not fit wait in `_waiting` and the game carries on.

## Frames to wait before the next byte may be sent.
const FRAMES_TO_WAIT := 0x1032AA
## 1 when the first byte of a two-byte request has been sent.
const SENT_FIRST_BYTE := 0x1032A8
const FIELD_1032A6 := 0x1032A6
## The queue: a word for each request (0 when free), where the next one
## goes and which is sent next.
const QUEUE := 0x1032AC
const QUEUE_END := 0x1032BC
const NEXT_SENT := 0x1032BC
const NEXT_FREE := 0x1032C0
## Set to 1 to reset the sound board (it then goes through 2), and set to
## stop the music.
const RESET_STEP := 0x100370
const STOP_MUSIC := 0x100372
## Where the sound board takes its commands.
const SOUND_LATCH := 0x320000
const COMMAND_RESET := 3
const COMMAND_STOP_MUSIC := 0x7F

var _waiting: Array[int] = []


func routines() -> Dictionary:
	return {
		0x15108: reset,
		0x15146: stop_music,
		0x15256: request_from_register,
		0x15150: send_next,
	}


func scratch() -> Dictionary:
	return {0x15108: ["ccr"], 0x15146: ["ccr"], 0x15256: ["ccr"], 0x15150: ["ccr"]}


## $15256: asks for the sound in D0. Numbers above $FF are sent as two bytes.
func request_from_register() -> void:
	request(m.d0 & 0xFFFF)


func request(sound: int) -> void:
	if m.log_sounds:
		print("sound $%04X" % sound)
	if not m.replaced_sounds.is_empty():
		m.sounds_taken.append(sound)
		if m.replaced_sounds.has(sound):
			return
	if not _waiting.is_empty() or u16(u32(NEXT_FREE)) != 0:
		_waiting.append(sound)
	else:
		_queue(sound)


func _queue(sound: int) -> void:
	var free := u32(NEXT_FREE)
	set16(free, sound)
	free += 2
	set32(NEXT_FREE, QUEUE if free == QUEUE_END else free)


## $15150: called from the vertical blank interrupt.
func send_next() -> void:
	while not _waiting.is_empty() and u16(u32(NEXT_FREE)) == 0:
		_queue(_waiting.pop_front())
	if u16(FRAMES_TO_WAIT) != 0:
		set16(FRAMES_TO_WAIT, u16(FRAMES_TO_WAIT) - 1)
		if u16(FRAMES_TO_WAIT) != 0:
			return
	if u16(RESET_STEP) == 1:
		m.w8(SOUND_LATCH, COMMAND_RESET)
		set16(RESET_STEP, 2)
		set16(FRAMES_TO_WAIT, 4)
		return
	if u16(RESET_STEP) != 0:
		m.w8(SOUND_LATCH, 7 if u16(FIELD_1032A6) != 0 else 4)
		set16(RESET_STEP, 0)
		set16(FRAMES_TO_WAIT, 2)
		return
	if u16(STOP_MUSIC) != 0 and u16(SENT_FIRST_BYTE) == 0:
		m.w8(SOUND_LATCH, COMMAND_STOP_MUSIC)
		set16(STOP_MUSIC, 0)
		set16(FRAMES_TO_WAIT, 2)
		return
	var next := u32(NEXT_SENT)
	var sound := u16(next)
	if sound == 0:
		return
	if u16(SENT_FIRST_BYTE) == 0 and sound > 0xFF:
		m.w8(SOUND_LATCH, sound >> 8)
		set16(SENT_FIRST_BYTE, 1)
	else:
		m.w8(SOUND_LATCH, sound & 0xFF)
		set16(next, 0)
		next += 2
		set32(NEXT_SENT, QUEUE if next == QUEUE_END else next)
		set16(SENT_FIRST_BYTE, 0)
	set16(FRAMES_TO_WAIT, 2)


## $15146
func stop_music() -> void:
	set16(STOP_MUSIC, 1)
	if not m.replaced_sounds.is_empty():
		m.sounds_taken.append(NeoGeoMachine.STOP_MUSIC)


## $15108: forgets what is asked for, and has the sound hardware reset.
func reset() -> void:
	if not m.replaced_sounds.is_empty():
		m.sounds_taken.append(NeoGeoMachine.RESET_SOUND)
	set16(FIELD_1032A6, m.d0)
	set16(SENT_FIRST_BYTE, 0)
	set16(FRAMES_TO_WAIT, 0)
	set32(NEXT_SENT, QUEUE)
	set32(NEXT_FREE, QUEUE)
	for entry in range(QUEUE, QUEUE_END, 2):
		set16(entry, 0)
	_waiting.clear()
	set16(RESET_STEP, 1)
