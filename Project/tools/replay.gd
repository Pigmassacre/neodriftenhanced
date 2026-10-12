extends SceneTree
## Headless verification run: restores a MAME snapshot, replays scripted
## inputs and logs work RAM after every frame for comparison with MAME.
##
##   godot --headless --path Project --script res://tools/replay.gd -- \
##       --snapshot=PATH --frames=N --out=PATH [--input=FIELD:FIRST-LAST ...]
##       [--soundlog=PATH] [--seedlog=PATH] [--dump=FRAME[,FRAME...] --dump-dir=DIR]
##       [--topup=OFFSET:BELOW:VALUE] [--cycles=FIRST-LAST:PATH] [--profile=PATH]
##       [--translated | --check-routines]
##
## --dump writes the video state after those frames in the same format as
## the MAME harness dumps, for Tools/render.py and Tools/compare_video.py.
##
## --seedlog applies the random seeds MAME had each time the main loop left
## its vblank wait (see Tools/mame/harness.lua). The game steps the seed
## while waiting, so its value depends on exact CPU timing. The run reports
## how often the port's own seed already agreed, as a measure of its timing.
##
## --cycles writes "address cycle-count" for every translated block entered
## in those frames, for Tools/compare_cycles.py --port.
##
## --translated runs the translated program alone, without the hand-written
## routines of Project/game/. --check-routines does too, but runs every call
## of a routine that has a hand-written version both ways and reports where
## the outcomes differ (see RoutineCheck).
##
## --profile counts how often every translated block ran and which block ran
## before it ("B address count", "E from to count"), for Tools/routines.py.
##
## --topup keeps a work RAM word topped up before every frame (see
## NeoGeoMachine.top_up); numbers are decimal.
##
## FIELD is a, b, c, d, up, down, left, right, start or coin; frames count
## from 0 at the snapshot. Unknown code addresses are appended to
## data/game/seeds.txt so the next build_code.py run includes them.

## Where the main loop continues after its vblank wait, and the seed's RAM offset.
const WAIT_EXIT := 0xB80
const SEED := 0x430
## One turn of the wait loop steps the seed once and takes this many CPU cycles.
const WAIT_TURN_CYCLES := 146
const MAX_TURNS := 300
const UNKNOWN_TURNS := 1 << 20
const P1_BITS := {"up": 1, "down": 2, "left": 4, "right": 8, "a": 16, "b": 32, "c": 64, "d": 128}


