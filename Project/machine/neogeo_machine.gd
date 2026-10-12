class_name NeoGeoMachine
extends RefCounted
## Neo Geo MVS machine model that the recompiled game program runs on.
##
## The program itself is generated from the ROMs by Tools/recomp into
## data/game/code and extends this class: every basic block is a method that
## returns the address of the next block. This class provides the 68000
## registers and flags, the memory map, the video registers, the raster
## timer and interrupt delivery.
##
## Memory is stored as little-endian 16-bit words so that a word read is a
## single decode_u16; the byte at bus address A lives at index A ^ 1.

const CYCLES_PER_LINE := 768
const LINES_PER_FRAME := 264
const CYCLES_PER_FRAME := CYCLES_PER_LINE * LINES_PER_FRAME
## A frame starts with line 240, where the vertical blank begins. The
## interrupt for it is raised this many cycles later (59 ticks of the 24 MHz
## master clock, as in MAME), and the raster timer is reloaded later still
## (1146 ticks).
const VBLANK_LINE := 240
const VBLANK_IRQ_DELAY := 30
const VBLANK_RELOAD_DELAY := 573
const FIRST_VISIBLE_LINE := 16
## The game's wait for the vertical blank: where its loop starts, the work RAM
## word that ends it, the seed it steps, and the cycles one turn takes.
const E_CLOCK_CYCLES := 10
const WAIT_LOOP := 0xB6E
const WAIT_FLAG := 0x424
const WAIT_SEED := 0x430
const WAIT_TURN_CYCLES := 146
## The instruction after the loop's `rol.w #2`, which ends with 6 cycles off the bus.
const WAIT_ROTATE_END := 0x10C2
const WAIT_ROTATE_IDLE := 6

# 68000 state
var d0 := 0
var d1 := 0
var d2 := 0
var d3 := 0
var d4 := 0
var d5 := 0
var d6 := 0
var d7 := 0
var a0 := 0
var a1 := 0
var a2 := 0
var a3 := 0
var a4 := 0
var a5 := 0
var a6 := 0
var a7 := 0
var usp := 0
var fn := 0
var fz := 0
var fv := 0
var fc := 0
var fx := 0
var ipl := 7
var supervisor := true
var pc := 0
var stopped := false

# timing
var cyc := 0
var event_cyc := 0
var frame_start := 0
var _next_frame := -1
## When, in this frame, the vertical blank interrupt and the timer reload are
## still to come (-1 once they have), and when the frame ends.
var _irq_cyc := -1
var _reload_cyc := -1
var _deadline := 0
## Added to `cyc`, gives a count that is a multiple of ten where an interrupt
## handler starts. The phase is arbitrary, as it is from one power-on to the
## next; a snapshot sets it to what MAME had (see MachineLoader).
var e_clock := 0
var _irq1_cyc := 0
var _irq2_cyc := 0
var recheck := false
var halted := false
var missing_block := -1

# memory
var rom := PackedByteArray()
var bios := PackedByteArray()
var ram := PackedByteArray()
var sram := PackedByteArray()
var vram := PackedInt32Array()
var palette := PackedInt32Array()

# video registers
## Counts writes to video RAM and the palettes (tools/routine_check.gd uses
## it to tell whether they changed).
var video_writes := 0
var vram_addr := 0
var vram_mod := 0
var lspc_mode := 0
var timer_reload := 0
var timer_fire_cyc := -1
var auto_anim_counter := 0
var auto_anim_timer := 0
## Sprite vertical-position words changed while the picture was being drawn
## this frame, as (raster line, sprite, previous value). The game moves the
## background strips part-way down the screen with a raster interrupt.
var midframe_y: Array[Vector3i] = []
## Text layer words changed while the picture was being drawn this frame, as
## (raster line, video RAM address, previous value). When a frame's work runs
## long the game updates text after the raster has passed it, and the old
## text stays on screen for one more frame.
var midframe_text: Array[Vector3i] = []

# latches and interrupt lines
var bios_vectors := false
var fix_from_cart := true
var palette_bank := 0
var sram_locked := false
var shadow := false
var irq1_pending := false
var irq2_pending := false

# inputs (active high here; inverted on the bus)
## How many pixels of picture are drawn to each side of the hardware's 320
## (see NeoGeoVideo.view_width). The hand-written game routines that test
## whether something is in sight allow for it; 0 is the original.
var view_margin := 0

