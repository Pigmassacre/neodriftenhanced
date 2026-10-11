class_name YM2610
extends RefCounted
## The YM2610 sound chip.
##
## Two sides: the bus side answers the sound CPU as it runs (timers, status
## and end-of-sample flags), and the audio side turns the register writes,
## stamped with the time they happened, into sound afterwards. The audio parts
## are independent of each other, so render() runs them on worker threads.
##
## One chip sample is 72 sound CPU cycles (55.6 kHz). The second sampled-sound
## part (ADPCM-B) is not modelled: the game's driver only ever resets it.

const CYCLES_PER_SAMPLE := 72
const SAMPLE_RATE := 4000000.0 / CYCLES_PER_SAMPLE
const TIMER_A_CYCLES := 72
const TIMER_B_CYCLES := 1152
## How loud MAME's Neo Geo mixes the FM and sampled parts and the SSG part.
const MAIN_GAIN := 0.98 / 32768.0
const SSG_GAIN := 0.28 / 32768.0

var fm: Array[YMFmChannel] = []
var ssg := YMSsg.new()
var adpcm := YMAdpcmA.new()

## Output of the last render(): stereo sound without the SSG part, and the SSG part.
var out_left := PackedInt32Array()
var out_right := PackedInt32Array()
var out_ssg := PackedInt32Array()
## Leave parts out of render() (for checking them one at a time).
var use_fm := true
var use_ssg := true
var use_adpcm := true
## Render the parts on worker threads.
var threaded := true

## How many writes went to parts that make no sound.
var unvoiced_adpcm_b := 0

var _address_reg := PackedByteArray()
var _timer_a_end := -1
var _timer_b_end := -1
var _status := 0
var _irq_enable := 0
var _flags := 0
var _flag_mask := 0
var _channel_end := PackedInt64Array([-1, -1, -1, -1, -1, -1])
var _reg := [PackedByteArray(), PackedByteArray()]
var _writes := PackedInt64Array()
var _rendered := 0
var _parts: Array = []


func _init() -> void:
	_reg[0].resize(256)
	_reg[1].resize(256)
	for channel: int in [1, 2, 4, 5]:
		fm.append(YMFmChannel.new(channel))


func set_sample_rom(rom: PackedByteArray) -> void:
	adpcm.rom = rom


# --- bus side ----------------------------------------------------------------

## A register write by the sound CPU at time `cycles`.
func write(port: int, register: int, value: int, cycles: int) -> void:
	_reg[port][register] = value
	_writes.append(((cycles / CYCLES_PER_SAMPLE) << 17) | (port << 16) | (register << 8) | value)
	if port == 0:
		if register >= 0x10 and register < 0x1C:
			unvoiced_adpcm_b += 1
		elif register == 0x1C:
			# flag control: set bits mask a flag and clear it
			_flag_mask = value
			_flags &= ~value
		elif register == 0x27:
			_timer_control(value, cycles)
	elif register == 0x00:
		for channel in 6:
			if (value >> channel) & 1:
				if value & 0x80:
					_channel_end[channel] = -1
				else:
					var length := YMAdpcmA.length_for(
							_reg[1][0x10 + channel] | (_reg[1][0x18 + channel] << 8),
							_reg[1][0x20 + channel] | (_reg[1][0x28 + channel] << 8))
					var sample := cycles / CYCLES_PER_SAMPLE
					_channel_end[channel] = (sample + YMAdpcmA.samples_until_end(sample, length)) \
							* CYCLES_PER_SAMPLE


## Only the SSG registers can be read back.
func read(port: int, register: int) -> int:
	return _reg[0][register] if port == 0 and register < 0x10 else 0


## Timer flags.
func status(cycles: int) -> int:
	_update_timers(cycles)
	return _status


## End-of-sample flags of the six sampled channels.
func flags(cycles: int) -> int:
	for channel in 6:
		if _channel_end[channel] >= 0 and cycles >= _channel_end[channel]:
			_channel_end[channel] = -1
			_flags |= 1 << channel
	return _flags & ~_flag_mask & 0xFF


## True while the chip asks for an interrupt.
func irq(cycles: int) -> bool:
	_update_timers(cycles)
	return (_status & _irq_enable) != 0


## The time of the next timer overflow, or a time far away if none is running.
func next_timer_event() -> int:
	var next := 1 << 62
	if _timer_a_end >= 0:
		next = _timer_a_end
	if _timer_b_end >= 0 and _timer_b_end < next:
		next = _timer_b_end
	return next


func _timer_control(value: int, cycles: int) -> void:
	_update_timers(cycles)
	if value & 0x10:
		_status &= ~1
	if value & 0x20:
		_status &= ~2
	_irq_enable = (value >> 2) & 3
	if (value & 1) == 0:
		_timer_a_end = -1
	elif _timer_a_end < 0:
		_timer_a_end = cycles + _timer_a_period()
	if (value & 2) == 0:
		_timer_b_end = -1
	elif _timer_b_end < 0:
		_timer_b_end = cycles + _timer_b_period()


func _timer_a_period() -> int:
	return (1024 - ((_reg[0][0x24] << 2) | (_reg[0][0x25] & 3))) * TIMER_A_CYCLES


func _timer_b_period() -> int:
	return (256 - _reg[0][0x26]) * TIMER_B_CYCLES


func _update_timers(cycles: int) -> void:
	if _timer_a_end >= 0 and cycles >= _timer_a_end:
		_status |= 1
		_timer_a_end += _timer_a_period()
	if _timer_b_end >= 0 and cycles >= _timer_b_end:
		_status |= 2
		_timer_b_end += _timer_b_period()


# --- audio side --------------------------------------------------------------

## Renders the sound up to time `cycles` into out_left, out_right and out_ssg,
## and returns the number of samples.
func render(cycles: int) -> int:
	var count := cycles / CYCLES_PER_SAMPLE - _rendered
	if count <= 0:
		return 0
	_parts.clear()
	if use_fm:
		_parts.append_array(fm)
	if use_ssg:
		_parts.append(ssg)
	if use_adpcm:
		_parts.append(adpcm)
	if threaded and _parts.size() > 1:
		var task := WorkerThreadPool.add_group_task(_render_part.bind(count), _parts.size())
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for index in _parts.size():
			_render_part(index, count)
	_writes.clear()
	_rendered += count

	out_left.resize(count)
	out_right.resize(count)
	out_left.fill(0)
	out_right.fill(0)
	if use_adpcm:
		out_left = adpcm.out_left.duplicate()
		out_right = adpcm.out_right.duplicate()
	if use_fm:
		for channel in fm:
			var left := channel.out_left
			var right := channel.out_right
			for index in count:
				out_left[index] += left[index]
				out_right[index] += right[index]
	if use_ssg:
		out_ssg = ssg.out
	else:
		out_ssg.resize(count)
		out_ssg.fill(0)
	return count


## Forgets the writes since the last render() without making sound of them.
func discard_writes() -> void:
	_writes.clear()


func _render_part(index: int, count: int) -> void:
	_parts[index].render(_writes, _rendered, count)


## The last render() as stereo frames at SAMPLE_RATE.
func frames() -> PackedVector2Array:
	var count := out_left.size()
	var result := PackedVector2Array()
	result.resize(count)
	for index in count:
		var centre := out_ssg[index] * SSG_GAIN
		result[index] = Vector2(clampi(out_left[index], -32768, 32767) * MAIN_GAIN + centre,
				clampi(out_right[index], -32768, 32767) * MAIN_GAIN + centre)
	return result
