class_name ButtonMasher
extends Node
## Presses buttons at random from the moment the game starts, as a cat on
## the keyboard or a child with the pad would, to find what crashes the
## game, prints errors or leaves it stuck:
## `-- --masher <seed> [--seconds N] [--close-at F] [--no-quit]`. --close-at
## closes the window at frame F, as a player does, instead of quitting when
## time is up; --no-quit presses nothing but up and down while Quit to
## desktop has the focus, and clicks nowhere on it, so the game is still
## there to close.
##
## It plays as a player, with the files of its user data directory (so run
## it with one of its own), and sends its input through
## Input.parse_input_event as the keyboard, mouse and pad do: the events
## bound to the game's controls and the menus' actions, the keys the game
## and the course editor read for themselves (F2, F3, M, F11, the editor's
## tools, Ctrl+Z, Ctrl+S, Delete), mouse moves, clicks and drags anywhere or
## on a control that can be pressed, and the mouse wheel. The menus' Quit to
## desktop is never aimed at, but a press can still reach it.
##
## Now and then something happens around the presses, as it does on a
## player's machine: the window loses focus and gets it back, the window
## changes shape, the pad is unplugged and another plugged in with a new
## device number, or a frame takes long, a hitch of up to half a second.
##
## While it plays it checks that the game keeps going: a machine that
## stops, a game in play that stands still, a game paused with no menu
## open, or a menu that keyboard or pad input has left with nothing focused
## (a dead end for a player without a mouse). It prints "MASHER PASS: ..."
## with what it reached once its time is up, "MASHER FAIL: ..." when the
## game got stuck, and "MASHER QUIT: ..." when its presses quit the game.

static var is_active: bool = OS.get_cmdline_user_args().has("--masher")

## How long a game in play may stand still, in frames.
const _MAX_STILL_FRAMES := 600
## How long the game may be paused with no menu, or get a game under way, in frames.
const _MAX_STUCK_FRAMES := 3600
## How long a menu may go without a focused row after keyboard or pad input, in frames.
const _MAX_UNFOCUSED_FRAMES := 120
## Keys the game and the course editor read for themselves rather than through an action.
const _EXTRA_KEYS: Array[Key] = [KEY_F2, KEY_F3, KEY_M, KEY_F11, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_DELETE,
	KEY_BACKSPACE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_G, KEY_A, KEY_E, KEY_SPACE, KEY_HOME, KEY_PAGEUP]
## Keys pressed with Ctrl: the course editor's undo, redo and save.
const _CTRL_KEYS: Array[Key] = [KEY_Z, KEY_Y, KEY_S]

var main: Node
var _seed: int
var _frames_left: int
var _close_at: int
var _no_quit := false
var _rng := RandomNumberGenerator.new()
var _actions: Array[StringName] = []
## The events held down, with the frame each is let go on.
var _held: Array[InputEvent] = []
var _release_frames: Array[int] = []
## A drag of the mouse under way: where to, and the frame it ends.
var _drag_to := Vector2.ZERO
var _drag_end := -1
var _frame: int
var _still_frames: int
var _last_machine_frame := -1
var _stuck_frames: int
var _unfocused_frames: int
var _used_keys_or_pad: bool
var _finished: bool
var _screens_seen := {}
var _games_started: int
var _was_starting := false
var _unfocused_screens := {}
## The device the pad presses come from, which a new pad changes.
var _pad_device := 0
## The frames at which the window gets its focus back, the pad is plugged in again and a hitch ends, or -1.
var _refocus_frame := -1
var _replug_frame := -1
var _hitch_end_frame := -1
var _time_scale_before_hitch := 1.0
var _disturbances := {}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	main = get_parent()
	var args := OS.get_cmdline_user_args()
	var seed_arg := args.find("--masher") + 1
	if seed_arg >= args.size() or not args[seed_arg].is_valid_int():
		_finish("FAIL", "Usage: -- --masher <seed> [--seconds N] [--close-at F] [--no-quit]")
		return
	_seed = int(args[seed_arg])
	var seconds_arg := args.find("--seconds") + 1
	_frames_left = int(float(args[seconds_arg]) * 60.0) if seconds_arg > 0 and seconds_arg < args.size() else 3600
	var close_arg := args.find("--close-at") + 1
	_close_at = int(args[close_arg]) if close_arg > 0 and close_arg < args.size() else 0
	_no_quit = args.has("--no-quit")
	_rng.seed = _seed
	seed(_seed)
	for action in InputMap.get_actions():
		var name := String(action)
		if name.begins_with(Settings.ACTION_PREFIX) or name in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept",
				"ui_cancel", "ui_focus_next", "ui_focus_prev"]:
			if not InputMap.action_get_events(action).is_empty():
				_actions.append(action)
	_actions.sort()