var input_p1 := 0
var input_p2 := 0
var input_start := 0
var input_coin := 0

# sound
var sound_command := 0
var sound_reply := 0
## Sound commands written this frame, and when: main CPU cycles since the frame began.
var sound_log: Array[int] = []
var sound_log_times: Array[int] = []

## Return address of a routine called by hand-written code: never a block.
const CALL_RETURN := 0xFFFFFE

var _table: Dictionary = {}
## Number of one bits in each 16-bit value (multiply timing).
static var ONES := PackedByteArray()


static func _static_init() -> void:
	ONES.resize(0x10000)
	for value in 0x10000:
		ONES[value] = ONES[value >> 1] + (value & 1)


func _init() -> void:
	ram.resize(0x10000)
	sram.resize(0x10000)
	vram.resize(0x10000)
	palette.resize(0x2000)


## Overridden by the generated program.
func block_table() -> Dictionary:
	return {}


func setup(program_rom: PackedByteArray, bios_rom: PackedByteArray) -> void:
	rom = program_rom
	bios = bios_rom
	_table = block_table()


## Runs `callback` every time execution reaches the block at `address`.
## Costs nothing for blocks that are not hooked.
func hook_block(address: int, callback: Callable) -> void:
	var original: Callable = _table[address]
	_table[address] = func() -> int:
		callback.call()
		return original.call()


## Call when done with the machine: the replaced and hooked blocks refer
## back to it, which would keep it and the hand-written routines alive.
func release() -> void:
	_table = {}
	remove_meta(&"hand_written")


## The code that runs when execution reaches `address`.
func block(address: int) -> Callable:
	return _table[address]


func set_block(address: int, code: Callable) -> void:
	_table[address] = code


## Replaces the translated routine at `address` with `routine`: hand-written
## code (see Project/game/) that takes its arguments from the registers and
## memory, leaves there what the callers use, and takes no CPU time.
func replace_routine(address: int, routine: Callable) -> void:
	_table[address] = func() -> int:
		routine.call()
		var back := r32(a7) & 0xFFFFFF
		a7 = (a7 + 4) & 0xFFFFFFFF
		return back


## Runs the routine at `address` until it returns, for hand-written code
## calling a routine that is still translated. Interrupts are taken inside
## it as usual, and if it runs past the end of the frame (the original waits
## for the vertical blank in places) the next frame starts inside it: the
## frame that `run_frame` was running is then twice as long.
func call_routine(address: int) -> void:
	var stack := a7
	a7 = (a7 - 4) & 0xFFFFFFFF
	w32(a7, CALL_RETURN)
	var at := address
	while not (at == CALL_RETURN and a7 == stack):
		if cyc >= event_cyc or recheck:
			pc = at
			_fire_timer()
			if cyc >= _deadline:
				_begin_frame()
			_take_events()
			at = pc
		var code: Variant = _table.get(at)
		if code == null or halted:
			missing_block = at
			halted = true
			return
		at = code.call()


# --- execution ---------------------------------------------------------------

## Runs one video frame, starting where the vertical blank begins.
func run_frame() -> void:
	_begin_frame()
	while cyc < _deadline and not halted:
		_take_events()
		if stopped:
			cyc = maxi(cyc, event_cyc)
		else:
			while cyc < event_cyc and not recheck:
				if pc == WAIT_LOOP:
					_skip_wait_turns()
				var block: Variant = _table.get(pc)
				if block == null:
					missing_block = pc
					halted = true
					return
				pc = block.call()
		_fire_timer()


func _begin_frame() -> void:
	# The last block of a frame runs a little past its end; the next frame
	# still starts on time.
	frame_start = _next_frame if (_next_frame >= 0 and cyc >= _next_frame
			and cyc - _next_frame < CYCLES_PER_LINE) else cyc
	_next_frame = frame_start + CYCLES_PER_FRAME
	midframe_y.clear()
	midframe_text.clear()
	_tick_auto_anim()
	_irq_cyc = frame_start + VBLANK_IRQ_DELAY
	_reload_cyc = frame_start + VBLANK_RELOAD_DELAY
	_deadline = frame_start + CYCLES_PER_FRAME


