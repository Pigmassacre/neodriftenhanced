class_name YMSsg
extends RefCounted
## The SSG part of the YM2610: three square-wave channels, a noise generator
## and one shared envelope.
##
## Follows MAME's chip model (ymfm): the generator steps at 250 kHz, 4.5 steps
## per output sample, and each output sample is the average of the steps it
## covers. Steps are only taken one by one when something audible is about to
## change; otherwise the counters are moved on in one go.

const AMPLITUDES: Array[int] = [
	0, 32, 78, 141, 178, 222, 262, 306, 369, 441, 509, 585, 701, 836, 965, 1112,
	1334, 1595, 1853, 2146, 2576, 3081, 3576, 4135, 5000, 6006, 7023, 8155, 9963, 11976, 14132, 16382,
]

## Output of the last render(): the three channels mixed, one value per sample.
var out := PackedInt32Array()

var _reg := PackedByteArray()
var _tone_count := PackedInt32Array([0, 0, 0])
## The tones start high: that is what lines the waveform up with MAME's.
var _tone_state := PackedInt32Array([1, 1, 1])
var _noise_count := 0
var _noise_state := 1
var _envelope_count := 0
var _envelope_state := 0
## Mixed level after the last generator step, and at the current state.
var _last := 0


func _init() -> void:
	_reg.resize(16)


## Renders `count` samples starting at chip sample `first`; see YMFmChannel.render.
func render(writes: PackedInt64Array, first: int, count: int) -> void:
	out.resize(count)
	var position := 0
	for entry in writes:
		if (entry & 0x1FF00) >= 0x1000:
			continue
		var at := clampi((entry >> 17) - first, position, count)
		if at > position:
			_run(position, at, first)
			position = at
		var register := (entry >> 8) & 0xFF
		_reg[register] = entry & 0xFF
		if register == 0x0D:
			_envelope_state = 0
	if count > position:
		_run(position, count, first)


func _tone_period(channel: int) -> int:
	return _reg[channel * 2] | ((_reg[channel * 2 + 1] & 0x0F) << 8)


## The mixed level of the three channels at the current state.
func _level() -> int:
	var shape := _reg[0x0D]
	var envelope := 0
	if ((shape & 1) != 0 or (shape & 8) == 0) and _envelope_state >= 32:
		_envelope_state = 32
		envelope = 31 if ((((shape >> 2) ^ (shape >> 1)) & (shape >> 3)) & 1) else 0
	else:
		var attack := (shape >> 2) & 1
		if shape & 2:
			attack ^= (_envelope_state >> 5) & 1
		envelope = (_envelope_state & 31) ^ (0 if attack else 31)
	var mixer := _reg[7]
	var total := 0
	for channel in 3:
		var control := _reg[8 + channel]
		var level := envelope
		if (control & 0x10) == 0:
			level = (control & 0x0F) * 2
			if level != 0:
				level |= 1
		if ((((mixer >> channel) & 1) | _tone_state[channel])
				& (((mixer >> (3 + channel)) & 1) | (_noise_state & 1))) != 0:
			total += AMPLITUDES[level]
	return total


func _step_noise() -> void:
	_noise_state ^= ((_noise_state & 1) ^ ((_noise_state >> 3) & 1)) << 17
	_noise_state >>= 1


