extends SceneTree
## Headless check of the sound driver emulation against MAME.
##
##   godot --headless --path Project --script res://tools/sound_replay.gd -- \
##       --ymlog=PATH [--out=PATH] [--wav=PATH]
##
## Reads the "frame cmd value seconds" lines of a MAME ymlog
## (Tools/mame/harness.lua) and feeds those commands to the sound board at
## the same times, counted from power-on. --out
## writes the chip register writes it produces as "frame port register value
## seconds" for Tools/compare_ym.py; --wav writes the sound it produces, at the chip's
## sample rate, for Tools/compare_audio.py.


func _init() -> void:
	var log_path := ""
	var out_path := ""
	var wav_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ymlog="):
			log_path = arg.trim_prefix("--ymlog=")
		elif arg.begins_with("--wav="):
			wav_path = arg.trim_prefix("--wav=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	# [sound CPU cycle, value] in order
	var commands: Array = []
	var last := 0.0
	var source := FileAccess.open(log_path, FileAccess.READ)
	while not source.eof_reached():
		var parts := source.get_line().split(" ")
		if parts.size() < 4:
			continue
		last = float(parts[parts.size() - 1])
		if parts[1] == "cmd":
			commands.append([int(last * SoundBoard.Z80_CLOCK), parts[2].hex_to_int()])
	var frames := int(last * SoundBoard.FRAME_RATE) + 1
	var board := SoundBoard.new()
	board.silent = true
	board.logging = true
	board.render_sound = wav_path != ""
	board.capturing = true
	if not board.load_roms(MachineLoader.repo_dir().path_join("neodrift")):
		quit(1)
		return
	var out := FileAccess.open(out_path, FileAccess.WRITE) if out_path != "" else null
	var started := Time.get_ticks_usec()
	for frame in frames:
		var frame_end := board.cpu.cycles + SoundBoard.CYCLES_PER_FRAME
		while not commands.is_empty() and commands[0][0] < frame_end:
			var entry: Array = commands.pop_front()
			board.command(entry[1], entry[0] - board.cpu.cycles)
		board.run_frame()
		for entry: Array in board.write_log:
			if out != null:
				out.store_line("%d %s %02X %02X %.9f" % [frame, entry[0], entry[1], entry[2],
						entry[3] / SoundBoard.Z80_CLOCK])
		board.write_log.clear()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("ran %d frames in %.0f ms (%.2f ms/frame)" % [frames, elapsed, elapsed / frames])
	if wav_path != "":
		SoundBoard.save_wav(board.captured, wav_path)
	board.free()
	quit()