func _exit_tree() -> void:
	if not _finished:
		_finished = true
		print("MASHER QUIT: seed %d, the game quit after %d frames: %s" % [_seed, _frame, _reached()])


func _process(_delta: float) -> void:
	if _finished:
		return
	_frame += 1
	_frames_left -= 1

	for i in range(_held.size() - 1, -1, -1):
		if _release_frames[i] <= _frame:
			var released := _held[i]
			_held.remove_at(i)
			_release_frames.remove_at(i)
			_let_go(released)
	if _drag_end >= _frame:
		var mouse := get_viewport().get_mouse_position()
		_move_mouse(mouse.lerp(_drag_to, 1.0 / maxf(_drag_end - _frame + 1, 1)), true)

	_watch()
	if _finished:
		return
	if _frame == _close_at:
		_finished = true
		print("MASHER PASS: seed %d, closed the window at frame %d: %s" % [_seed, _frame, _reached()])
		_release_held()
		_close_window()
		return
	if _frames_left <= 0:
		_finish("PASS", "seed %d, %d frames: %s" % [_seed, _frame, _reached()])
		return

	_settle_disturbances()
	# Before the press: letting go of what is held sends each event again, which must not be in the frame it was sent.
	if _rng.randf() < 0.004:
		_disturb()
	# Not every frame: a player's presses come some frames apart, and the game gets to answer them.
	if _rng.randf() < 0.4:
		_press()


## Loses the window's focus, changes its shape, unplugs the pad or takes a long frame.
func _disturb() -> void:
	var roll := _rng.randi_range(0, 3)
	if roll == 0 and _refocus_frame < 0:
		_note("focus lost")
		_release_held()
		get_tree().root.propagate_notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_refocus_frame = _frame + _rng.randi_range(1, 120)
	elif roll == 1:
		_note("window resized")
		var sizes: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1280, 800), Vector2i(2560, 1080), Vector2i(1280, 960),
			Vector2i(1920, 1080), Vector2i(640, 448), Vector2i(800, 1200), Vector2i(3440, 1440)]
		get_window().size = sizes[_rng.randi_range(0, sizes.size() - 1)]
	elif roll == 2 and _replug_frame < 0:
		_note("pad unplugged")
		for event in _held:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				_let_go(event)
		Input.joy_connection_changed.emit(_pad_device, false)
		_pad_device += 1
		_replug_frame = _frame + _rng.randi_range(30, 300)
	elif roll == 3 and _hitch_end_frame < 0:
		_note("hitch")
		# The next frame's time is as long as a hitch's, as the game sees the time passed through its time scale.
		_time_scale_before_hitch = Engine.time_scale
		Engine.time_scale = _time_scale_before_hitch * _rng.randf_range(3.0, 30.0)
		_hitch_end_frame = _frame + 1


func _settle_disturbances() -> void:
	if _frame == _refocus_frame:
		_refocus_frame = -1
		get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
		get_tree().root.propagate_notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	if _frame == _replug_frame:
		_replug_frame = -1
		Input.joy_connection_changed.emit(_pad_device, true)
	if _frame == _hitch_end_frame:
		_hitch_end_frame = -1
		Engine.time_scale = _time_scale_before_hitch


func _note(disturbance: String) -> void:
	_disturbances[disturbance] = _disturbances.get(disturbance, 0) + 1


## The screen the player is on, or "" in play.
func _screen() -> String:
	var state: String = main.testing_state()
	var menu: Menu = main._menu
	if state == "editing":
		return "course editor"
	if (state == "menu" or state == "paused") and menu.is_open():
		return "menu " + String(menu._pages[-1][0])
	return ""


