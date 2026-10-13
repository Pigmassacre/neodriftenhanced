extends Node2D
## Runs the game: steps the machine at the hardware frame rate, feeds it the
## keyboard and gamepads and shows its video output.
##
## The game's picture is drawn in game pixels into a viewport of its own
## (video/neogeo_video.gd), which is shown enlarged to the window's height
## in the middle of the window. What is drawn over it (hud/) is drawn at the
## window's resolution.
##
## It starts with the main menu (menu/menu.gd) over the original's attract
## mode. A game chosen there is started by restarting the machine and
## working its coin slot and buttons until the game is under way; the game
## over, or left from the menu of a paused game, the machine is restarted
## again for the menu. Any option of the "automated" kind below leaves the
## menus out and the machine to its inputs, as on the original hardware.
##
## The keys and buttons are the player's to choose (settings.gd). At first:
## arrows steer/select, Z X C V are buttons A B C D, 1 is start, 5 inserts a
## coin and Esc pauses. On a gamepad, stick or pad steers, the four buttons
## are A B C D (A below, B right, C left, D above), the right and left
## triggers are A and B too, Start is start (and pauses a race) and Back
## inserts a coin. F2 turns the picture-tube look on and off, M the map,
## F11 full screen.
##
## Options after `--` (automated: --snapshot, --input, --seedlog, --shot-frame,
## --frames, --compare-views and --no-menu):
##   --no-menu                  no menus, and none of the player's stored options
##   --menu=PAGE                the menu open at that page even when automated
##   --arcade, --stage=N        start a game as the menu would: the whole game, or
##                              stage N alone (0 is the practice stage)
##   --settings=PATH            keep the player's options in that file instead
##   --press=TICK:KEY[,...]     press a key (by its name, as "Down" or "Enter") at that
##                              count of drawn frames, to try the menus out
##   --shot-tick=N              with --shot, one screenshot of the window at that count
##                              of drawn frames, then quit
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
const P1_BITS := {"up": 1, "down": 2, "left": 4, "right": 8, "a": 16, "b": 32, "c": 64, "d": 128}

const GameFlow := preload("res://game/game_flow.gd")
## What the original's main loop is at ($100426): its attract mode, the
## title with a credit in, "how to play", the entry of a name, and the game.
const MAIN_ATTRACT: Array[int] = [0, 1]
const MAIN_TITLE: Array[int] = [12, 13]
const MAIN_HOW_TO_PLAY: Array[int] = [2, 3]
const MAIN_NAME_ENTRY: Array[int] = [4, 18, 19]
const MAIN_GAME: Array[int] = [6, 7]
## Starting a game: a button is pressed for PRESS_FRAMES of every
## PRESS_EVERY, a coin put in every COIN_EVERY, and it is given up after
## START_FRAMES.
const PRESS_FRAMES := 3
const PRESS_EVERY := 8
const COIN_FRAMES := 6
const COIN_EVERY := 40
const START_FRAMES := 900

## What the player is at: the game, a menu over the attract mode, a game
## being got ready behind a black screen, or a menu over a stopped game.
enum {PLAYING, IN_MENU, STARTING, PAUSED}

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

var _settings := Settings.new()
## Null when the run is automated.
var _menu: Menu
var _state := PLAYING
var _snapshot := ""
var _hand_written := true
var _native_video := true
var _keep_video_ram := false
## The stage of a game of one stage alone, or -1.
var _stage := -1
var _start_frames := 0
## Frames a coin is still being put in for, and whether the game was
## asking to be continued the frame before.
var _coin_frames := 0
var _continuing := false
## Drawn frames so far, the keys to press by drawn frame, the key held,
## and the drawn frame to take a screenshot at.
var _tick := 0
var _presses := {}
var _held: Key = KEY_NONE
var _shot_tick := 0

@onready var video: NeoGeoVideo = $Video
@onready var sound: SoundBoard = $Sound


