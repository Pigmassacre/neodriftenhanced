class_name SoundBoard
extends Node
## The sound side of the machine: the Z80 running the game's own sound
## driver, and the YM2610 sound chip it plays.
##
## run_frame() runs the driver for one video frame and renders that frame's
## sound; it may be called from a worker thread. play_rendered() then hands
## the sound to the audio output, from the main thread.

const Z80_CLOCK := 4000000.0
const FRAME_RATE := 59.185606
const CYCLES_PER_FRAME := int(Z80_CLOCK / FRAME_RATE)
## The driver's idle loop (see _skip_idle_loop): where it starts, the code
## expected there, what one turn costs, and the two queue positions it compares.
const IDLE_LOOP := 0x0133
const IDLE_LOOP_CODE: Array[int] = [0xFB, 0x3A, 0xB1, 0xFE, 0x47, 0x3A, 0xB0, 0xFE, 0xB8, 0x28, 0xF5]
const IDLE_LOOP_CYCLES := 50
const IDLE_LOOP_INSTRUCTIONS := 6
const IDLE_QUEUE_READ := 0xFEB0
const IDLE_QUEUE_WRITE := 0xFEB1
## Sound kept queued ahead of the audio output, in seconds: enough to ride
## out uneven frame times, short enough not to be heard as a delay.
const QUEUE_TARGET := 0.05

var cpu: Z80
var chip := YM2610.new()
var driver_rom := PackedByteArray()
var ram := PackedByteArray()
## Offsets into the driver ROM of the four banked windows at 8000, C000, E000 and F000.
var bank := [0x8000, 0xC000, 0xE000, 0xF000]

var reply := 0
## Commands on their way to the driver, as [sound CPU time, value].
var commands: Array = []
var nmi_enabled := false
var _latch := 0
var _idle_pc := -1
var _nmi_pending := false
var _address := [0, 0]

## Optional register-write log for comparison with MAME:
## [port "A"/"B", register, value, sound CPU time in cycles]
var write_log: Array = []
var logging := false
## No audio output (headless tools).
var silent := false
## Keep the sound from the audio output (it is still rendered and captured).
var muted := false
## Times the audio output ran out of sound, and frames of sound dropped
## because the game ran ahead of it.
var underruns := 0
var dropped := 0
## Time the last run_frame() took, in milliseconds.
var frame_ms := 0.0
## Render sound in run_frame(). Off, only the driver runs.
var render_sound := true
## Keep everything rendered in `captured`, for writing a recording.
var capturing := false
var captured := PackedVector2Array()

var _rendered := PackedVector2Array()
var _playback: AudioStreamGeneratorPlayback
var _queue_size := 0


func _init() -> void:
	ram.resize(0x800)
	cpu = Z80.new(self)


func _ready() -> void:
	if silent:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = YM2610.SAMPLE_RATE
	stream.buffer_length = 0.25
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()
	_playback = player.get_stream_playback()


## Loads the driver and sample ROMs from the user's ROM folder.
func load_roms(dir: String) -> bool:
	driver_rom = FileAccess.get_file_as_bytes(dir.path_join("213-m1.m1"))
	var samples_rom := FileAccess.get_file_as_bytes(dir.path_join("213-v1.v1")) \
			+ FileAccess.get_file_as_bytes(dir.path_join("213-v2.v2"))
	chip.set_sample_rom(samples_rom)
	if driver_rom.size() != 0x20000 or samples_rom.is_empty():
		push_error("Sound ROMs not found in %s" % dir)
		return false
	cpu.reset()
	# only skip the idle loop of the driver this was worked out for
	_idle_pc = IDLE_LOOP
	for index in IDLE_LOOP_CODE.size():
		if driver_rom[IDLE_LOOP + index] != IDLE_LOOP_CODE[index]:
			_idle_pc = -1
	cpu.stop_pc = _idle_pc
	return true