func _init() -> void:
	var snapshot := ""
	var out_path := ""
	var frames := 60
	var inputs: Array = []
	var seedlog_path := ""
	var dump_frames: Array[int] = []
	var dump_dir := ""
	var sound_path := ""
	var topup := PackedInt32Array()
	var cycle_span: Array[int] = []
	var cycle_out: FileAccess = null
	var profile_path := ""
	var hand_written := true
	var check_routines := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			snapshot = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--dump="):
			for value in arg.trim_prefix("--dump=").split(","):
				dump_frames.append(int(value))
		elif arg.begins_with("--soundlog="):
			sound_path = arg.trim_prefix("--soundlog=")
		elif arg.begins_with("--dump-dir="):
			dump_dir = arg.trim_prefix("--dump-dir=")
		elif arg.begins_with("--seedlog="):
			seedlog_path = arg.trim_prefix("--seedlog=")
		elif arg.begins_with("--cycles="):
			var parts := arg.trim_prefix("--cycles=").split(":", true, 1)
			cycle_span = [int(parts[0].split("-")[0]), int(parts[0].split("-")[1])]
			cycle_out = FileAccess.open(parts[1], FileAccess.WRITE)
		elif arg == "--translated":
			hand_written = false
		elif arg == "--check-routines":
			hand_written = false
			check_routines = true
		elif arg.begins_with("--profile="):
			profile_path = arg.trim_prefix("--profile=")
		elif arg.begins_with("--topup="):
			for value in arg.trim_prefix("--topup=").split(":"):
				topup.append(int(value))
		elif arg.begins_with("--input="):
			var parts := arg.trim_prefix("--input=").split(":")
			var span := parts[1].split("-")
			inputs.append([parts[0], int(span[0]), int(span[1])])
	var machine := MachineLoader.create(hand_written)
	if machine == null or MachineLoader.load_snapshot(machine, snapshot) != OK:
		push_error("Could not set up the machine")
		quit(1)
		return
	var checker: RoutineCheck = null
	if check_routines:
		checker = RoutineCheck.new(machine)
		checker.install()
	var exit_seeds := {}
	var frame_box := [0]
	var timing := [0, 0]
	var offsets: Array[int] = []
	if seedlog_path != "":
		exit_seeds = MachineLoader.read_seed_log(seedlog_path)
		var first: int = machine.get_meta("snapshot_frame")
		machine.hook_block(WAIT_EXIT, func() -> void:
			var seed: Variant = exit_seeds.get(first + frame_box[0])
			if seed != null:
				# the seed counts the turns of the wait loop, so it agreeing
				# with MAME's means the frame's work took the same time
				timing[1] += 1
				var turns := _turns_apart(machine.ram.decode_u16(SEED), seed)
				if turns == 0:
					timing[0] += 1
				offsets.append(turns)
				machine.ram.encode_u16(SEED, seed))
	if cycle_out != null:
		for address: int in machine.block_table().keys():
			machine.hook_block(address, func() -> void:
				if frame_box[0] >= cycle_span[0] and frame_box[0] <= cycle_span[1]:
					cycle_out.store_line("%06X %d" % [address, machine.cyc]))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--watch="):
			# reports every change of a work RAM word: --watch=OFFSET (hex)
			var offset := arg.trim_prefix("--watch=").hex_to_int()
			var seen := [machine.ram.decode_u16(offset), 0]
			for address: int in machine.block_table().keys():
				machine.hook_block(address, func() -> void:
					var value := machine.ram.decode_u16(offset)
					if value != seen[0]:
						print("frame %d: %04X -> %04X before %06X (after %06X), line %d, a6=%X" % [
								frame_box[0], seen[0], value, address, seen[1], machine.raster_line(), machine.a6])
						seen[0] = value
					seen[1] = address)
	var block_counts := {}
	var edge_counts := {}
	var previous := [0]
	if profile_path != "":
		for address: int in machine.block_table().keys():
			machine.hook_block(address, func() -> void:
				block_counts[address] = block_counts.get(address, 0) + 1
				var edge: int = (previous[0] << 24) | address
				edge_counts[edge] = edge_counts.get(edge, 0) + 1
				previous[0] = address)
	var out := FileAccess.open(out_path, FileAccess.WRITE) if out_path != "" else null
	var sound_out := FileAccess.open(sound_path, FileAccess.WRITE) if sound_path != "" else null
	var started := Time.get_ticks_usec()
	var done := 0
	for frame in frames:
		machine.input_p1 = 0
		machine.input_start = 0
		machine.input_coin = 0
		for entry in inputs:
			if frame >= entry[1] and frame <= entry[2]:
				if entry[0] == "start":
					machine.input_start |= 1
				elif entry[0] == "coin":
					machine.input_coin |= 1
				else:
					machine.input_p1 |= P1_BITS[entry[0]]
		frame_box[0] = frame
		if checker != null:
			checker.frame = frame
		if not topup.is_empty():
			machine.top_up(topup[0], topup[1], topup[2])
		machine.run_frame()
		if machine.halted:
			break
		done += 1
		if sound_out != null:
			for command: int in machine.sound_log:
				sound_out.store_line("%d %02X" % [frame, command])
		machine.sound_log.clear()
		machine.sound_log_times.clear()
		if frame + 1 in dump_frames:
			_dump(machine, dump_dir.path_join("g%06d.bin" % (frame + 1)), frame + 1)
		if out != null:
			out.store_buffer(MachineLoader._swap_words(machine.ram))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("ran %d frames in %.0f ms (%.2f ms/frame)" % [done, elapsed, elapsed / maxi(done, 1)])
	if timing[1] > 0:
		offsets.sort()
		var far := offsets.count(UNKNOWN_TURNS)
		print("timing: the wait for the vertical blank ended on MAME's seed in %d of %d frames; turns of the wait loop (%d cycles each) more than MAME: median %d, nine in ten frames within %d to %d; %d frames further than %d off"
				% [timing[0], timing[1], WAIT_TURN_CYCLES, offsets[offsets.size() / 2],
				offsets[offsets.size() / 20], offsets[offsets.size() * 19 / 20 - far], far, MAX_TURNS])
	if checker != null:
		checker.report()
	if profile_path != "":
		var profile := FileAccess.open(profile_path, FileAccess.WRITE)
		for address: int in block_counts:
			profile.store_line("B %06X %d" % [address, block_counts[address]])
		for edge: int in edge_counts:
			profile.store_line("E %06X %06X %d" % [edge >> 24, edge & 0xFFFFFF, edge_counts[edge]])
	if machine.missing_block >= 0:
		print("missing code at %06X" % machine.missing_block)
		var seeds := FileAccess.open(MachineLoader.repo_dir().path_join("data/game/seeds.txt"),
				FileAccess.READ_WRITE)
		if seeds == null:
			seeds = FileAccess.open(MachineLoader.repo_dir().path_join("data/game/seeds.txt"),
					FileAccess.WRITE)
		seeds.seek_end()
		seeds.store_line("%06X" % machine.missing_block)
	var halted: bool = machine.halted
	machine.release()
	quit(0 if not halted else 2)


## How many more turns of the wait loop led to `ours` than to `theirs`
## (negative for fewer), or UNKNOWN_TURNS if they are far apart.
func _turns_apart(ours: int, theirs: int) -> int:
	var ahead := theirs
	var behind := ours
	for turns in MAX_TURNS + 1:
		if ahead == ours:
			return turns
		if behind == theirs:
			return -turns
		ahead = _step_seed(ahead)
		behind = _step_seed(behind)
	return UNKNOWN_TURNS


## The seed step of the game's routine at $10B8.
func _step_seed(seed: int) -> int:
	var rotated := ((seed << 2) | (seed >> 14)) & 0xFFFF
	return (seed + rotated + 0x3711) & 0xFFFF


func _dump(machine: RefCounted, path: String, frame: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.big_endian = true
	f.store_buffer("NDF1".to_ascii_buffer())
	f.store_32(frame)
	f.store_16(machine.lspc_mode)
	f.store_8(int(machine.shadow))
	f.store_8(int(machine.fix_from_cart))
	f.store_8(machine.palette_bank)
	f.store_8(0)
	for i in 0x8800:
		f.store_16(machine.vram[i])
	for i in 0x1000:
		f.store_16(machine.palette[machine.palette_bank * 0x1000 + i])
	f.store_buffer(MachineLoader._swap_words(machine.ram))