func _run(from: int, to: int, first: int) -> void:
	# which counters can change what is heard during this span
	var mixer := _reg[7]
	var tone_heard := [false, false, false]
	var noise_heard := false
	var envelope_heard := false
	for channel in 3:
		var control := _reg[8 + channel]
		if (control & 0x1F) == 0:
			continue
		tone_heard[channel] = ((mixer >> channel) & 1) == 0
		noise_heard = noise_heard or ((mixer >> (3 + channel)) & 1) == 0
		envelope_heard = envelope_heard or (control & 0x10) != 0
	var periods := [_tone_period(0), _tone_period(1), _tone_period(2)]
	var noise_period: int = maxi((_reg[6] & 0x1F) * 2, 2)
	var envelope_period: int = _reg[0x0B] | (_reg[0x0C] << 8)

	var current := _level()
	var last := _last
	# generator steps before the next audible change, and steps not yet applied to the counters
	var quiet := _steps_until_change(tone_heard, noise_heard, envelope_heard, periods,
			noise_period, envelope_period)
	var lag := 0
	var total_steps := 0
	for index in range(from, to):
		var odd := ((first + index) & 1) != 0
		var steps := 4 if odd else 5
		total_steps += steps
		if quiet > steps:
			quiet -= steps
			lag += steps
			out[index] = ((last + current * 8) if odd else (current * 9)) * 2 / 9
			last = current
			continue
		if lag != 0:
			_advance_heard(lag, tone_heard, noise_heard, envelope_heard)
			lag = 0
		var sum := last if odd else 0
		for step in steps:
			var changed := false
			for channel in 3:
				if tone_heard[channel]:
					_tone_count[channel] += 1
					if _tone_count[channel] >= periods[channel]:
						_tone_state[channel] ^= 1
						_tone_count[channel] = 0
						changed = true
			if noise_heard:
				_noise_count += 1
				if _noise_count >= noise_period:
					_step_noise()
					_noise_count = 0
					changed = true
			if envelope_heard:
				_envelope_count += 1
				if _envelope_count >= envelope_period:
					_envelope_state += 1
					_envelope_count = 0
					changed = true
			if changed:
				current = _level()
			sum += current * (1 if (step == 4) else 2)
		out[index] = sum * 2 / 9
		last = current
		quiet = _steps_until_change(tone_heard, noise_heard, envelope_heard, periods,
				noise_period, envelope_period)
	if lag != 0:
		_advance_heard(lag, tone_heard, noise_heard, envelope_heard)
	_last = last

	# counters that could not be heard: move them on in one go
	for channel in 3:
		if not tone_heard[channel]:
			var period: int = maxi(periods[channel], 1)
			var steps := total_steps
			if _tone_count[channel] >= period and steps > 0:
				_tone_state[channel] ^= 1
				_tone_count[channel] = 0
				steps -= 1
			var count := _tone_count[channel] + steps
			_tone_state[channel] ^= (count / period) & 1
			_tone_count[channel] = count % period
	if not noise_heard:
		var steps := total_steps
		while steps > 0:
			var wait := maxi(noise_period - _noise_count, 1)
			if wait > steps:
				_noise_count += steps
				break
			steps -= wait
			_step_noise()
			_noise_count = 0
	if not envelope_heard:
		var period := maxi(envelope_period, 1)
		var steps := total_steps
		if _envelope_count >= period and steps > 0:
			_envelope_state += 1
			_envelope_count = 0
			steps -= 1
		var count := _envelope_count + steps
		_envelope_state += count / period
		_envelope_count = count % period
		var shape := _reg[0x0D]
		if ((shape & 1) != 0 or (shape & 8) == 0) and _envelope_state >= 32:
			_envelope_state = 32
		_envelope_state &= 0x3F


func _steps_until_change(tone_heard: Array, noise_heard: bool, envelope_heard: bool,
		periods: Array, noise_period: int, envelope_period: int) -> int:
	var steps := 1 << 30
	for channel in 3:
		if tone_heard[channel]:
			steps = mini(steps, maxi(periods[channel] - _tone_count[channel], 1))
	if noise_heard:
		steps = mini(steps, maxi(noise_period - _noise_count, 1))
	if envelope_heard:
		steps = mini(steps, maxi(envelope_period - _envelope_count, 1))
	return steps


func _advance_heard(steps: int, tone_heard: Array, noise_heard: bool, envelope_heard: bool) -> void:
	for channel in 3:
		if tone_heard[channel]:
			_tone_count[channel] += steps
	if noise_heard:
		_noise_count += steps
	if envelope_heard:
		_envelope_count += steps