func _ready() -> void:
	_snapshot = MachineLoader.repo_dir().path_join("data/game/start.snapshot")
	var automated := false
	var menu_page := ""
	var start_arcade := false
	var seedlog := ""
	var use_sound := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			_snapshot = arg.trim_prefix("--snapshot=")
			automated = true
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-frame="):
			for value in arg.trim_prefix("--shot-frame=").split(","):
				shot_frames.append(int(value))
			automated = true
		elif arg.begins_with("--input="):
			var parts := arg.trim_prefix("--input=").split(":")
			var span := parts[1].split("-")
			scripted.append([parts[0], int(span[0]), int(span[1])])
			automated = true
		elif arg.begins_with("--seedlog="):
			seedlog = arg.trim_prefix("--seedlog=")
			automated = true
		elif arg == "--translated":
			_hand_written = false
		elif arg == "--no-sound":
			use_sound = false
		elif arg.begins_with("--topup="):
			for value in arg.trim_prefix("--topup=").split(":"):
				_topup.append(int(value))
		elif arg.begins_with("--frames="):
			_quit_after = int(arg.trim_prefix("--frames="))
			automated = true
		elif arg.begins_with("--record-audio="):
			_record_path = arg.trim_prefix("--record-audio=")
		elif arg == "--hardware-video":
			_native_video = false
		elif arg == "--keep-video-ram":
			_keep_video_ram = true
		elif arg.begins_with("--width="):
			_forced_width = int(arg.trim_prefix("--width="))
		elif arg == "--window-shot":
			_window_shots = true
		elif arg.begins_with("--compare-views"):
			_comparing = true
			_compare_folder = arg.trim_prefix("--compare-views").trim_prefix("=")
			automated = true
		elif arg == "--no-menu":
			automated = true
		elif arg.begins_with("--menu="):
			menu_page = arg.trim_prefix("--menu=")
		elif arg.begins_with("--settings="):
			_settings.path = arg.trim_prefix("--settings=")
		elif arg.begins_with("--press="):
			for press in arg.trim_prefix("--press=").split(","):
				_presses[int(press.get_slice(":", 0))] = OS.find_keycode_from_string(press.get_slice(":", 1))
		elif arg.begins_with("--shot-tick="):
			_shot_tick = int(arg.trim_prefix("--shot-tick="))
		elif arg == "--arcade":
			start_arcade = true
		elif arg.begins_with("--stage="):
			_stage = int(arg.trim_prefix("--stage="))
	var with_menu := not _comparing and (not automated or menu_page != "" or start_arcade or _stage >= 0)
	if not automated:
		_settings.load_file()
	var args := OS.get_cmdline_user_args()
	if args.has("--crt"):
		_settings.crt = true
	if args.has("--whole-pixels"):
		_settings.whole_pixels = true
	if args.has("--no-map"):
		_settings.map = false
	_settings.apply_controls()
	if not use_sound or not sound.load_roms(MachineLoader.repo_dir().path_join("neodrift")):
		sound = null
	if sound != null:
		sound.capturing = _record_path != ""
		sound.muted = not shot_frames.is_empty()
	if not _start_machine():
		push_error("Could not start: need the generated program and %s" % _snapshot)
		get_tree().quit(1)
		return
	if seedlog != "":
		_apply_seed_log(seedlog)
	RenderingServer.set_default_clear_color(Color.BLACK)
	if _comparing:
		_set_up_comparison()
		video.refresh()
		return
	_set_up_screen()
	_map.fades = shot_frames.is_empty()
	get_viewport().size_changed.connect(_fit_view)
	if with_menu:
		_set_up_menu()
	_apply_settings("sound")
	_apply_settings("game")
	if not automated and not OS.get_cmdline_args().has("--resolution"):
		_apply_window()
	_apply_settings("picture")
	if _menu != null:
		if start_arcade or _stage >= 0:
			_start_game(_stage)
		else:
			_state = IN_MENU
			_menu.open(menu_page if menu_page != "" else "main")
	_refresh()


## Makes the machine anew from the snapshot it starts from, in place of the
## one there was.
func _start_machine() -> bool:
	_finish_sound_task()
	if machine != null:
		machine.release()
	machine = MachineLoader.create(_hand_written)
	if machine == null or MachineLoader.load_snapshot(machine, _snapshot) != OK:
		machine = null
		return false
	machine.first_course = maxi(_stage, 0)
	video.machine = machine
	video.scene = null
	if _native_video or _comparing:
		video.scene = GameScene.new(machine)
		if not _comparing and not _keep_video_ram:
			video.scene.replace_hardware_drawing()
			if _hand_written:
				Decomp.make_room(machine)
	if _map != null:
		_map.machine = machine
		_apply_settings("picture")
	return true


