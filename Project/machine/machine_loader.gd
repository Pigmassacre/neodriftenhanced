class_name MachineLoader
extends RefCounted
## Builds the machine from the user's ROM files and the locally generated
## program code, and restores machine snapshots captured from MAME.

const PROGRAM_ROM := "neodrift/213-p1.p1"
const BIOS_ROM := "neogeo/sp-s2.sp1"
const PROGRAM_SCRIPT := "data/game/code/program.gd"
const SNAPSHOT_MAGIC := "NDS1"
## Where MAME's E clock is at the start of frame 0, in NeoGeoMachine.e_clock's
## terms. Found by comparing interrupt times with MAME's instruction trace.
const E_CLOCK_PHASE := 8


## Where neodrift/, neogeo/ and data/ are: the top of the repository, or in
## an exported game a folder in the user's folder that boot.gd fills.
static func repo_dir() -> String:
	if OS.has_feature("template"):
		return ProjectSettings.globalize_path("user://game")
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


## Returns the machine, or null. It runs the hand-written game of
## Project/game/ alone, unless `translated`: then it is an instance of the
## program generated from the ROM, in which, with `hand_written`, the
## routines of Project/game/ replace their translated originals (all of
## them, or those named by a command line argument
## --only-routines=ADDRESS,ADDRESS... in hexadecimal). That is for checking
## the hand-written game against the original (Tools/verify_session.py).
static func create(hand_written := true, translated := true) -> NeoGeoMachine:
	var root := repo_dir()
	var file := FileAccess.get_file_as_bytes(root.path_join(PROGRAM_ROM))
	var bios := FileAccess.get_file_as_bytes(root.path_join(BIOS_ROM))
	if file.size() != 0x200000 or bios.is_empty():
		push_error("ROM files not found under %s" % root)
		return null
	# The file already holds little-endian words; its second megabyte is
	# mapped at address 0 and its first at 0x200000.
	var rom := file.slice(0x100000) + file.slice(0, 0x100000)
	if not translated:
		var game := NeoGeoMachine.new()
		game.setup(rom, bios)
		Decomp.install_native(game)
		return game
	var script := load(root.path_join(PROGRAM_SCRIPT)) as GDScript
	if script == null:
		push_error("Generated program missing - run Tools/recomp/build_code.py")
		return null
	var machine: NeoGeoMachine = script.new()
	machine.setup(rom, bios)
	if hand_written:
		var only: Array[int] = []
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--only-routines="):
				for address in arg.trim_prefix("--only-routines=").split(","):
					only.append(address.hex_to_int())
		Decomp.install(machine, only)
	return machine


## Reads a seed log written by the MAME harness: for each frame, the random
## seed when the main loop left its wait for the vertical blank.
static func read_seed_log(path: String) -> Dictionary:
	var seeds := {}
	var log := FileAccess.open(path, FileAccess.READ)
	if log == null:
		return seeds
	log.big_endian = true
	while log.get_position() < log.get_length():
		var frame := log.get_32()
		seeds[frame] = log.get_16()
	return seeds


static func load_snapshot(machine: RefCounted, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ERR_FILE_NOT_FOUND
	f.big_endian = true
	if f.get_buffer(4).get_string_from_ascii() != SNAPSHOT_MAGIC:
		return ERR_FILE_UNRECOGNIZED
	machine.set_meta("snapshot_frame", f.get_32())
	# A frame is 2 cycles more than a whole number of E clock periods, so the
	# clock's phase at the start of a frame follows from the frame number.
	machine.e_clock = posmod(machine.get_meta("snapshot_frame") * 2 + E_CLOCK_PHASE, 10)
	var regs: Array[int] = []
	for i in 18:
		regs.append(f.get_32())
	machine.d0 = regs[0]
	machine.d1 = regs[1]
	machine.d2 = regs[2]
	machine.d3 = regs[3]
	machine.d4 = regs[4]
	machine.d5 = regs[5]
	machine.d6 = regs[6]
	machine.d7 = regs[7]
	machine.a0 = regs[8]
	machine.a1 = regs[9]
	machine.a2 = regs[10]
	machine.a3 = regs[11]
	machine.a4 = regs[12]
	machine.a5 = regs[13]
	machine.a6 = regs[14]
	machine.a7 = regs[15]
	machine.usp = regs[16]
	machine.pc = regs[17] & 0xFFFFFF
	var sr := f.get_16()
	machine.supervisor = (sr & 0x2000) != 0
	machine.ipl = (sr >> 8) & 7
	machine.set_ccr(sr)
	machine.vram_addr = f.get_16()
	machine.vram_mod = f.get_16()
	machine.lspc_mode = f.get_16()
	machine.timer_reload = f.get_32()
	var latches := f.get_buffer(8)
	machine.shadow = latches[0] != 0
	machine.bios_vectors = latches[1] == 0
	machine.fix_from_cart = latches[5] != 0
	machine.sram_locked = latches[6] == 0
	machine.palette_bank = latches[7]
	machine.ram = _swap_words(f.get_buffer(0x10000))
	machine.sram = _swap_words(f.get_buffer(0x10000))
	for i in 0x8800:
		machine.vram[i] = f.get_16()
	for i in 0x1000:
		machine.palette[machine.palette_bank * 0x1000 + i] = f.get_16()
	return OK


## Converts between bus byte order and the machine's little-endian word storage.
static func _swap_words(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(data.size())
	for i in range(0, data.size(), 2):
		out[i] = data[i + 1]
		out[i + 1] = data[i]
	return out
