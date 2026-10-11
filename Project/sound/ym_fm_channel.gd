class_name YMFmChannel
extends RefCounted
## One four-operator FM channel of the YM2610 sound chip.
##
## Follows the behaviour of MAME's chip model (ymfm) sample for sample: log-sine
## and exponent tables, envelope rates, detune, feedback and the eight operator
## arrangements. Each channel keeps its own copy of the chip-wide counters so
## that channels can be rendered on separate threads.
##
## Not modelled, because the game's driver never enables them: the special
## modes of channel 3 and the SSG-style envelope shapes. The vibrato/tremolo
## oscillator is modelled but has not been checked against MAME.

enum { ATTACK, DECAY, SUSTAIN, RELEASE }

## Envelope levels above this are silent.
const QUIET := 0x380
## Register offsets of the four operators, in the order they are computed.
const OPERATOR_OFFSET: Array[int] = [0, 8, 4, 12]
const DETUNE: Array[int] = [
	0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2, 0, 0, 1, 2,
	0, 1, 2, 2, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
	0, 1, 2, 4, 0, 1, 3, 4, 0, 1, 3, 4, 0, 1, 3, 5,
	0, 2, 4, 5, 0, 2, 4, 6, 0, 2, 4, 6, 0, 2, 5, 7,
	0, 2, 5, 8, 0, 3, 6, 8, 0, 3, 6, 9, 0, 3, 7, 10,
	0, 4, 8, 11, 0, 4, 8, 12, 0, 4, 9, 13, 0, 5, 10, 14,
	0, 5, 11, 16, 0, 6, 12, 17, 0, 6, 13, 19, 0, 7, 14, 20,
	0, 8, 16, 22, 0, 8, 16, 22, 0, 8, 16, 22, 0, 8, 16, 22,
]
## Envelope steps for each rate: eight 4-bit increments, picked by the envelope clock.
const INCREMENTS: Array[int] = [
	0x00000000, 0x00000000, 0x10101010, 0x10101010, 0x10101010, 0x10101010, 0x11101110, 0x11101110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110, 0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110, 0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110, 0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110, 0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x10101010, 0x10111010, 0x11101110, 0x11111110, 0x10101010, 0x10111010, 0x11101110, 0x11111110,
	0x11111111, 0x21112111, 0x21212121, 0x22212221, 0x22222222, 0x42224222, 0x42424242, 0x44424442,
	0x44444444, 0x84448444, 0x84848484, 0x88848884, 0x88888888, 0x88888888, 0x88888888, 0x88888888,
]
## For each arrangement: which earlier result feeds operators 2, 3 and 4
## (0 none, 1-3 that operator, 5 = 1+2, 6 = 1+3, 7 = 2+3) and which of
## operators 1-3 are heard directly besides operator 4.
const ARRANGEMENTS: Array = [
	[1, 2, 3, 0], [0, 5, 3, 0], [0, 2, 6, 0], [1, 0, 7, 0],
	[1, 0, 3, 2], [1, 1, 1, 6], [1, 0, 0, 6], [0, 0, 0, 7],
]
const LFO_PERIOD: Array[int] = [109, 78, 72, 68, 63, 45, 9, 6]
const LFO_PM_SHIFTS: Array[int] = [
	0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
	0x77, 0x77, 0x77, 0x77, 0x72, 0x72, 0x72, 0x72,
	0x77, 0x77, 0x77, 0x72, 0x72, 0x72, 0x17, 0x17,
	0x77, 0x77, 0x72, 0x72, 0x17, 0x17, 0x12, 0x12,
	0x77, 0x77, 0x72, 0x17, 0x17, 0x17, 0x12, 0x07,
	0x77, 0x77, 0x17, 0x12, 0x07, 0x07, 0x02, 0x01,
	0x77, 0x77, 0x17, 0x12, 0x07, 0x07, 0x02, 0x01,
	0x77, 0x77, 0x17, 0x12, 0x07, 0x07, 0x02, 0x01,
]

## Attenuation of a sine wave at each of 1024 phase steps, in 1/256 octaves.
static var _wave := PackedInt32Array()
## Linear output for an attenuation in 1/256 octaves.
static var _volume := PackedInt32Array()

## Output of the last render(), one value per sample.
var out_left := PackedInt32Array()
var out_right := PackedInt32Array()

var _port := 0
var _slot := 0
var _key_code := 0
var _reg := PackedByteArray()
var _lfo_control := 0
var _latch := [0, 0]
var _block_freq := 0

