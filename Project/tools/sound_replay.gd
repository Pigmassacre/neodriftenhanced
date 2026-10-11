extends SceneTree
## Headless check of the sound driver emulation against MAME.
##
##   godot --headless --path Project --script res://tools/sound_replay.gd -- \
##       --ymlog=PATH --out=PATH
##
## Reads the "frame cmd value" lines of a MAME ymlog (Tools/mame/harness.lua),
## feeds those commands to the sound board at the same frames, and writes
## the chip register writes it produces as "frame port register value" for
## Tools/compare_ym.py.


func _init() -> void:
	var log_path := ""
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ymlog="):
			log_path = arg.trim_prefix("--ymlog=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var by_frame := {}
	var first := -1
	var last := 0
	var source := FileAccess.open(log_path, FileAccess.READ)
	while not source.eof_reached():
		var parts := source.get_line().split(" ")
		if parts.size() < 3:
			continue
		var frame := int(parts[0])
		if first < 0:
			first = frame
		last = frame
		if parts[1] == "cmd":
			if not by_frame.has(frame):
				by_frame[frame] = []
			by_frame[frame].append(parts[2].hex_to_int())
	var board := SoundBoard.new()
	board.silent = true
	board.logging = true
	if not board.load_roms(MachineLoader.repo_dir().path_join("neodrift")):
		quit(1)
		return
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	var started := Time.get_ticks_usec()
	for frame in range(first, last + 1):
		for value: int in by_frame.get(frame, []):
			board.command(value)
		board.run_frame()
		for entry: Array in board.write_log:
			out.store_line("%d %s %02X %02X" % [frame, entry[0], entry[1], entry[2]])
		board.write_log.clear()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	print("ran %d frames in %.0f ms (%.2f ms/frame); writes without sound yet: %s"
			% [last - first + 1, elapsed, elapsed / (last - first + 1), board.unvoiced])
	board.free()
	quit()