## Raises what has come due, finds when the next event is (`event_cyc`) and
## lets the processor take an interrupt that is waiting.
func _take_events() -> void:
	if _irq_cyc >= 0 and cyc >= _irq_cyc:
		irq1_pending = true
		_irq1_cyc = _irq_cyc
		_irq_cyc = -1
	if _reload_cyc >= 0 and cyc >= _reload_cyc:
		if lspc_mode & 0x40:
			timer_fire_cyc = _reload_cyc + (timer_reload + 1) * 2
		_reload_cyc = -1
	event_cyc = _deadline
	if _irq_cyc >= 0:
		event_cyc = _irq_cyc
	elif _reload_cyc >= 0:
		event_cyc = _reload_cyc
	if timer_fire_cyc >= 0 and timer_fire_cyc < event_cyc:
		event_cyc = timer_fire_cyc
	if not _service_interrupts():
		# an interrupt has to wait for the next instruction
		event_cyc = cyc + 1
	recheck = false


func _fire_timer() -> void:
	if timer_fire_cyc >= 0 and cyc >= timer_fire_cyc:
		if lspc_mode & 0x10:
			irq2_pending = true
			_irq2_cyc = timer_fire_cyc
		if lspc_mode & 0x80:
			timer_fire_cyc += (timer_reload + 1) * 2
		else:
			timer_fire_cyc = -1


## The game's main loop waits for the vertical blank at WAIT_LOOP, stepping
## its random seed once a turn. This takes all the whole turns that fit before
## the next event in one go, leaving what the translated loop would have left.
## The translated loop (one block per instruction, see build_code.py) runs
## the rest, so the interrupt still arrives on the right instruction.
func _skip_wait_turns() -> void:
	if ram.decode_u16(WAIT_FLAG) != 0:
		return
	var turns := (event_cyc - cyc) / WAIT_TURN_CYCLES
	if turns <= 0:
		return
	var seed := ram.decode_u16(WAIT_SEED)
	for turn in turns:
		var sum := seed + ((((seed << 2) | (seed >> 14)) + 0x3711) & 0xFFFF)
		fx = sum >> 16
		seed = sum & 0xFFFF
	ram.encode_u16(WAIT_SEED, seed)
	# the return address and the saved register the last turn left under the stack
	w32((a7 - 4) & 0xFFFFFFFF, WAIT_LOOP + 0x10)
	w16((a7 - 6) & 0xFFFFFFFF, d0 & 0xFFFF)
	cyc += turns * WAIT_TURN_CYCLES


## Sets the work RAM word at `offset` to `value` if it is above 0 and under
## `below`. Verification sessions use it between frames to keep the stage
## timer from running out, as the MAME harness does (`topup` in harness.lua).
func top_up(offset: int, below: int, value: int) -> void:
	var current := ram.decode_u16(offset)
	if current > 0 and current < below:
		ram.encode_u16(offset, value)


## Starts the handler of a pending interrupt. Returns false if one is pending
## that the instruction just finished came too late to notice.
func _service_interrupts() -> bool:
	var level := 2 if irq2_pending else (1 if irq1_pending else 0)
	if level <= ipl:
		return true
	# The 68000 looks for interrupts during an instruction's last bus cycle.
	# Most end with it, but not the wait loop's rotate, where the interrupt
	# usually arrives.
	if pc == WAIT_ROTATE_END and cyc - (_irq2_cyc if level == 2 else _irq1_cyc) < WAIT_ROTATE_IDLE:
		return false
	var sr := get_sr()
	supervisor = true
	a7 = (a7 - 4) & 0xFFFFFFFF
	w32(a7, pc)
	a7 = (a7 - 2) & 0xFFFFFFFF
	w16(a7, sr)
	ipl = level
	stopped = false
	var vector := 0x60 + level * 4
	var source := bios if bios_vectors else rom
	pc = ((source.decode_u16(vector) << 16) | source.decode_u16(vector + 2)) & 0xFFFFFF
	# The interrupts are autovectored, and the 68000 answers those in step
	# with its E clock, a tenth of its own: the handler starts on a fixed
	# phase of it, 50 to 59 cycles after the interrupted instruction.
	cyc += 50
	cyc += posmod(-(cyc + e_clock), E_CLOCK_CYCLES)
	return true


func fault(address: int) -> int:
	push_error("Program fault at %06X" % address)
	halted = true
	recheck = true
	return address


func raster_line() -> int:
	return (VBLANK_LINE + (cyc - frame_start) / CYCLES_PER_LINE) % LINES_PER_FRAME