# --- the menus and the player's options --------------------------------------

func _set_up_menu() -> void:
	_menu = Menu.new()
	_menu.settings = _settings
	add_child(_menu)
	_menu.changed.connect(_apply_settings)
	_menu.arcade_chosen.connect(_start_game.bind(-1))
	_menu.stage_chosen.connect(_start_game)
	_menu.resumed.connect(_resume)
	_menu.main_menu_chosen.connect(_to_main_menu.bind("main"))
	_menu.quit_chosen.connect(_quit)


## Makes what the player has chosen in a section of the options so.
func _apply_settings(section: String) -> void:
	match section:
		"picture":
			if _menu != null and _menu.is_open():
				_apply_window()
			_whole_pixels = _settings.whole_pixels
			_crt = _settings.crt
			if video.scene != null and not _comparing:
				video.scene.translucency = _settings.translucency
				# the shadows are put down every frame only to be drawn see-through
				machine.steady_shadows = _hand_written and _settings.translucency
			_fit_view()
		"sound":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_settings.volume, 0.0001)))
			AudioServer.set_bus_mute(0, _settings.volume <= 0.0)
			if sound != null:
				sound.set_volumes(_settings.music, _settings.effects)
		"game":
			_map.wanted = _settings.map


func _apply_window() -> void:
	var window := get_window()
	var full := window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	if full != _settings.full_screen:
		window.mode = Window.MODE_FULLSCREEN if _settings.full_screen else Window.MODE_WINDOWED
	if not _settings.full_screen and window.size != _settings.window_size:
		window.size = _settings.window_size
		window.move_to_center()
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if _settings.vsync else DisplayServer.VSYNC_DISABLED)


## Starts a game from the beginning: the whole game, or `stage` alone.
func _start_game(stage: int) -> void:
	_stage = stage
	_start_machine()
	if sound != null:
		sound.reset_driver()
		sound.muted = true
	_state = STARTING
	_start_frames = 0
	_coin_frames = 0
	_continuing = false
	_menu.cover("" if stage < 0 else "Practice stage" if stage == 0 else "Stage %d" % stage)


## Back to the main menu, over the attract mode from its beginning.
func _to_main_menu(page: String) -> void:
	_stage = -1
	_start_machine()
	if sound != null:
		sound.reset_driver()
		sound.muted = not shot_frames.is_empty()
	_state = IN_MENU
	_menu.open("main")
	if page != "main":
		_menu.go(page)


func _pause() -> void:
	_state = PAUSED
	_menu.open("pause")


func _resume() -> void:
	_state = PLAYING
	_time = 0.0
	_menu.close()


func _quit() -> void:
	_save_recording()
	get_tree().quit()


## What the coin slot and the buttons are to be while a game is got ready,
## as [player 1, start, coin]: a coin in, start pressed at the title, and
## for a single stage A pressed through "how to play" and the name too.
func _starting_inputs() -> Array[int]:
	var main: int = machine.ram.decode_u16(GameFlow.MAIN_STATE & 0xFFFF)
	var pressed := _start_frames % PRESS_EVERY < PRESS_FRAMES
	_start_frames += 1
	var done: bool = main in MAIN_GAME
	if _stage < 0 and (main in MAIN_HOW_TO_PLAY or main in MAIN_NAME_ENTRY):
		done = true
	if done or _start_frames > START_FRAMES:
		_state = PLAYING
		_menu.close()
		if sound != null:
			sound.muted = not shot_frames.is_empty()
		return [0, 0, 0]
	if main in MAIN_TITLE:
		return [0, int(pressed), 0]
	if main in MAIN_HOW_TO_PLAY or main in MAIN_NAME_ENTRY:
		return [P1_BITS["a"] if pressed else 0, 0, 0]
	return [0, 0, int(_start_frames % COIN_EVERY < COIN_FRAMES)]


