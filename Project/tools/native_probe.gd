extends SceneTree
## Runs the hand-written game alone, without a window and as fast as it
## goes, and prints the states it passes through and any routine it calls
## that is not there. For finding what is still missing of the game.
##
## Options after `--`:
##   --frames=N    how long to run (default 20000)
##   --coin=N      puts a coin in at that frame and presses start after
##   --drive       holds A from the start of a game, else presses it now and then
##   --idle        presses nothing once a race has begun

const GameFlow := preload("res://game/game_flow.gd")


func _init() -> void:
	var frames := 20000
	var coin := -1
	var drive := false
	var idle := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--coin="):
			coin = int(arg.trim_prefix("--coin="))
		elif arg == "--drive":
			drive = true
		elif arg == "--idle":
			idle = true
	var machine := MachineLoader.create(true, false)
	MachineLoader.load_snapshot(machine, MachineLoader.repo_dir().path_join("data/game/start.snapshot"))
	var scene := GameScene.new(machine)
	scene.replace_hardware_drawing()
	var last := ""
	var missing := {}
	for frame in frames:
		var ram := machine.ram
		var racing := ram.decode_u16(0x426) == 7 and ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF) == 3 \
				and ram.decode_u16(GameFlow.COURSES_STATE & 0xFFFF) == 3
		machine.input_coin = 1 if coin >= 0 and frame >= coin and frame < coin + 4 else 0
		machine.input_start = 1 if coin >= 0 and frame >= coin + 100 and frame % 40 < 4 else 0
		machine.input_p1 = 0
		if coin >= 0 and frame > coin + 150:
			if racing:
				machine.input_p1 = 0 if idle else (0x10 if drive else (0x10 if frame % 3 != 0 else 0))
			elif frame % 16 < 4:
				machine.input_p1 = 0x10
		machine.run_frame()
		var line := "main %d game %d courses %d race %d course %d" % [ram.decode_u16(0x426),
				ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF), ram.decode_u16(GameFlow.COURSES_STATE & 0xFFFF),
				ram.decode_u16(GameFlow.RACE_STATE & 0xFFFF), ram.decode_u16(GameFlow.COURSE & 0xFFFF)]
		if line != last:
			print(frame, ": ", line)
			last = line
		if machine.missing_block >= 0:
			missing[machine.missing_block] = missing.get(machine.missing_block, 0) + 1
			machine.missing_block = -1
	for address: int in missing:
		print("missing $%X, %d times" % [address, missing[address]])
	machine.release()
	quit()