func _start_timer() -> void:
	# The counter runs at the pixel clock, two CPU cycles per pixel.
	timer_fire_cyc = cyc + (timer_reload + 1) * 2


func _tick_auto_anim() -> void:
	if auto_anim_timer == 0:
		auto_anim_timer = lspc_mode >> 8
		auto_anim_counter = (auto_anim_counter + 1) & 7
	else:
		auto_anim_timer -= 1


# --- status register ---------------------------------------------------------

func get_ccr() -> int:
	return (fx << 4) | (fn << 3) | (fz << 2) | (fv << 1) | fc


func set_ccr(value: int) -> void:
	fx = (value >> 4) & 1
	fn = (value >> 3) & 1
	fz = (value >> 2) & 1
	fv = (value >> 1) & 1
	fc = value & 1


func get_sr() -> int:
	return (0x2000 if supervisor else 0) | (ipl << 8) | get_ccr()


func set_sr(value: int) -> void:
	var new_supervisor := (value & 0x2000) != 0
	if new_supervisor != supervisor:
		var other := usp
		usp = a7
		a7 = other
		supervisor = new_supervisor
	ipl = (value >> 8) & 7
	set_ccr(value)
	recheck = true


# --- memory ------------------------------------------------------------------

func r8(address: int) -> int:
	address &= 0xFFFFFF
	if address < 0x100000:
		return rom[address ^ 1]
	if address < 0x200000:
		return ram[(address & 0xFFFF) ^ 1]
	if address < 0x300000:
		return rom[(address - 0x100000) ^ 1]
	var word := _io_read(address & 0xFFFFFE)
	return (word & 0xFF) if (address & 1) else (word >> 8)


func r16(address: int) -> int:
	address &= 0xFFFFFE
	if address < 0x100000:
		return rom.decode_u16(address)
	if address < 0x200000:
		return ram.decode_u16(address & 0xFFFF)
	if address < 0x300000:
		return rom.decode_u16(address - 0x100000)
	return _io_read(address)


func r32(address: int) -> int:
	address &= 0xFFFFFE
	if address >= 0x100000 and address < 0x1FFFFE:
		address &= 0xFFFF
		return (ram.decode_u16(address) << 16) | ram.decode_u16((address + 2) & 0xFFFF)
	return (r16(address) << 16) | r16(address + 2)


func w8(address: int, value: int) -> void:
	address &= 0xFFFFFF
	if address >= 0x100000 and address < 0x200000:
		ram[(address & 0xFFFF) ^ 1] = value
	else:
		_io_write8(address, value)


func w16(address: int, value: int) -> void:
	address &= 0xFFFFFE
	if address >= 0x100000 and address < 0x200000:
		ram.encode_u16(address & 0xFFFF, value)
	else:
		_io_write(address, value)


func w32(address: int, value: int) -> void:
	w16(address, (value >> 16) & 0xFFFF)
	w16(address + 2, value & 0xFFFF)


func _io_read(address: int) -> int:
	var region := address >> 16
	if region >= 0xC0 and region < 0xD0:
		return bios.decode_u16(address & 0x1FFFE)
	if region == 0x3C:
		match address & 6:
			0, 2:
				return vram[vram_addr]
			4:
				return vram_mod
			_:
				var counter := raster_line() + 0x100
				if counter >= 0x200:
					counter -= LINES_PER_FRAME
				return (counter << 7) | (auto_anim_counter & 7)
	if region >= 0x40 and region < 0x80:
		return palette[palette_bank * 0x1000 + ((address & 0x1FFE) >> 1)]
	if region == 0x30:
		if (address & 0x80) != 0:
			# test switch (active low) in bit 7, remaining bits read low
			return 0xFF80
		return ((input_p1 ^ 0xFF) << 8) | 0xFF
	if region == 0x34:
		return ((input_p2 ^ 0xFF) << 8) | 0xFF
	if region == 0x32:
		# high byte: sound CPU reply; low byte: coins (active low), clock chip bits low
		return (sound_reply << 8) | (0x3F ^ (input_coin & 7))
	if region == 0x38:
		return ((0xFF ^ (input_start & 0x0F)) << 8) | 0xFF
	if region >= 0xD0 and region < 0xE0:
		return sram.decode_u16(address & 0xFFFF)
	return 0xFFFF