# per operator, in computation order
var _phase := PackedInt32Array([0, 0, 0, 0])
var _phase_step := PackedInt32Array([0, 0, 0, 0])
var _attenuation := PackedInt32Array([0x3FF, 0x3FF, 0x3FF, 0x3FF])
var _state := PackedInt32Array([RELEASE, RELEASE, RELEASE, RELEASE])
var _key_live := PackedInt32Array([0, 0, 0, 0])
var _key_state := PackedInt32Array([0, 0, 0, 0])
var _total_level := PackedInt32Array([0, 0, 0, 0])
var _sustain := PackedInt32Array([0, 0, 0, 0])
var _rate := PackedInt32Array()
var _tremolo := PackedInt32Array([0, 0, 0, 0])
## Envelope plus total level in 1/256 octaves, or -1 when the operator is silent.
var _level := PackedInt32Array([-1, -1, -1, -1])

var _feedback_0 := 0
var _feedback_1 := 0
var _modified := true
var _silent := true
var _sub := 0
var _env_clock := 0
var _lfo_counter := 0
var _lfo_am := 0
var _lfo_pm := 0
var _mix := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])


static func _static_init() -> void:
	_wave.resize(1024)
	for index in 1024:
		var quarter := (~index if (index & 0x100) else index) & 0xFF
		_wave[index] = roundi(-log(sin((quarter + 0.5) * PI / 512.0)) / log(2.0) * 256.0)
	_volume.resize(0x1900)
	for value in _volume.size():
		var mantissa := roundi((pow(2.0, (255 - (value & 0xFF)) / 256.0) - 1.0) * 1024.0)
		_volume[value] = ((mantissa | 0x400) << 2) >> (value >> 8)


## `channel` is the chip's channel number, 0-5; the YM2610 only has 1, 2, 4 and 5.
func _init(channel: int) -> void:
	_port = channel / 3
	_slot = channel % 3
	_key_code = _slot + _port * 4
	_reg.resize(256)
	_reg[0xB4 + _slot] = 0xC0
	_rate.resize(16)


## Renders `count` samples starting at chip sample `first`. `writes` are the
## register writes of that span in order, each encoded as
## (sample << 17) | (port << 16) | (register << 8) | value.
func render(writes: PackedInt64Array, first: int, count: int) -> void:
	out_left.resize(count)
	out_right.resize(count)
	out_left.fill(0)
	out_right.fill(0)
	var position := 0
	for entry in writes:
		var register := (entry >> 8) & 0xFF
		if register < 0x22:
			continue
		var port := (entry >> 16) & 1
		if not _concerns(port, register, entry & 0xFF):
			continue
		var at := clampi((entry >> 17) - first, position, count)
		if at > position:
			_run(position, at)
			position = at
		_write(port, register, entry & 0xFF)
	if count > position:
		_run(position, count)


func _concerns(port: int, register: int, value: int) -> bool:
	if port == 0:
		if register == 0x22:
			return true
		if register == 0x28:
			return (value & 7) == _key_code
	if port != _port or register < 0x30:
		return false
	if register >= 0xA4 and register < 0xA8:
		return true
	return (register & 3) == _slot


func _write(port: int, register: int, value: int) -> void:
	_modified = true
	if port == 0 and register == 0x22:
		_lfo_control = value
	elif port == 0 and register == 0x28:
		for index in 4:
			_key_live[index] = (value >> (4 + index)) & 1
	elif register >= 0xA4 and register < 0xA8:
		# the high part of the pitch waits for the low part to be written
		_latch[0] = value
	elif register >= 0xA0 and register < 0xA4:
		_block_freq = ((_latch[0] & 0x3F) << 8) | value
	else:
		_reg[register] = value


## Recomputes what depends on the registers, and starts or releases notes.
func _prepare() -> void:
	_modified = false
	var key := ((_block_freq >> 10) & 15) << 1
	key |= (0xFE80 >> ((_block_freq >> 7) & 15)) & 1
	for index in 4:
		var offset := OPERATOR_OFFSET[index] + _slot
		_total_level[index] = (_reg[0x40 + offset] & 0x7F) << 3
		var sustain := _reg[0x80 + offset] >> 4
		sustain |= (sustain + 1) & 0x10
		_sustain[index] = sustain << 5
		var scaling := key >> ((_reg[0x50 + offset] >> 6) ^ 3)
		_rate[index * 4 + ATTACK] = _effective_rate((_reg[0x50 + offset] & 0x1F) * 2, scaling)
		_rate[index * 4 + DECAY] = _effective_rate((_reg[0x60 + offset] & 0x1F) * 2, scaling)
		_rate[index * 4 + SUSTAIN] = _effective_rate((_reg[0x70 + offset] & 0x1F) * 2, scaling)
		_rate[index * 4 + RELEASE] = _effective_rate((_reg[0x80 + offset] & 0x0F) * 4 + 2, scaling)
		_tremolo[index] = _reg[0x60 + offset] >> 7
		if _key_live[index] != _key_state[index]:
			_key_state[index] = _key_live[index]
			if _key_live[index] == 0:
				if _state[index] < RELEASE:
					_state[index] = RELEASE
			elif _state[index] != ATTACK:
				_state[index] = ATTACK
				_phase[index] = 0
				if _rate[index * 4 + ATTACK] >= 62:
					_attenuation[index] = 0
	_update_steps(key)
	_update_levels()


