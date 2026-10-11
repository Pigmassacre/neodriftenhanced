extends SceneTree
## Headless verification run: restores a MAME snapshot, replays scripted
## inputs and logs work RAM after every frame for comparison with MAME.
##
##   godot --headless --path Project --script res://tools/replay.gd -- \
##       --snapshot=PATH --frames=N --out=PATH [--input=FIELD:FIRST-LAST ...]
##       [--soundlog=PATH] [--seedlog=PATH] [--dump=FRAME[,FRAME...] --dump-dir=DIR]
##
## --dump writes the video state after those frames in the same format as
## the MAME harness dumps, for Tools/render.py and Tools/compare_video.py.
##
## --seedlog applies the random seeds MAME had each time the main loop left
## its vblank wait (see Tools/mame/harness.lua). The game steps the seed
## while waiting, so its value depends on exact CPU timing, which is only
## approximated here.
##
## FIELD is a, b, c, d, up, down, left, right, start or coin; frames count
## from 0 at the snapshot. Unknown code addresses are appended to
## data/game/seeds.txt so the next build_code.py run includes them.

## Where the main loop continues after its vblank wait, and the seed's RAM offset.
const WAIT_EXIT := 0xB80
const SEED := 0x430
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
		elif arg.begins_with("--input="):
			var parts := arg.trim_prefix("--input=").split(":")
			var span := parts[1].split("-")
			inputs.append([parts[0], int(span[0]), int(span[1])])
	var machine := MachineLoader.create()
	if machine == null or MachineLoader.load_snapshot(machine, snapshot) != OK:
		push_error("Could not set up the machine")
		quit(1)
		return
	var exit_seeds := {}
	var frame_box := [0]
	if seedlog_path != "":
		var log := FileAccess.open(seedlog_path, FileAccess.READ)
		log.big_endian = true
		while log.get_position() < log.get_length():
			var seed_frame := log.get_32()
			exit_seeds[seed_frame] = log.get_16()
		var first: int = machine.get_meta("snapshot_frame")
		machine.hook_block(WAIT_EXIT, func() -> void:
			var seed: Variant = exit_seeds.get(first + frame_box[0])
			if seed != null:
				machine.ram.encode_u16(SEED, seed))
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
		machine.run_frame()
		if machine.halted:
			break
		done += 1
		if sound_out != null:
			for command: int in machine.sound_log:
				sound_out.store_line("%d %02X" % [frame, command])
		machine.sound_log.clear()
		if frame + 1 in dump_frames:
			_dump(machine, dump_dir.path_join("g%06d.bin" % (frame + 1)), frame + 1)
		if out != null:
			out.store_buffer(MachineLoader._swap_words(machine.ram))
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("ran %d frames in %.0f ms (%.2f ms/frame)" % [done, elapsed, elapsed / maxi(done, 1)])
	if machine.missing_block >= 0:
		print("missing code at %06X" % machine.missing_block)
		var seeds := FileAccess.open(MachineLoader.repo_dir().path_join("data/game/seeds.txt"),
				FileAccess.READ_WRITE)
		if seeds == null:
			seeds = FileAccess.open(MachineLoader.repo_dir().path_join("data/game/seeds.txt"),
					FileAccess.WRITE)
		seeds.seek_end()
		seeds.store_line("%06X" % machine.missing_block)
	quit(0 if not machine.halted else 2)


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