func _io_write(address: int, value: int) -> void:
	var region := address >> 16
	if region == 0x3C:
		match address & 0xE:
			0:
				vram_addr = value
			2:
				if vram_addr >= 0x8200 and vram_addr < 0x8400 and vram[vram_addr] != value:
					var line := raster_line()
					if line >= FIRST_VISIBLE_LINE and line < VBLANK_LINE:
						midframe_y.append(Vector3i(line, vram_addr - 0x8200, vram[vram_addr]))
				elif vram_addr >= 0x7000 and vram_addr < 0x7500 and vram[vram_addr] != value:
					var line := raster_line()
					if line >= FIRST_VISIBLE_LINE and line < VBLANK_LINE:
						midframe_text.append(Vector3i(line, vram_addr, vram[vram_addr]))
				vram[vram_addr] = value
				video_writes += 1
				vram_addr = (vram_addr & 0x8000) | ((vram_addr + vram_mod) & 0x7FFF)
			4:
				vram_mod = value
			6:
				lspc_mode = value
			8:
				timer_reload = (timer_reload & 0xFFFF) | (value << 16)
			10:
				timer_reload = (timer_reload & 0xFFFF0000) | value
				if lspc_mode & 0x20:
					_start_timer()
					recheck = true
			12:
				if value & 2:
					irq2_pending = false
				if value & 4:
					irq1_pending = false
	elif region >= 0x40 and region < 0x80:
		palette[palette_bank * 0x1000 + ((address & 0x1FFE) >> 1)] = value
		video_writes += 1
	elif region >= 0xD0 and region < 0xE0:
		if not sram_locked:
			sram.encode_u16(address & 0xFFFF, value)
	else:
		_io_write8(address, value >> 8)
		_io_write8(address + 1, value & 0xFF)


func _io_write8(address: int, value: int) -> void:
	var region := address >> 16
	if region == 0x3A:
		var on := (address & 0x10) != 0
		match (address >> 1) & 7:
			0:
				shadow = on
			1:
				bios_vectors = not on
			5:
				fix_from_cart = on
			6:
				sram_locked = not on
			7:
				palette_bank = 1 if on else 0
	elif region == 0x32:
		if (address & 1) == 0:
			sound_command = value
			sound_log.append(value)
			sound_log_times.append(cyc - frame_start)
	elif region >= 0xD0 and region < 0xE0:
		if not sram_locked:
			sram[(address & 0xFFFF) ^ 1] = value
	elif region == 0x3C or (region >= 0x40 and region < 0x80):
		# byte access to a word register: both halves carry the value
		_io_write(address & 0xFFFFFE, (value << 8) | value)


# --- arithmetic helpers ------------------------------------------------------

func _shift_flags(result: int, bits: int) -> void:
	fn = (result >> (bits - 1)) & 1
	fz = int(result == 0)


func sh_lsl(value: int, count: int, bits: int) -> int:
	var mask := (1 << bits) - 1
	fv = 0
	if count == 0:
		fc = 0
	else:
		fc = ((value >> (bits - count)) & 1) if count <= bits else 0
		fx = fc
		value = ((value << count) & mask) if count < bits else 0
	_shift_flags(value, bits)
	return value


func sh_lsr(value: int, count: int, bits: int) -> int:
	fv = 0
	if count == 0:
		fc = 0
	else:
		fc = ((value >> (count - 1)) & 1) if count <= bits else 0
		fx = fc
		value = (value >> count) if count < bits else 0
	_shift_flags(value, bits)
	return value


func sh_asr(value: int, count: int, bits: int) -> int:
	var mask := (1 << bits) - 1
	var sign := (value >> (bits - 1)) & 1
	fv = 0
	if count == 0:
		fc = 0
	elif count >= bits:
		fc = sign
		fx = fc
		value = mask if sign else 0
	else:
		fc = (value >> (count - 1)) & 1
		fx = fc
		value >>= count
		if sign:
			value |= (mask << (bits - count)) & mask
	_shift_flags(value, bits)
	return value


func sh_asl(value: int, count: int, bits: int) -> int:
	var mask := (1 << bits) - 1
	if count == 0:
		fc = 0
		fv = 0
	else:
		if count >= bits:
			fv = int(value != 0)
		else:
			var top := value >> (bits - count - 1)
			fv = int(top != 0 and top != (1 << (count + 1)) - 1)
		fc = ((value >> (bits - count)) & 1) if count <= bits else 0
		fx = fc
		value = ((value << count) & mask) if count < bits else 0
	_shift_flags(value, bits)
	return value