func _effective_rate(raw: int, scaling: int) -> int:
	return 0 if raw == 0 else mini(raw + scaling, 63)


func _update_steps(key: int) -> void:
	var number := (_block_freq & 0x7FF) << 1
	var depth := _reg[0xB4 + _slot] & 7
	if depth != 0 and _lfo_pm != 0:
		var magnitude := absi(_lfo_pm)
		var shifts := LFO_PM_SHIFTS[depth * 8 + (magnitude & 7)]
		var top := (_block_freq >> 4) & 0x7F
		var adjust := (top >> (shifts & 15)) + (top >> (shifts >> 4))
		if depth > 5:
			adjust <<= depth - 5
		adjust >>= 2
		number = (number + (-adjust if _lfo_pm < 0 else adjust)) & 0xFFF
	var base := (number << ((_block_freq >> 11) & 7)) >> 2
	for index in 4:
		var control := _reg[0x30 + OPERATOR_OFFSET[index] + _slot]
		var detune := DETUNE[key * 4 + ((control >> 4) & 3)]
		var step := (base + (-detune if (control & 0x40) else detune)) & 0x1FFFF
		var multiple := (control & 15) * 2
		_phase_step[index] = (step * (multiple if multiple else 1)) >> 1


func _update_levels() -> void:
	var tremolo := (_lfo_am << 1) >> ((1 << (((_reg[0xB4 + _slot] >> 4) & 3) ^ 3)) - 1)
	_silent = true
	for index in 4:
		var attenuation := _attenuation[index]
		if attenuation > QUIET:
			_level[index] = -1
		else:
			_level[index] = mini(attenuation + _total_level[index]
					+ (tremolo if _tremolo[index] else 0), 0x3FF) << 2
		if attenuation <= QUIET or _state[index] != RELEASE:
			_silent = false


func _clock_envelopes() -> void:
	for index in 4:
		var state := _state[index]
		var attenuation := _attenuation[index]
		if state == ATTACK and attenuation == 0:
			state = DECAY
		if state == DECAY and attenuation >= _sustain[index]:
			state = SUSTAIN
		_state[index] = state
		var rate := _rate[index * 4 + state]
		var shift := rate >> 2
		var clock := _env_clock << shift
		if clock & 0x7FF:
			continue
		var increment := (INCREMENTS[rate] >> (4 * ((clock >> (11 if shift <= 11 else shift)) & 7))) & 15
		if state == ATTACK:
			if rate < 62:
				attenuation += (~attenuation * increment) >> 4
		else:
			attenuation = mini(attenuation + increment, 0x3FF)
		_attenuation[index] = attenuation
	_update_levels()


## Steps the vibrato/tremolo oscillator; true if its output changed.
func _clock_lfo() -> bool:
	var am := _lfo_am
	var pm := _lfo_pm
	if (_lfo_control & 8) == 0:
		_lfo_counter = 0
		_lfo_am = 0
		_lfo_pm = 0
	else:
		var count := _lfo_counter & 0xFF
		_lfo_counter += 1
		if count >= LFO_PERIOD[_lfo_control & 7]:
			_lfo_counter += 0x101 - count
		_lfo_am = (_lfo_counter >> 8) & 0x3F
		if ((_lfo_counter >> 14) & 1) == 0:
			_lfo_am ^= 0x3F
		_lfo_pm = (_lfo_counter >> 10) & 7
		if (_lfo_counter >> 13) & 1:
			_lfo_pm ^= 7
		if (_lfo_counter >> 14) & 1:
			_lfo_pm = -_lfo_pm
	return am != _lfo_am or pm != _lfo_pm


func _run(from: int, to: int) -> void:
	if _modified:
		_prepare()
	var index := from
	while index < to:
		if _silent and (_lfo_control & 8) == 0:
			index = _run_silent(index, to)
		else:
			index = _run_sounding(index, to)