## Looks for a game that stopped, and for menus without focus.
func _watch() -> void:
	var machine: NeoGeoMachine = main.machine
	if machine == null:
		_finish("FAIL", "seed %d, frame %d: there is no machine" % [_seed, _frame])
		return
	if machine.halted:
		_finish("FAIL", "seed %d, frame %d: the machine stopped%s" % [_seed, _frame,
			" at untranslated code %06X" % machine.missing_block if machine.missing_block >= 0 else ""])
		return
	var screen := _screen()
	if screen != "":
		_screens_seen[screen] = true
	var state: String = main.testing_state()
	var menu: Menu = main._menu
	if state == "starting" and not _was_starting:
		_games_started += 1
	_was_starting = state == "starting"

	var machine_frame: int = main.frame
	var playing := state == "playing" and _refocus_frame < 0
	_still_frames = _still_frames + 1 if playing and machine_frame == _last_machine_frame else 0
	_last_machine_frame = machine_frame
	if _still_frames > _MAX_STILL_FRAMES:
		_finish("FAIL", "seed %d, frame %d: the game stood still at its frame %d for %d frames with nothing paused" % [
			_seed, _frame, machine_frame, _MAX_STILL_FRAMES])
		return
	if state == "playing" and menu.visible:
		_finish("FAIL", "seed %d, frame %d: the menu shows while the game plays" % [_seed, _frame])
		return
	var stuck := (state == "paused" and not menu.is_open()) or state == "starting"
	_stuck_frames = _stuck_frames + 1 if stuck else 0
	if _stuck_frames > _MAX_STUCK_FRAMES:
		_finish("FAIL", "seed %d, frame %d: the game was %s for %d frames" % [_seed, _frame,
			"paused with no menu open" if state == "paused" else "getting a game under way", _MAX_STUCK_FRAMES])
		return

	var focus := get_viewport().gui_get_focus_owner()
	var in_menu: bool = screen.begins_with("menu ") and main.testing_menu_ready() \
		and not (menu._appearing != null and menu._appearing.is_running())
	var unfocused: bool = _used_keys_or_pad and in_menu and (focus == null or not focus.is_visible_in_tree())
	_unfocused_frames = _unfocused_frames + 1 if unfocused else 0
	if _unfocused_frames == _MAX_UNFOCUSED_FRAMES:
		_unfocused_screens[screen] = true