## After a frame of a game started from the menu: sees to the credit of a
## game that asks to be continued, and to the menu when the game is over
## (for a single stage, when the stage is).
func _follow_game() -> void:
	var ram: PackedByteArray = machine.ram
	var main := ram.decode_u16(GameFlow.MAIN_STATE & 0xFFFF)
	if main in MAIN_ATTRACT or main in MAIN_TITLE:
		_to_main_menu("main")
		return
	if not main in MAIN_GAME or ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF) < GameFlow.GAME_COURSES:
		return
	var courses := ram.decode_u16(GameFlow.COURSES_STATE & 0xFFFF)
	var over := ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF) > GameFlow.GAME_COURSES
	if _stage >= 0:
		if over or courses >= GameFlow.COURSES_SET_UP_CONTINUE \
				or ram.decode_u16(GameFlow.COURSE & 0xFFFF) != _stage:
			_to_main_menu("freeplay")
		return
	var continuing := not over and courses == GameFlow.COURSES_CONTINUE
	if continuing and not _continuing and _settings.free_continues:
		_coin_frames = COIN_FRAMES
	_continuing = continuing


## Is the car being driven (and not a screen before or after a race shown)?
func _driving() -> bool:
	var ram: PackedByteArray = machine.ram
	return ram.decode_u16(GameFlow.MAIN_STATE & 0xFFFF) in MAIN_GAME \
			and ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF) == GameFlow.GAME_COURSES \
			and ram.decode_u16(GameFlow.COURSES_STATE & 0xFFFF) == GameFlow.COURSES_RACE \
			and ram.decode_u16(GameFlow.RACE_STATE & 0xFFFF) == GameFlow.RACE_DRIVING


func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or _state != PLAYING or not event.is_action_pressed(Settings.ACTION_PREFIX + "pause"):
		return
	# what is also the game's start button pauses a race only
	if event.is_action(Settings.ACTION_PREFIX + "start") and not _driving():
		return
	_pause()
	get_viewport().set_input_as_handled()


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
	move_child(_picture, 0)
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
	if _picture == null:
		return
	var window := get_viewport().get_visible_rect().size
	_pixel = minf(window.y / NeoGeoVideo.SCREEN.y, window.x / NeoGeoVideo.SCREEN.x)
	if _whole_pixels:
		_pixel = maxf(floorf(_pixel), 1.0)
	var width := int(window.x / _pixel + 0.001)
	if _forced_width > 0:
		width = _forced_width
	elif not _settings.wide:
		width = int(NeoGeoVideo.SCREEN.x)
	video.view_width = mini(width, WIDEST_VIEW) & ~1
	_screen.size = Vector2i(video.view_width, int(NeoGeoVideo.SCREEN.y))
	_picture.size = (Vector2(_screen.size) * _pixel).round()
	_picture.position = ((window - _picture.size) / 2).round()
	_map.pixel = _pixel
	_map.size = _picture.size
	if _menu != null:
		_menu.position = Vector2.ZERO
		_menu.size = window
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
			_settings.crt = not _settings.crt
			_apply_settings("picture")
		KEY_M:
			_settings.map = not _settings.map
			_apply_settings("game")
		KEY_F11:
			_settings.full_screen = not _settings.full_screen
			_apply_window()
		_:
			return
	if _menu != null:
		_settings.save_file()


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
	_tick += 1
	if _held != KEY_NONE:
		_press(_held, false)
		_held = KEY_NONE
	if _presses.has(_tick):
		_held = _presses[_tick]
		_press(_held, true)
	if _tick == _shot_tick:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		_quit()
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
	if _state == PAUSED:
		return
	_time = minf(_time + delta, FRAME_TIME * 3)
	var stepped := false
	while _time >= FRAME_TIME and not machine.halted:
		_time -= FRAME_TIME
		_step()
		stepped = true
	if stepped:
		_refresh()


func _press(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _refresh() -> void:
	video.refresh()
	_map.refresh(video.hud_shown)


func _step() -> void:
	var p1 := 0
	var start := 0
	var coin := 0
	if _state == STARTING:
		var inputs := _starting_inputs()
		p1 = inputs[0]
		start = inputs[1]
		coin = inputs[2]
	elif _state == PLAYING:
		for button: String in P1_BITS:
			if Input.is_action_pressed(Settings.ACTION_PREFIX + button):
				p1 |= P1_BITS[button]
		start = int(Input.is_action_pressed(Settings.ACTION_PREFIX + "start"))
		coin = int(Input.is_action_pressed(Settings.ACTION_PREFIX + "coin"))
		if _coin_frames > 0:
			_coin_frames -= 1
			coin = 1
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
	elif _menu != null and _state == PLAYING:
		_follow_game()
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
