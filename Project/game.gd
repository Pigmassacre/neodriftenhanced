extends Node2D
## Runs the game: steps the machine at the hardware frame rate, feeds it the
## keyboard and gamepads and shows its video output.
##
## The game's picture is drawn in game pixels into a viewport of its own
## (video/neogeo_video.gd), which is shown enlarged to the window's height
## in the middle of the window. What is drawn over it (hud/) is drawn at the
## window's resolution.
##
## Keys: arrows steer/select, Z X C V are buttons A B C D, 1 is start, 5 inserts a coin.
## F2 turns the picture-tube look on and off, M the map, F11 full screen.
## Gamepad: stick or pad steers, the four buttons are A B C D (A below, B
## right, C left, D above), the right and left triggers are A and B too,
## Start is start and Back inserts a coin.
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
##   --window-shot              screenshots are of the window, not of the game's picture alone
##   --frames=N                 quit after N frames, printing timing figures
##   --hardware-video           draw what is in video RAM, as the hardware would, instead
##                              of the game's own records (see video/game_scene.gd)
##   --keep-video-ram           draw from the game's records, but leave the original's code
##                              that draws to video RAM running too
##   --width=N                  how wide a picture to draw, instead of as wide as the window
##   --crt                      start with the picture-tube look on
##   --whole-pixels             enlarge the picture a whole number of times only
##   --no-map                   start with the map off
##   --compare-views[=FOLDER]   draw every frame both ways, 320 pixels wide and with the
##                              hardware's timing and limits, and count the frames that
##                              differ; the first of them are saved to FOLDER

## The hardware refreshes slightly slower than 60 Hz.
const FRAME_TIME := 1.0 / 59.185606
## The widest picture drawn: what the game keeps of the course around the
## camera is not made for more (about 2.85 to 1).
const WIDEST_VIEW := 640
const P1_KEYS := {
	KEY_UP: 1, KEY_DOWN: 2, KEY_LEFT: 4, KEY_RIGHT: 8, KEY_Z: 16, KEY_X: 32, KEY_C: 64, KEY_V: 128,
}
const P1_BITS := {"up": 1, "down": 2, "left": 4, "right": 8, "a": 16, "b": 32, "c": 64, "d": 128}
const P1_PAD_BUTTONS := {
	JOY_BUTTON_DPAD_UP: 1, JOY_BUTTON_DPAD_DOWN: 2, JOY_BUTTON_DPAD_LEFT: 4, JOY_BUTTON_DPAD_RIGHT: 8,
	JOY_BUTTON_A: 16, JOY_BUTTON_B: 32, JOY_BUTTON_X: 64, JOY_BUTTON_Y: 128,
}
## How far a stick or trigger must be moved to count.
const STICK_MOVED := 0.5
const TRIGGER_PRESSED := 0.3

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
var _forced_width := 0
var _comparing := false
var _compare_folder := ""
var _hardware_view: NeoGeoVideo
var _views: Array[SubViewport] = []
var _compared := 0
var _differing: Array[int] = []
var _over_limit := 0
## The viewport the game's picture is drawn in, what shows it in the
## window, and how many screen pixels a game pixel is.
var _screen: SubViewport
var _picture: TextureRect
var _pixel := 1.0
var _whole_pixels := false
var _enlarge_material: ShaderMaterial
var _crt_material: ShaderMaterial
var _crt := false
var _window_shots := false
var _map: Minimap

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
	var hand_written := true
	var native_video := true
	var keep_video_ram := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seedlog="):
			seedlog = arg.trim_prefix("--seedlog=")
		elif arg == "--translated":
			hand_written = false
		elif arg == "--no-sound":
			use_sound = false
		elif arg.begins_with("--topup="):
			for value in arg.trim_prefix("--topup=").split(":"):
				_topup.append(int(value))
		elif arg.begins_with("--frames="):
			_quit_after = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--record-audio="):
			_record_path = arg.trim_prefix("--record-audio=")
		elif arg == "--hardware-video":
			native_video = false
		elif arg == "--keep-video-ram":
			keep_video_ram = true
		elif arg.begins_with("--width="):
			_forced_width = int(arg.trim_prefix("--width="))
		elif arg == "--crt":
			_crt = true
		elif arg == "--whole-pixels":
			_whole_pixels = true
		elif arg == "--window-shot":
			_window_shots = true
		elif arg.begins_with("--compare-views"):
			_comparing = true
			_compare_folder = arg.trim_prefix("--compare-views").trim_prefix("=")
	if not use_sound or not sound.load_roms(MachineLoader.repo_dir().path_join("neodrift")):
		sound = null
	if sound != null:
		sound.capturing = _record_path != ""
		sound.muted = not shot_frames.is_empty()
	machine = MachineLoader.create(hand_written)
	if machine == null or MachineLoader.load_snapshot(machine, snapshot) != OK:
		push_error("Could not start: need the generated program and %s" % snapshot)
		get_tree().quit(1)
		return
	if seedlog != "":
		_apply_seed_log(seedlog)
	video.machine = machine
	if native_video or _comparing:
		video.scene = GameScene.new(machine)
		video.scene.translucency = not _comparing
		machine.steady_shadows = hand_written and not _comparing
		if not _comparing and not keep_video_ram:
			video.scene.replace_hardware_drawing()
			if hand_written:
				Decomp.make_room(machine)
	RenderingServer.set_default_clear_color(Color.BLACK)
	if _comparing:
		_set_up_comparison()
		video.refresh()
	else:
		_set_up_screen()
		_map.wanted = not OS.get_cmdline_user_args().has("--no-map")
		_map.fades = shot_frames.is_empty()
		get_viewport().size_changed.connect(_fit_view)
		_fit_view()
		_refresh()