## Sends one input: a control's key or button, a key the game reads itself,
## a mouse click or drag somewhere or on a control, or a mouse wheel turn.
func _press() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if _no_quit and focus != null and _quits(focus):
		var away := InputEventAction.new()
		away.action = &"ui_down" if _rng.randf() < 0.5 else &"ui_up"
		away.pressed = true
		Input.parse_input_event(away)
		_hold(away, 1)
		return
	var roll := _rng.randf()
	if roll < 0.6:
		var action := _actions[_rng.randi_range(0, _actions.size() - 1)]
		var events := InputMap.action_get_events(action)
		var event: InputEvent = events[_rng.randi_range(0, events.size() - 1)].duplicate()
		if event is InputEventMouseButton:
			_click(_random_point(), (event as InputEventMouseButton).button_index)
			return
		_used_keys_or_pad = true
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			# The bindings are for any device, and a pad's presses come from its own.
			event.device = _pad_device
			# An unplugged pad presses nothing.
			if _replug_frame >= 0:
				return
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			motion.axis_value = signf(motion.axis_value) if absf(motion.axis_value) > 0.0 else 1.0
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.keycode == KEY_NONE:
				key.keycode = key.physical_keycode
			if key.physical_keycode == KEY_NONE:
				key.physical_keycode = key.keycode
		event.set("pressed", true)
		Input.parse_input_event(event)
		# held longer in a race, where the stick and the pedals are held
		_hold(event, _rng.randi_range(1, 12) if _rng.randf() < 0.7 else _rng.randi_range(20, 240))
	elif roll < 0.7:
		_used_keys_or_pad = true
		var key := InputEventKey.new()
		var ctrl := _rng.randf() < 0.15
		key.physical_keycode = _CTRL_KEYS[_rng.randi_range(0, _CTRL_KEYS.size() - 1)] if ctrl \
			else _EXTRA_KEYS[_rng.randi_range(0, _EXTRA_KEYS.size() - 1)]
		key.keycode = key.physical_keycode
		key.ctrl_pressed = ctrl
		key.shift_pressed = ctrl and _rng.randf() < 0.3
		if key.keycode >= KEY_A and key.keycode <= KEY_Z and not ctrl:
			key.unicode = key.keycode + 32
		key.pressed = true
		Input.parse_input_event(key)
		_hold(key, _rng.randi_range(1, 6))
	elif roll < 0.85:
		var target := _random_control()
		if target != null:
			_click(target.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	elif roll < 0.9:
		_click(_random_point(), MOUSE_BUTTON_LEFT if _rng.randf() < 0.7 else MOUSE_BUTTON_RIGHT)
	elif roll < 0.93:
		_drag(_random_point(), _random_point(), MOUSE_BUTTON_LEFT if _rng.randf() < 0.8 else MOUSE_BUTTON_RIGHT)
	elif roll < 0.96:
		_click(_random_point(), MOUSE_BUTTON_WHEEL_UP if _rng.randf() < 0.5 else MOUSE_BUTTON_WHEEL_DOWN)
	else:
		_move_mouse(_random_point())


func _hold(event: InputEvent, frames: int) -> void:
	_held.append(event)
	_release_frames.append(_frame + frames)


func _let_go(event: InputEvent) -> void:
	event.set("pressed", false)
	# A stick has no pressed to let go of: it goes back to the middle.
	if event is InputEventJoypadMotion:
		(event as InputEventJoypadMotion).axis_value = 0.0
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		button.position = get_viewport().get_mouse_position()
		button.global_position = button.position
	Input.parse_input_event(event)


## The viewport's own coordinates, as the window sends them.
func _to_window(point: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * point


func _move_mouse(point: Vector2, dragging := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _to_window(point)
	motion.relative = motion.position - get_viewport().get_mouse_position()
	motion.global_position = motion.position
	if dragging:
		for event in _held:
			if event is InputEventMouseButton:
				motion.button_mask |= MOUSE_BUTTON_MASK_LEFT if (event as InputEventMouseButton).button_index \
					== MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(motion)


func _click(point: Vector2, button: MouseButton) -> void:
	if _no_quit and _over_quit(point):
		return
	_used_keys_or_pad = false
	_move_mouse(point)
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.position = _to_window(point)
	click.global_position = click.position
	click.pressed = true
	Input.parse_input_event(click)
	# A wheel turn has no release; a click is let go a few frames later.
	if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
		return
	_hold(click, _rng.randi_range(1, 6))


## Presses at `from`, moves to `to` over some frames, and lets go there.
func _drag(from: Vector2, to: Vector2, button: MouseButton) -> void:
	if _drag_end >= _frame:
		return
	_click(from, button)
	var frames := _rng.randi_range(4, 40)
	_release_frames[-1] = _frame + frames + 1
	_drag_to = to
	_drag_end = _frame + frames


func _random_point() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	return Vector2(_rng.randf() * size.x, _rng.randf() * size.y)


## A control that can be pressed and is shown, but never Quit to desktop.
func _random_control() -> Control:
	var candidates: Array[Control] = []
	_collect_controls(get_tree().root, candidates)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _collect_controls(node: Node, candidates: Array[Control]) -> void:
	for child in node.get_children():
		if (child is CanvasItem and not (child as CanvasItem).visible) or (child is CanvasLayer and not (child as CanvasLayer).visible):
			continue
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE and (child as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var control := child as Control
			if control.is_visible_in_tree() and not _quits(control):
				candidates.append(control)
		_collect_controls(child, candidates)


## Whether `point` is on a shown Quit to desktop row.
func _over_quit(point: Vector2) -> bool:
	var rows: Array[Control] = []
	_collect_quit_rows(get_tree().root, rows)
	for row in rows:
		if row.get_global_rect().grow(4.0).has_point(point):
			return true
	return false


func _collect_quit_rows(node: Node, rows: Array[Control]) -> void:
	for child in node.get_children():
		if child is Button and (child as Control).is_visible_in_tree() and _quits(child):
			rows.append(child)
		_collect_quit_rows(child, rows)


static func _quits(control: Control) -> bool:
	for label in control.find_children("*", "Label", true, false):
		if (label as Label).text == "Quit to desktop":
			return true
	return false


func _reached() -> String:
	var unfocused := "none" if _unfocused_screens.is_empty() else ", ".join(_unfocused_screens.keys())
	var screens := _screens_seen.keys()
	screens.sort()
	return "%d games started, around it %s, screens %s; menus left without focus: %s" % [
		_games_started, _disturbances, ", ".join(screens), unfocused]


## Lets go of everything held, as the engine does when the window loses focus.
func _release_held() -> void:
	for event in _held:
		_let_go(event)
	_held.clear()
	_release_frames.clear()
	_drag_end = -1


func _finish(result: String, message: String) -> void:
	_finished = true
	_release_held()
	print("MASHER %s: %s" % [result, message])
	main._quit(0 if result == "PASS" else 1)


## Closes the window as the player's window manager does: the game hears of
## it, then the tree quits, as it does on its own for a real window.
func _close_window() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	if get_tree().auto_accept_quit:
		get_tree().quit()
