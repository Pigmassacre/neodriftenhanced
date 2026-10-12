extends Node2D
## Runs the game: steps the machine at the hardware frame rate, feeds it the
## keyboard and shows its video output.
##
## Keys: arrows steer/select, Z X C V are buttons A B C D, 1 is start, 5 inserts a coin.
##
## Options after `--`:
##   --snapshot=PATH            machine state to start from (default data/game/start.snapshot)
##   --input=FIELD:FIRST-LAST   scripted input for frames FIRST..LAST (as tools/replay.gd)
##   --topup=OFFSET:BELOW:VALUE keeps a work RAM word topped up (as tools/replay.gd)
##   --seedlog=PATH             random seeds from a MAME run (as tools/replay.gd), so
##                              screenshots can be compared pixel for pixel
##   --no-sound                 run without the sound board
##   --record-audio=PATH        write the sound produced to a WAV file (saved on quit)
##   --shot=PATH --shot-frame=N[,N...]  save a screenshot after each of those frame
##                              counts (PATH may contain %d) and quit after the last;
##                              runs as fast as it can, with the sound muted
##   --frames=N                 quit after N frames, printing timing figures

## The hardware refreshes slightly slower than 60 Hz.
const FRAME_TIME := 1.0 / 59.185606
const P1_KEYS := {
	KEY_UP: 1, KEY_DOWN: 2, KEY_LEFT: 4, KEY_RIGHT: 8, KEY_Z: 16, KEY_X: 32, KEY_C: 64, KEY_V: 128,
}
const P1_BITS := {"up": 1, "down": 2, "left": 4, "right": 8, "a": 16, "b": 32, "c": 64, "d": 128}

var machine: RefCounted
var frame := 0
var scripted: Array = []
var shot_path := ""
var shot_frames: Array[int] = []
var _time := 0.0
var _sound_task := -1
var _record_path := ""
var _quit_after := 0
var _sound_ms := 0.0
var _sound_ms_peak := 0.0
var _machine_ms := 0.0
var _machine_ms_peak := 0.0

var _topup := PackedInt32Array()

@onready var video: NeoGeoVideo = $Video
@onready var sound: SoundBoard = $Sound


func _ready() -> void:
	var snapshot := MachineLoader.repo_dir().path_join("data/game/start.snapshot")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			snapshot = arg.trim_prefix("--snapshot=")
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-frame="):
			for value in arg.trim_prefix("--shot-frame=").split(","):
				shot_frames.append(int(value))
		elif arg.begins_with("--input="):
			var parts := arg.trim_prefix("--input=").split(":")
			var span := parts[1].split("-")
			scripted.append([parts[0], int(span[0]), int(span[1])])
	var seedlog := ""
	var use_sound := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seedlog="):
			seedlog = arg.trim_prefix("--seedlog=")
		elif arg == "--no-sound":
			use_sound = false
		elif arg.begins_with("--topup="):
			for value in arg.trim_prefix("--topup=").split(":"):
				_topup.append(int(value))
		elif arg.begins_with("--frames="):
			_quit_after = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--record-audio="):
			_record_path = arg.trim_prefix("--record-audio=")
	if not use_sound or not sound.load_roms(MachineLoader.repo_dir().path_join("neodrift")):
		sound = null
	if sound != null:
		sound.capturing = _record_path != ""
		sound.muted = not shot_frames.is_empty()
	machine = MachineLoader.create()
	if machine == null or MachineLoader.load_snapshot(machine, snapshot) != OK:
		push_error("Could not start: need the generated program and %s" % snapshot)
		get_tree().quit(1)
		return
	if seedlog != "":
		_apply_seed_log(seedlog)
	video.machine = machine
	video.refresh()


func _apply_seed_log(path: String) -> void:
	var seeds := MachineLoader.read_seed_log(path)
	var first: int = machine.get_meta("snapshot_frame")
	# 0xB80 is where the main loop continues after its vblank wait; 0x430 holds the seed.
	machine.hook_block(0xB80, func() -> void:
		var value: Variant = seeds.get(first + frame)
		if value != null:
			machine.ram.encode_u16(0x430, value))


