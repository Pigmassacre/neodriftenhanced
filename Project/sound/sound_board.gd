class_name SoundBoard
extends Node
## The sound side of the machine: the Z80 running the game's own sound
## driver, and the parts of the YM2610 sound chip modelled so far.
##
## Modelled: the two timers (they drive the driver's interrupt), the status
## flags, and the six ADPCM-A sample channels, which are played through
## AudioStreamPlayers. Register writes for the SSG, FM and ADPCM-B parts are
## accepted and counted but make no sound yet.

const Z80_CLOCK := 4000000.0
const FRAME_RATE := 59.185606
const CYCLES_PER_FRAME := int(Z80_CLOCK / FRAME_RATE)
## Chip master clock is 8 MHz, twice the Z80's.
const TIMER_A_CYCLES := 72       # Z80 cycles per timer A count
const TIMER_B_CYCLES := 1152
const ADPCM_A_RATE := 18518.5
## Z80 cycles per byte of ADPCM-A data (two samples).
const ADPCM_A_BYTE_CYCLES := Z80_CLOCK / ADPCM_A_RATE * 2.0
const ADPCM_A_STEPS: Array[int] = [
	16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130,
	143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
	876, 963, 1060, 1166, 1282, 1411, 1552,
]
const ADPCM_A_STEP_CHANGE: Array[int] = [-1, -1, -1, -1, 2, 5, 7, 9]

var cpu: Z80
var driver_rom := PackedByteArray()
var samples_rom := PackedByteArray()
var ram := PackedByteArray()
## Offsets into the driver ROM of the four banked windows at 8000, C000, E000 and F000.
var bank := [0x8000, 0xC000, 0xE000, 0xF000]

var reply := 0
var commands: Array[int] = []
var nmi_enabled := false
var _latch := 0
var _nmi_pending := false

# sound chip
var _address := [0, 0]
var _reg := [PackedByteArray(), PackedByteArray()]
var _timer_a_end := -1
var _timer_b_end := -1
var _status := 0
var _irq_enable := 0
var _adpcm_flags := 0
var _adpcm_mask := 0
var _channel_end := PackedInt64Array([-1, -1, -1, -1, -1, -1])

## Optional register-write log for comparison with MAME: [port "A"/"B", register, value]
var write_log: Array = []
var logging := false
## How many writes went to parts that make no sound yet.
var unvoiced := {"ssg": 0, "fm": 0, "adpcm_b": 0}

## Player changes produced while the driver ran, applied by apply_events().
## The driver runs on a worker thread; audio nodes are only touched from the main thread.
var _events: Array = []
var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var silent := false


func _init() -> void:
	ram.resize(0x800)
	_reg[0].resize(256)
	_reg[1].resize(256)
	cpu = Z80.new(self)


func _ready() -> void:
	if silent:
		return
	for channel in 6:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## Loads the driver and sample ROMs from the user's ROM folder.
func load_roms(dir: String) -> bool:
	driver_rom = FileAccess.get_file_as_bytes(dir.path_join("213-m1.m1"))
	samples_rom = FileAccess.get_file_as_bytes(dir.path_join("213-v1.v1")) \
			+ FileAccess.get_file_as_bytes(dir.path_join("213-v2.v2"))
	if driver_rom.size() != 0x20000 or samples_rom.is_empty():
		push_error("Sound ROMs not found in %s" % dir)
		return false
	cpu.reset()
	return true


## Applies the sample starts, stops and level changes of the last run_frame().
## Call from the main thread once that run has finished.
func apply_events() -> void:
	for event: Array in _events:
		var player := _players[event[1]]
		match event[0]:
			"play":
				player.stream = event[2]
				player.volume_db = event[3]
				player.play()
			"stop":
				player.stop()
			"level":
				player.volume_db = event[2]
	_events.clear()


## A command byte written by the main program.
func command(value: int) -> void:
	commands.append(value)


## Runs the sound CPU for one video frame.
func run_frame() -> void:
	var target := cpu.cycles + CYCLES_PER_FRAME
	while cpu.cycles < target:
		if not _nmi_pending and not commands.is_empty():
			_latch = commands.pop_front()
			_nmi_pending = true
		if _nmi_pending and nmi_enabled:
			_nmi_pending = false
			cpu.nmi()
		_update_timers()
		if (_status & _irq_enable) != 0:
			cpu.irq()
		# run a small slice between interrupt checks
		var slice := mini(cpu.cycles + 256, target)
		while cpu.cycles < slice:
			cpu.step()
		if cpu.bad_opcode >= 0:
			push_error("Sound driver hit an unimplemented opcode %04X near %04X" % [cpu.bad_opcode, cpu.pc])
			cpu.bad_opcode = -1
	_update_channel_flags()


# --- Z80 bus -----------------------------------------------------------------

func mem_read(addr: int) -> int:
	if addr < 0x8000:
		return driver_rom[addr]
	if addr >= 0xF800:
		return ram[addr - 0xF800]
	if addr < 0xC000:
		return driver_rom[(bank[0] + addr - 0x8000) & 0x1FFFF]
	if addr < 0xE000:
		return driver_rom[(bank[1] + addr - 0xC000) & 0x1FFFF]
	if addr < 0xF000:
		return driver_rom[(bank[2] + addr - 0xE000) & 0x1FFFF]
	return driver_rom[(bank[3] + addr - 0xF000) & 0x1FFFF]


func mem_write(addr: int, value: int) -> void:
	if addr >= 0xF800:
		ram[addr - 0xF800] = value