## Nothing is heard: only the envelopes move, towards full attenuation.
func _run_silent(from: int, to: int) -> int:
	_feedback_0 = 0
	_feedback_1 = 0
	_lfo_counter = 0
	var settled := true
	for index in 4:
		if _attenuation[index] < 0x3FF:
			settled = false
	var clocks := (_sub + to - from) / 3
	if settled:
		_env_clock += clocks
	else:
		for step in clocks:
			_env_clock += 1
			_clock_envelopes()
	_sub = (_sub + to - from) % 3
	return to


func _run_sounding(from: int, to: int) -> int:
	var wave := _wave
	var volume := _volume
	var mix := _mix
	var phase_0 := _phase[0]
	var phase_1 := _phase[1]
	var phase_2 := _phase[2]
	var phase_3 := _phase[3]
	var step_0 := _phase_step[0]
	var step_1 := _phase_step[1]
	var step_2 := _phase_step[2]
	var step_3 := _phase_step[3]
	var level_0 := _level[0]
	var level_1 := _level[1]
	var level_2 := _level[2]
	var level_3 := _level[3]
	var feedback_0 := _feedback_0
	var feedback_1 := _feedback_1
	var feedback := (_reg[0xB0 + _slot] >> 3) & 7
	var feedback_shift := 10 - feedback
	var arrangement: Array = ARRANGEMENTS[_reg[0xB0 + _slot] & 7]
	var from_2: int = arrangement[0]
	var from_3: int = arrangement[1]
	var from_4: int = arrangement[2]
	var direct: int = arrangement[3]
	var left := (_reg[0xB4 + _slot] & 0x80) != 0
	var right := (_reg[0xB4 + _slot] & 0x40) != 0
	var lfo := (_lfo_control & 8) != 0
	var sub := _sub
	var index := from
	while index < to:
		sub += 1
		var refresh := false
		if sub == 3:
			sub = 0
			_env_clock += 1
			_clock_envelopes()
			refresh = true
		if lfo and _clock_lfo():
			_update_steps((((_block_freq >> 10) & 15) << 1) | ((0xFE80 >> ((_block_freq >> 7) & 15)) & 1))
			_update_levels()
			step_0 = _phase_step[0]
			step_1 = _phase_step[1]
			step_2 = _phase_step[2]
			step_3 = _phase_step[3]
			refresh = true
		if refresh:
			level_0 = _level[0]
			level_1 = _level[1]
			level_2 = _level[2]
			level_3 = _level[3]
			if _silent and not lfo:
				index += 1
				break
		phase_0 = (phase_0 + step_0) & 0xFFFFF
		phase_1 = (phase_1 + step_1) & 0xFFFFF
		phase_2 = (phase_2 + step_2) & 0xFFFFF
		phase_3 = (phase_3 + step_3) & 0xFFFFF
		index += 1

		var angle := phase_0 >> 10
		if feedback != 0:
			angle = (angle + ((feedback_0 + feedback_1) >> feedback_shift)) & 0x3FF
		var out_1 := 0
		if level_0 >= 0:
			out_1 = volume[wave[angle] + level_0]
			if angle & 0x200:
				out_1 = -out_1
		feedback_0 = feedback_1
		feedback_1 = out_1
		mix[1] = out_1

		angle = ((phase_1 >> 10) + (mix[from_2] >> 1)) & 0x3FF
		var out_2 := 0
		if level_1 >= 0:
			out_2 = volume[wave[angle] + level_1]
			if angle & 0x200:
				out_2 = -out_2
		mix[2] = out_2
		mix[5] = out_1 + out_2

		angle = ((phase_2 >> 10) + (mix[from_3] >> 1)) & 0x3FF
		var out_3 := 0
		if level_2 >= 0:
			out_3 = volume[wave[angle] + level_2]
			if angle & 0x200:
				out_3 = -out_3
		mix[3] = out_3
		mix[6] = out_1 + out_3
		mix[7] = out_2 + out_3

		angle = ((phase_3 >> 10) + (mix[from_4] >> 1)) & 0x3FF
		var result := 0
		if level_3 >= 0:
			result = volume[wave[angle] + level_3]
			if angle & 0x200:
				result = -result
		result >>= 1
		if direct != 0:
			if direct & 1:
				result += out_1 >> 1
			if direct & 2:
				result += out_2 >> 1
			if direct & 4:
				result += out_3 >> 1
		if left:
			out_left[index - 1] = result
		if right:
			out_right[index - 1] = result
	_sub = sub
	_phase[0] = phase_0
	_phase[1] = phase_1
	_phase[2] = phase_2
	_phase[3] = phase_3
	_feedback_0 = feedback_0
	_feedback_1 = feedback_1
	return index