func _process(delta: float) -> void:
	if machine == null or machine.halted:
		return
	if not shot_frames.is_empty():
		# deterministic stepping for automated screenshots
		_step()
		if frame == shot_frames[0]:
			shot_frames.pop_front()
			var done := shot_frames.is_empty()
			set_process(false)
			video.refresh()
			await RenderingServer.frame_post_draw
			var path := shot_path % frame if "%d" in shot_path else shot_path
			get_viewport().get_texture().get_image().save_png(path)
			if done:
				_save_recording()
				get_tree().quit()
			else:
				set_process(true)
		return
	_time = minf(_time + delta, FRAME_TIME * 3)
	var stepped := false
	while _time >= FRAME_TIME and not machine.halted:
		_time -= FRAME_TIME
		_step()
		stepped = true
	if stepped:
		video.refresh()


func _step() -> void:
	var p1 := 0
	var start := 0
	var coin := 0
	for key: int in P1_KEYS:
		if Input.is_physical_key_pressed(key):
			p1 |= P1_KEYS[key]
	if Input.is_physical_key_pressed(KEY_1):
		start |= 1
	if Input.is_physical_key_pressed(KEY_5):
		coin |= 1
	for entry in scripted:
		if frame >= entry[1] and frame <= entry[2]:
			if entry[0] == "start":
				start |= 1
			elif entry[0] == "coin":
				coin |= 1
			else:
				p1 |= P1_BITS[entry[0]]
	if sound != null:
		# The sound CPU ran alongside the previous frame on a worker thread.
		_finish_sound_task()
		sound.play_rendered()
		machine.sound_reply = sound.reply
		_sound_ms += sound.frame_ms
		_sound_ms_peak = maxf(_sound_ms_peak, sound.frame_ms)
	machine.input_p1 = p1
	machine.input_start = start
	machine.input_coin = coin
	if not _topup.is_empty():
		machine.top_up(_topup[0], _topup[1], _topup[2])
	var started := Time.get_ticks_usec()
	machine.run_frame()
	var took := (Time.get_ticks_usec() - started) / 1000.0
	_machine_ms += took
	_machine_ms_peak = maxf(_machine_ms_peak, took)
	if sound != null:
		# the sound CPU's clock is a third of the main CPU's
		for index in machine.sound_log.size():
			sound.command(machine.sound_log[index], machine.sound_log_times[index] / 3)
		_sound_task = WorkerThreadPool.add_task(sound.run_frame)
	machine.sound_log.clear()
	machine.sound_log_times.clear()
	frame += 1
	if machine.halted:
		_report_halt()
	if frame == _quit_after:
		print("%d frames; game %.2f ms a frame (peak %.2f), sound %.2f ms (peak %.2f)"
				% [frame, _machine_ms / frame, _machine_ms_peak, _sound_ms / frame, _sound_ms_peak])
		if sound != null:
			print("audio output ran dry %d times, %d frames of sound dropped" % [sound.underruns, sound.dropped])
		_save_recording()
		get_tree().quit()


func _report_halt() -> void:
	if machine.missing_block < 0:
		return
	# Code the recompiler has not seen yet: record it for the next build.
	push_error("Game code at %06X has not been translated yet. Re-run Tools/recomp/build_code.py."
			% machine.missing_block)
	var path := MachineLoader.repo_dir().path_join("data/game/seeds.txt")
	var seeds := FileAccess.open(path, FileAccess.READ_WRITE)
	if seeds == null:
		seeds = FileAccess.open(path, FileAccess.WRITE)
	seeds.seek_end()
	seeds.store_line("%06X" % machine.missing_block)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_recording()


func _exit_tree() -> void:
	_finish_sound_task()


## The sound board must not be freed while a worker thread is running it.
func _finish_sound_task() -> void:
	if _sound_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_sound_task)
		_sound_task = -1


func _save_recording() -> void:
	if sound == null or _record_path == "":
		return
	_finish_sound_task()
	SoundBoard.save_wav(sound.captured, _record_path)
	_record_path = ""