## Puts the game's picture in a viewport of its own, shown in the window
## by `_picture`, with what is drawn over it.
func _set_up_screen() -> void:
	_screen = SubViewport.new()
	_screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_screen.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_screen.snap_2d_transforms_to_pixel = true
	remove_child(video)
	_screen.add_child(video)
	add_child(_screen)
	_picture = TextureRect.new()
	_picture.texture = _screen.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.clip_contents = true
	add_child(_picture)
	_enlarge_material = ShaderMaterial.new()
	_enlarge_material.shader = preload("res://video/enlarge.gdshader")
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = preload("res://video/crt.gdshader")
	_map = Minimap.new()
	_map.machine = machine
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.add_child(_map)


## Makes the picture as high as the window, or as wide when the window is
## narrower than the hardware's picture, as wide as the window then shows,
## and puts it in the middle.
func _fit_view() -> void:
	var window := get_viewport().get_visible_rect().size
	_pixel = minf(window.y / NeoGeoVideo.SCREEN.y, window.x / NeoGeoVideo.SCREEN.x)
	if _whole_pixels:
		_pixel = maxf(floorf(_pixel), 1.0)
	var width := _forced_width if _forced_width > 0 else int(window.x / _pixel + 0.001)
	video.view_width = mini(width, WIDEST_VIEW) & ~1
	_screen.size = Vector2i(video.view_width, int(NeoGeoVideo.SCREEN.y))
	_picture.size = (Vector2(_screen.size) * _pixel).round()
	_picture.position = ((window - _picture.size) / 2).round()
	_map.pixel = _pixel
	_map.size = _picture.size
	if video.scene != null:
		machine.view_margin = video.margin()
	_show_crt()


func _show_crt() -> void:
	# below three screen pixels to a line there is no room for the look
	var on := _crt and _pixel >= 3
	_picture.material = _crt_material if on else _enlarge_material
	_picture.material.set_shader_parameter("picture_size", Vector2(_screen.size))
	_enlarge_material.set_shader_parameter("scale", _pixel)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or _picture == null:
		return
	match key.physical_keycode:
		KEY_F2:
			_crt = not _crt
			_show_crt()
		KEY_M:
			_map.wanted = not _map.wanted
		KEY_F11:
			var window := get_window()
			var full := window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
			window.mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN


## Puts the picture drawn from the game's records and the one drawn from
## video RAM in a viewport each, shown side by side.
func _set_up_comparison() -> void:
	video.scene.hardware_timing = true
	video.scene.hardware_limits = true
	_hardware_view = NeoGeoVideo.new()
	_hardware_view.machine = machine
	remove_child(video)
	for view: NeoGeoVideo in [video, _hardware_view]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(NeoGeoVideo.SCREEN)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.add_child(view)
		add_child(viewport)
		var shown := Sprite2D.new()
		shown.texture = viewport.get_texture()
		shown.centered = false
		shown.position.x = _views.size() * NeoGeoVideo.SCREEN.x
		add_child(shown)
		_views.append(viewport)
	_hardware_view.refresh()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _compare_views() -> void:
	if not video.scene.in_use():
		return
	_compared += 1
	var ours := _views[0].get_texture().get_image()
	var theirs := _views[1].get_texture().get_image()
	if ours.get_data() == theirs.get_data():
		return
	if _hardware_view.over_line_limit():
		# the hardware left sprites out on a line; a scene has no such limit
		_over_limit += 1
		return
	_differing.append(frame)
	if _compare_folder != "" and _differing.size() <= 40:
		ours.save_png(_compare_folder.path_join("%d_scene.png" % frame))
		theirs.save_png(_compare_folder.path_join("%d_video_ram.png" % frame))


func _report_comparison() -> void:
	print("compared %d frames: %d differ, %d more where the hardware ran out of sprites on a line"
			% [_compared, _differing.size(), _over_limit])
	if not _differing.is_empty():
		print("differing frames: ", ", ".join(_differing.slice(0, 60).map(func(f: int) -> String: return str(f))))


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
	if _comparing:
		_step()
		set_process(false)
		video.refresh()
		_hardware_view.refresh()
		await RenderingServer.frame_post_draw
		_compare_views()
		if frame >= _quit_after or machine.halted:
			_report_comparison()
			get_tree().quit()
		else:
			set_process(true)
		return
	if not shot_frames.is_empty():
		# deterministic stepping for automated screenshots
		_step()
		if frame == shot_frames[0]:
			shot_frames.pop_front()
			var done := shot_frames.is_empty()
			set_process(false)
			_refresh()
			await RenderingServer.frame_post_draw
			var path := shot_path % frame if "%d" in shot_path else shot_path
			(get_viewport() if _window_shots else _screen).get_texture().get_image().save_png(path)
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
		_refresh()


func _refresh() -> void:
	video.refresh()
	_map.refresh(video.hud_shown)


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
	for pad in Input.get_connected_joypads():
		for button: int in P1_PAD_BUTTONS:
			if Input.is_joy_button_pressed(pad, button):
				p1 |= P1_PAD_BUTTONS[button]
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if stick.y < -STICK_MOVED:
			p1 |= 1
		elif stick.y > STICK_MOVED:
			p1 |= 2
		if stick.x < -STICK_MOVED:
			p1 |= 4
		elif stick.x > STICK_MOVED:
			p1 |= 8
		if Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_PRESSED:
			p1 |= 16
		if Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_PRESSED:
			p1 |= 32
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_START):
			start |= 1
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_BACK):
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
	if frame == _quit_after and not _comparing:
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
	if machine != null:
		machine.release()
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