## Writes stereo sound at the chip's sample rate as a 16-bit WAV file.
static func save_wav(sound: PackedVector2Array, path: String) -> void:
	var pcm := PackedByteArray()
	pcm.resize(sound.size() * 4)
	for index in sound.size():
		pcm.encode_s16(index * 4, clampi(roundi(sound[index].x * 32767.0), -32768, 32767))
		pcm.encode_s16(index * 4 + 2, clampi(roundi(sound[index].y * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = roundi(YM2610.SAMPLE_RATE)
	stream.data = pcm
	stream.save_to_wav(path)


## Sends the sound of the last run_frame() to the audio output.
## Call from the main thread once that run has finished.
func play_rendered() -> void:
	if _playback == null or muted or _rendered.is_empty():
		_rendered.clear()
		return
	var free_frames := _playback.get_frames_available()
	if _queue_size == 0:
		_queue_size = free_frames
	var queued := _queue_size - free_frames
	if queued == 0:
		# starting, or the output ran dry: put some silence ahead
		var lead := PackedVector2Array()
		lead.resize(int(YM2610.SAMPLE_RATE * QUEUE_TARGET))
		_playback.push_buffer(lead)
		underruns += 1
	elif queued > YM2610.SAMPLE_RATE * QUEUE_TARGET * 3 or _rendered.size() > free_frames:
		# the game is running ahead of the audio output: drop this frame's sound
		dropped += 1
		_rendered.clear()
		return
	_playback.push_buffer(_rendered)
	_rendered.clear()


## A command byte written by the main program, `delay` sound CPU cycles
## after the start of the frame that run_frame() will run next.
func command(value: int, delay := 0) -> void:
	commands.append([cpu.cycles + delay, value])


## Runs the sound CPU for one video frame and renders the frame's sound.
func run_frame() -> void:
	var started := Time.get_ticks_usec()
	var target := cpu.cycles + CYCLES_PER_FRAME
	while cpu.cycles < target:
		var now := cpu.cycles
		var limit := target
		if not commands.is_empty():
			if now >= commands[0][0]:
				_latch = commands.pop_front()[1]
				_nmi_pending = true
			else:
				limit = mini(limit, commands[0][0])
		if _nmi_pending and nmi_enabled:
			_nmi_pending = false
			cpu.nmi()
		if chip.irq(now):
			cpu.irq()
		else:
			limit = mini(limit, chip.next_timer_event())
		if cpu.pc == _idle_pc:
			_skip_idle_loop(limit)
		cpu.run(maxi(limit, cpu.cycles + 1))
		if cpu.bad_opcode >= 0:
			push_error("Sound driver hit an unimplemented opcode %04X near %04X" % [cpu.bad_opcode, cpu.pc])
			cpu.bad_opcode = -1
	if render_sound:
		chip.render(cpu.cycles)
		_rendered = chip.frames()
		if capturing:
			captured.append_array(_rendered)
	else:
		chip.discard_writes()
	frame_ms = (Time.get_ticks_usec() - started) / 1000.0


## The driver's main loop waits for its command queue to fill by comparing
## the queue's read and write positions over and over. Nothing changes until
## an interrupt arrives, so whole turns of that loop are accounted for here
## instead of being executed: most of the sound CPU's time goes there.
func _skip_idle_loop(limit: int) -> void:
	var turns := (limit - cpu.cycles) / IDLE_LOOP_CYCLES
	if turns <= 0 or ram[IDLE_QUEUE_READ - 0xF800] != ram[IDLE_QUEUE_WRITE - 0xF800]:
		return
	cpu.iff1 = true
	cpu.iff2 = true
	cpu.r += turns * IDLE_LOOP_INSTRUCTIONS
	cpu.cycles += turns * IDLE_LOOP_CYCLES


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
			return chip.status(cpu.cycles)
		0x05:
			return chip.read(0, _address[0])
		0x06:
			return chip.flags(cpu.cycles)
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


func _chip_write(port: int, register: int, value: int) -> void:
	if logging:
		write_log.append(["A" if port == 0 else "B", register, value, cpu.cycles])
	chip.write(port, register, value, cpu.cycles)