func sh_rol(value: int, count: int, bits: int) -> int:
	var mask := (1 << bits) - 1
	fv = 0
	if count == 0:
		fc = 0
	else:
		var k := count % bits
		value = ((value << k) | (value >> (bits - k))) & mask
		fc = value & 1
	_shift_flags(value, bits)
	return value


func sh_ror(value: int, count: int, bits: int) -> int:
	var mask := (1 << bits) - 1
	fv = 0
	if count == 0:
		fc = 0
	else:
		var k := count % bits
		value = ((value >> k) | (value << (bits - k))) & mask
		fc = (value >> (bits - 1)) & 1
	_shift_flags(value, bits)
	return value


func sh_roxl(value: int, count: int, bits: int) -> int:
	var k := count % (bits + 1)
	var wide := (fx << bits) | value
	wide = ((wide << k) | (wide >> (bits + 1 - k))) & ((1 << (bits + 1)) - 1)
	fx = wide >> bits
	fc = fx
	fv = 0
	value = wide & ((1 << bits) - 1)
	_shift_flags(value, bits)
	return value


func sh_roxr(value: int, count: int, bits: int) -> int:
	var k := count % (bits + 1)
	var wide := (fx << bits) | value
	wide = ((wide >> k) | (wide << (bits + 1 - k))) & ((1 << (bits + 1)) - 1)
	fx = wide >> bits
	fc = fx
	fv = 0
	value = wide & ((1 << bits) - 1)
	_shift_flags(value, bits)
	return value


func divu(dividend: int, divisor: int) -> int:
	fc = 0
	if divisor == 0:
		fault(pc)
		return dividend
	var quotient := dividend / divisor
	if quotient > 0xFFFF:
		fv = 1
		fn = 1
		cyc += 10
		return dividend
	# the time follows the processor's shift-and-subtract steps
	var steps := 38
	var rest := dividend
	var high := divisor << 16
	for step in 15:
		var carried := (rest & 0x80000000) != 0
		rest = (rest << 1) & 0xFFFFFFFF
		if carried:
			rest = (rest - high) & 0xFFFFFFFF
		else:
			steps += 2
			if rest >= high:
				rest -= high
				steps -= 1
	cyc += steps * 2
	fv = 0
	fn = quotient >> 15
	fz = int(quotient == 0)
	return ((dividend % divisor) << 16) | quotient


func divs(dividend: int, divisor: int) -> int:
	fc = 0
	if divisor == 0:
		fault(pc)
		return dividend
	var a := (dividend ^ 0x80000000) - 0x80000000
	var b := (divisor ^ 0x8000) - 0x8000
	var steps := 7 if a < 0 else 6
	if (absi(a) >> 16) >= absi(b):
		fv = 1
		fn = 1
		cyc += (steps + 2) * 2
		return dividend
	steps += 55
	if b >= 0:
		steps += -1 if a >= 0 else 1
	var magnitude := absi(a) / absi(b)
	for step in 15:
		if (magnitude & 0x8000) == 0:
			steps += 1
		magnitude <<= 1
	cyc += steps * 2
	var quotient := a / b
	if quotient > 32767 or quotient < -32768:
		fv = 1
		fn = 1
		return dividend
	fv = 0
	fn = (quotient >> 15) & 1
	fz = int(quotient == 0)
	return (((a % b) & 0xFFFF) << 16) | (quotient & 0xFFFF)


func abcd(source: int, dest: int) -> int:
	var result := (source & 0x0F) + (dest & 0x0F) + fx
	if result > 9:
		result += 6
	result += (source & 0xF0) + (dest & 0xF0)
	fc = int(result > 0x99)
	if fc:
		result -= 0xA0
	fx = fc
	result &= 0xFF
	if result != 0:
		fz = 0
	fn = result >> 7
	return result


## dest - source - X, in binary coded decimal.
func sbcd(source: int, dest: int) -> int:
	var result := (dest & 0x0F) - (source & 0x0F) - fx
	if result < 0:
		result -= 6
	result += (dest & 0xF0) - (source & 0xF0)
	fc = int(result < 0)
	if fc:
		result += 0xA0
	fx = fc
	result &= 0xFF
	if result != 0:
		fz = 0
	fn = result >> 7
	return result