func port_in(port: int) -> int:
	var high := port >> 8
	match port & 0x0F:
		0x00:
			return _latch
		0x04:
			_update_timers()
			return _status
		0x05:
			# only the SSG registers can be read back
			return _reg[0][_address[0]] if _address[0] < 0x10 else 0
		0x06:
			_update_channel_flags()
			return _adpcm_flags & ~_adpcm_mask & 0xFF
		0x08:
			bank[3] = high * 0x800
		0x09:
			bank[2] = high * 0x1000
		0x0A:
			bank[1] = high * 0x2000
		0x0B:
			bank[0] = high * 0x4000
	return 0


func port_out(port: int, value: int) -> void:
	match port & 0x0F:
		0x00:
			_latch = 0
		0x04:
			_address[0] = value
		0x05:
			_chip_write(0, _address[0], value)
		0x06:
			_address[1] = value
		0x07:
			_chip_write(1, _address[1], value)
		0x08:
			nmi_enabled = (port & 0x10) == 0
		0x0C:
			reply = value


# --- sound chip --------------------------------------------------------------

func _chip_write(port: int, register: int, value: int) -> void:
	if logging:
		write_log.append(["A" if port == 0 else "B", register, value])
	_reg[port][register] = value
	if port == 0:
		if register < 0x10:
			unvoiced["ssg"] += 1
		elif register < 0x1C:
			unvoiced["adpcm_b"] += 1
		elif register == 0x1C:
			# flag control: set bits mask a flag and clear it
			_adpcm_mask = value
			_adpcm_flags &= ~value
		elif register == 0x27:
			_timer_control(value)
		elif register >= 0x28:
			unvoiced["fm"] += 1
	elif register < 0x30:
		_adpcm_a_write(register, value)
	else:
		unvoiced["fm"] += 1


func _timer_control(value: int) -> void:
	_update_timers()
	if value & 0x10:
		_status &= ~1
	if value & 0x20:
		_status &= ~2
	_irq_enable = (value >> 2) & 3
	if (value & 1) == 0:
		_timer_a_end = -1
	elif _timer_a_end < 0:
		_timer_a_end = cpu.cycles + _timer_a_period()
	if (value & 2) == 0:
		_timer_b_end = -1
	elif _timer_b_end < 0:
		_timer_b_end = cpu.cycles + _timer_b_period()


func _timer_a_period() -> int:
	return (1024 - ((_reg[0][0x24] << 2) | (_reg[0][0x25] & 3))) * TIMER_A_CYCLES


func _timer_b_period() -> int:
	return (256 - _reg[0][0x26]) * TIMER_B_CYCLES


func _update_timers() -> void:
	if _timer_a_end >= 0 and cpu.cycles >= _timer_a_end:
		_status |= 1
		_timer_a_end += _timer_a_period()
	if _timer_b_end >= 0 and cpu.cycles >= _timer_b_end:
		_status |= 2
		_timer_b_end += _timer_b_period()


func _update_channel_flags() -> void:
	for channel in 6:
		if _channel_end[channel] >= 0 and cpu.cycles >= _channel_end[channel]:
			_channel_end[channel] = -1
			_adpcm_flags |= 1 << channel


func _adpcm_a_write(register: int, value: int) -> void:
	if register == 0x00:
		for channel in 6:
			if (value & (1 << channel)) == 0:
				continue
			if value & 0x80:
				_channel_end[channel] = -1
				if not silent:
					_events.append(["stop", channel])
			else:
				_key_on(channel)
	elif register == 0x01 or (register >= 0x08 and register < 0x0E):
		if not silent:
			for channel in 6:
				_events.append(["level", channel, _level_db(channel)])


func _key_on(channel: int) -> void:
	var start: int = (_reg[1][0x10 + channel] | (_reg[1][0x18 + channel] << 8)) << 8
	var end: int = ((_reg[1][0x20 + channel] | (_reg[1][0x28 + channel] << 8)) << 8) | 0xFF
	var length: int = end - start + 1
	if length <= 0:
		return
	_adpcm_flags &= ~(1 << channel)
	_channel_end[channel] = cpu.cycles + int(length * ADPCM_A_BYTE_CYCLES)
	if silent:
		return
	var key: int = start | (end << 24)
	if not _streams.has(key):
		_streams[key] = _decode_adpcm_a(start, length)
	_events.append(["play", channel, _streams[key], _level_db(channel)])


## Channel volume: master and channel attenuation add up in 0.75 dB steps.
func _level_db(channel: int) -> float:
	var control: int = _reg[1][0x08 + channel]
	var attenuation: int = ((control & 0x1F) ^ 0x1F) + ((_reg[1][0x01] & 0x3F) ^ 0x3F)
	var audible := attenuation < 63 and (control & 0xC0) != 0
	return -0.75 * attenuation if audible else -80.0


func _decode_adpcm_a(start: int, length: int) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(length * 4)
	var accumulator := 0
	var step := 0
	var out := 0
	var limit := mini(start + length, samples_rom.size())
	for position in range(start, limit):
		var data := samples_rom[position]
		for half in 2:
			var nibble := (data >> 4) if half == 0 else (data & 0x0F)
			var delta := (2 * (nibble & 7) + 1) * ADPCM_A_STEPS[step] / 8
			accumulator = (accumulator + (-delta if (nibble & 8) else delta)) & 0xFFF
			step = clampi(step + ADPCM_A_STEP_CHANGE[nibble & 7], 0, 48)
			# 12-bit signed sample, scaled to 16 bits
			pcm.encode_s16(out, ((accumulator ^ 0x800) - 0x800) << 4)
			out += 2
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(ADPCM_A_RATE)
	stream.stereo = false
	stream.data = pcm
	return stream
