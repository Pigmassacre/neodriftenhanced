class_name RunBot
extends Node
## Plays whole games by itself, as a player who picks at random among what
## they could do, to find what scripted sessions miss:
## `-- --bot <seed> [--games N] [--minutes M] [--stop-after S] [--close-at F]
## [--check-save] [--no-options]`.
##
## It plays as a player would, with the files of its user data directory
## (so run it with one of its own), and every game goes through the real
## menus, worked with the keys the menus answer to: the main menu's Arcade,
## Freeplay (a stage, or a mod's course) and Options (Picture, Sound and
## Game, each setting changed at random), the pause menu (Resume, Options,
## Quit to main menu) and, after the last game, Quit to desktop. In a race
## the autopilot accelerates and steers for the waypoints the other cars
## follow, now and then brakes, lets go or steers wrong, and on the screens
## around the races (car choice, results, continue, name entry) presses
## buttons at random.
##
## Every half second it checks the game: the machine has not stopped, a game
## in play goes on, the menu is open when it should be and shut when not, and
## no screen of the game lasts too long. As each game starts it prints how
## many objects and nodes there are, which Tools/release_check.py reads to
## find leaks; as each ends, it checks that the best times on disk are those
## the game holds and that the options file reads.
##
## --minutes leaves a game that lasts that long in game time from the pause
## menu (default 8). --stop-after ends the bot S seconds into its first
## game. --close-at closes the window at that frame, wherever the game is, as
## a player does, and passes if the game then quits cleanly. --check-save
## fails at once if the best times or the options on disk do not read.
## --no-options leaves the options as they are.
##
## It prints "BOT PASS: ..." and quits with 0 when every game has ended, or
## "BOT FAIL: ..." and quits with 1.

static var is_active: bool = OS.get_cmdline_user_args().has("--bot")

const GameFlow := preload("res://game/game_flow.gd")
const BestTimes := preload("res://game/best_times.gd")
const Car := preload("res://game/car.gd")
const Rival := preload("res://game/rival.gd")

## How many frames the bot may wait for what it waits for.
const _MAX_WAIT_FRAMES := 3600
## How many frames a game in play may go with its machine standing still.
const _MAX_STILL_FRAMES := 600
## How many frames the game may stay on one screen outside a race, with the
## bot pressing buttons all the while.
const _MAX_SCREEN_FRAMES := 3 * 60 * 60
## How many frames a race may go without the car moving from a small square.
const _MAX_PARKED_FRAMES := 60 * 60
## Frames between checks.
const _CHECK_EVERY := 30
## Frames the bot waits before it presses something in a menu, at least and at most.
const _THINK := Vector2i(6, 40)
## A frame's chance, in a race, of the bot opening the pause menu.
const _PAUSE_ODDS := 1.0 / 2400.0
const _MAIN := GameFlow.MAIN_STATE & 0xFFFF
const _CAR := 0x101500

var main: Node
var _seed: int
var _games: int
var _minutes: float
var _stop_after: float
var _close_at: int
var _rng := RandomNumberGenerator.new()
var _frame := 0
var _finished := false
## Games started, and the one in play (its description), or "".
var _game := 0
var _game_description := ""
var _in_game := false
## What the game chosen in the menu is, until it starts.
var _chosen_game := ""
## Quit to desktop has been chosen, after the last game.
var _quitting := false
var _game_start_frame := 0
var _leaving := false
var _wait_frames := 0
var _waiting_for := ""
var _act_at := 0
## Keys to press in a menu, one a press, and the actions held in a race.
var _presses: Array[StringName] = []
var _held_keys: Array[InputEvent] = []
var _held_actions := {}
## What the game was at when last checked.
var _last_machine_frame := -1
var _still_frames := 0
var _screen := ""
var _screen_frames := 0
var _parked_at := Vector2i.ZERO
var _parked_frames := 0
## Where the autopilot is heading, and how it is driving now.
var _waypoint := 1
var _mistake_frames := 0
var _mistake := ""
## Which settings pages it has been through in this visit to the options.
var _option_pages := 0
## --no-options: the bot leaves the options as they are.
var _no_options := false
## The courses driven in the game.
var _courses: Array[int] = []
## What the games reached, to show what the runs get to.
var _reached := {}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	main = get_parent()
	var args := OS.get_cmdline_user_args()
	var seed_arg := args.find("--bot") + 1
	if seed_arg >= args.size() or not args[seed_arg].is_valid_int():
		_finish(1, "Usage: -- --bot <seed> [--games N] [--minutes M] [--stop-after S] [--close-at F] [--check-save] [--no-options]")
		return
	_seed = int(args[seed_arg])
	_games = int(_option(args, "--games", "1"))
	_minutes = float(_option(args, "--minutes", "8"))
	_stop_after = float(_option(args, "--stop-after", "0"))
	_close_at = int(_option(args, "--close-at", "0"))
	_no_options = args.has("--no-options")
	_rng.seed = _seed
	seed(_seed)
	if args.has("--check-save"):
		var problem := _check_files(false)
		if problem != "":
			_finish(1, problem)


static func _option(args: PackedStringArray, name: String, default: String) -> String:
	var index := args.find(name) + 1
	return args[index] if index > 0 and index < args.size() else default


func _process(_delta: float) -> void:
	if _finished:
		return
	_frame += 1
	for event in _held_keys:
		event.set("pressed", false)
		Input.parse_input_event(event)
	_held_keys.clear()
	if _frame == _close_at:
		_finished = true
		_let_go_all()
		print("BOT PASS: seed %d, closed the window at frame %d, in game %d (%s)" % [_seed, _frame, _game, _game_description])
		_close_window()
		return
	if _stop_after > 0.0 and _in_game and _frame - _game_start_frame > _stop_after * 60.0:
		_finish(0, "seed %d, stopped %d s into game %d (%s)" % [_seed, int(_stop_after), _game, _game_description])
		return
	var error := ""
	if _frame % _CHECK_EVERY == 0:
		error = _check()
	if error == "":
		error = _step()
	if error != "":
		_finish(1, "seed %d, game %d (%s), frame %d: %s" % [_seed, _game, _game_description, _frame, error])


# --- what to do --------------------------------------------------------------

func _step() -> String:
	var state: String = main.testing_state()
	var menu: Menu = main._menu
	match state:
		"starting":
			_let_go_all()
			if not _in_game:
				if _chosen_game == "":
					return "a game started that the bot did not choose"
				_begin_game(_chosen_game)
				_chosen_game = ""
			return _wait("the game to get under way")
		"editing":
			# the bot does not edit courses: the masher does
			_press_key(KEY_ESCAPE)
			return _wait("the course editor to close")
		"menu", "paused":
			_let_go_all()
			if _in_game and state == "menu":
				var error := _game_ended()
				if error != "":
					return error
			if not main.testing_menu_ready() or not menu.is_open() or menu._appearing != null and menu._appearing.is_running():
				return _wait("the menu")
			return _on_menu(menu)
		"playing":
			return _on_game()
	return ""


## Counts a frame spent waiting, and says what went wrong once it has waited too long.
func _wait(for_what: String) -> String:
	if for_what != _waiting_for:
		_waiting_for = for_what
		_wait_frames = 0
	_wait_frames += 1
	if _wait_frames > _MAX_WAIT_FRAMES:
		return "waited %d frames for %s" % [_MAX_WAIT_FRAMES, for_what]
	return ""


func _moved_on() -> void:
	_waiting_for = ""
	_wait_frames = 0


# --- the menus ---------------------------------------------------------------

func _on_menu(menu: Menu) -> String:
	_moved_on()
	if _frame < _act_at:
		return ""
	_act_at = _frame + _rng.randi_range(_THINK.x, _THINK.y)
	if not _presses.is_empty():
		_press_action(_presses.pop_front())
		return ""
	var page: String = menu._pages[-1][0]
	var rows := _rows(menu)
	if rows.is_empty():
		return "the menu's %s page has no rows" % page
	var focused := _focused(rows)
	if focused < 0:
		return "nothing has the focus on the menu's %s page" % page
	_reached["menu " + page] = true
	var want := ""
	match page:
		"main":
			_option_pages = 0
			if _game >= _games:
				want = "Quit to desktop"
				_quitting = true
			else:
				var roll := _rng.randf()
				want = "Arcade" if roll < 0.35 else "Freeplay" if roll < 0.85 or _no_options else "Options"
		"freeplay":
			# a stage driven on its own ends back here
			var names := _names(rows)
			names.erase("Back")
			want = "Back" if _game >= _games or _rng.randf() < 0.05 else names[_rng.randi_range(0, names.size() - 1)]
		"pause":
			if _leaving or _rng.randf() < 0.2:
				want = "Quit to main menu"
			else:
				want = "Options" if _rng.randf() < 0.2 and _option_pages < 2 and not _no_options else "Resume"
		"options":
			_option_pages += 1
			if _no_options:
				_option_pages = 99
			var pages: Array[String] = ["Picture", "Sound", "Game"]
			want = "Back" if _option_pages > 2 or _rng.randf() < 0.2 else pages[_rng.randi_range(0, pages.size() - 1)]
		"picture", "sound", "game":
			# a setting or two changed, then back
			if _rng.randf() < 0.35:
				want = "Back"
			else:
				var names := _names(rows)
				names.erase("Back")
				# full screen and the window's size are the player's machine's to try
				names.erase("Full screen")
				names.erase("Window size")
				var row := rows[_names(rows).find(names[_rng.randi_range(0, names.size() - 1)])]
				_go_to(rows, focused, rows.find(row))
				for i in _rng.randi_range(1, 3):
					_presses.append(&"ui_left" if _rng.randf() < 0.5 else &"ui_right")
				return ""
		_:
			want = "Back"
	var target := _names(rows).find(want)
	if target < 0:
		return "the menu's %s page has no row %s (it has %s)" % [page, want, ", ".join(_names(rows))]
	_go_to(rows, focused, target)
	_presses.append(&"ui_accept")
	if page == "main" and want == "Arcade":
		_chosen_game = "Arcade"
	elif page == "freeplay" and want != "Back":
		_chosen_game = want
	elif page == "pause" and want == "Quit to main menu":
		_reached["left a game from the pause menu"] = true
	return ""


func _rows(menu: Menu) -> Array[Button]:
	var rows: Array[Button] = []
	for node in menu._buttons():
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled:
			rows.append(button)
	return rows


func _focused(rows: Array[Button]) -> int:
	for index in rows.size():
		if rows[index].has_focus():
			return index
	return -1


## What each row says: its name, after its number.
static func _names(rows: Array[Button]) -> Array[String]:
	var names: Array[String] = []
	for row in rows:
		var labels := row.find_children("*", "Label", true, false)
		names.append((labels[1] as Label).text if labels.size() > 1 else "")
	return names


## Presses up or down until the row `target` has the focus, the short way round.
func _go_to(rows: Array[Button], from: int, target: int) -> void:
	var down := posmod(target - from, rows.size())
	var up := posmod(from - target, rows.size())
	for i in mini(down, up):
		_presses.append(&"ui_down" if down <= up else &"ui_up")


func _begin_game(description: String) -> void:
	_game += 1
	_game_description = description
	_in_game = true
	_leaving = false
	_game_start_frame = _frame
	_waypoint = 1
	_screen = ""
	_screen_frames = 0
	_parked_frames = 0
	_courses = []
	print("BOT GAME %d: %s, at frame %d" % [_game, description, _frame])
	print("BOT MEMORY %d: objects %d, nodes %d, orphan nodes %d, resources %d" % [_game,
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])


## Back at the main menu after a game: checks what the game keeps on disk.
func _game_ended() -> String:
	_in_game = false
	print("BOT GAME %d ended at frame %d, %d frames in, courses driven: %s" % [_game, _frame,
		_frame - _game_start_frame, ", ".join(_courses.map(str)) if not _courses.is_empty() else "none"])
	_reached["games ended"] = _reached.get("games ended", 0) + 1
	return _check_files(true)


## The best times on disk must read, and after a game be what the new machine
## holds; the options must read.
func _check_files(after_game: bool) -> String:
	var settings_path: String = main._settings.path
	if FileAccess.file_exists(settings_path) and ConfigFile.new().load(settings_path) != OK:
		return "the options at %s don't read" % ProjectSettings.globalize_path(settings_path)
	var times_path: String = main._best_times()
	if not FileAccess.file_exists(times_path):
		return ""
	var on_disk := FileAccess.get_file_as_bytes(times_path)
	if on_disk.size() != BestTimes.KEPT_SIZE:
		return "the best times at %s are %d bytes, not %d" % [ProjectSettings.globalize_path(times_path),
			on_disk.size(), BestTimes.KEPT_SIZE]
	if after_game and main.machine != null and Decomp.kept_times(main.machine) != on_disk:
		return "the best times on disk are not those the game holds"
	return ""


# --- a game ------------------------------------------------------------------

func _on_game() -> String:
	_moved_on()
	var machine: NeoGeoMachine = main.machine
	if _minutes > 0.0 and _in_game and _frame - _game_start_frame > _minutes * 3600.0:
		_leaving = true
	if _driving() and (_leaving or _rng.randf() < _PAUSE_ODDS):
		_let_go_all()
		_press_action(StringName(Settings.ACTION_PREFIX + "pause"))
		_reached["paused a race"] = true
		return ""
	if _driving():
		_drive(machine)
	else:
		_press_through_screens()
	return ""


func _driving() -> bool:
	return main._driving()


## Steers for the waypoints the other cars follow, with the accelerator
## down, and now and then gets it wrong for a while.
func _drive(machine: NeoGeoMachine) -> void:
	_reached["drove"] = true
	var course := machine.r16(GameFlow.COURSE)
	var waypoints := machine.r32(Rival.WAYPOINTS + course * 4)
	var count := machine.r16(Rival.WAYPOINT_COUNTS + course * 2)
	var x := machine.r16(_CAR + Car.X)
	var y := machine.r16(_CAR + Car.Y)
	if count > 0:
		_waypoint = clampi(_waypoint, 0, count - 1)
		# heading for the nearest of the next few, which also finds the way again after a wrong turn
		var best := _waypoint
		var best_distance := INF
		for step in 4:
			var index := (_waypoint + step) % count
			var point := waypoints + index * Rival.WAYPOINT_SIZE
			var distance := Vector2(_s16(machine.r16(point)) - _s16(x), _s16(machine.r16(point + 2)) - _s16(y)).length()
			if distance < best_distance:
				best_distance = distance
				best = index
		_waypoint = best
		var point := waypoints + _waypoint * Rival.WAYPOINT_SIZE
		if best_distance < maxf(machine.r16(point + 4), machine.r16(point + 6)) * 0.5 + 8.0:
			_waypoint = (_waypoint + 1) % count
	var steer := 0
	if count > 0:
		var point := waypoints + _waypoint * Rival.WAYPOINT_SIZE
		# the car's directions are 256 to the turn, 0x80 towards larger x and 0xC0 up the screen:
		# the other way round from the screen's angles
		var towards := atan2(_s16(machine.r16(point + 2)) - _s16(y), _s16(machine.r16(point)) - _s16(x))
		var wanted := 0x80 - towards / TAU * 256.0
		var travel := machine.r16(_CAR + Car.TRAVEL) & 0xFF
		var turn := wrapf(wanted - travel, -128.0, 128.0)
		# A turn the wrong way round the car's angles is to the right. The car slides, so it is
		# steered in pulses, the longer the more it has to turn, or it spins.
		var pulse := clampi(int(absf(turn) / 6.0), 0, 8)
		if _frame % 8 < pulse:
			steer = 1 if turn < 0.0 else -1
	if _mistake_frames > 0:
		_mistake_frames -= 1
	elif _rng.randf() < 0.01:
		_mistake = ["brake", "coast", "left", "right", "buttons"][_rng.randi_range(0, 4)]
		_mistake_frames = _rng.randi_range(5, 90)
	var held := {"a": true}
	if _mistake_frames > 0:
		match _mistake:
			"brake":
				held = {"b": true}
			"coast":
				held = {}
			"left":
				steer = -1
			"right":
				steer = 1
			"buttons":
				held = {"a": true, "c": _rng.randf() < 0.5, "d": _rng.randf() < 0.5}
	if steer < 0:
		held["left"] = true
	elif steer > 0:
		held["right"] = true
	_hold(held)


static func _s16(value: int) -> int:
	return value - 0x10000 if value >= 0x8000 else value


## Outside a race: the car choice, the screens before and after a race, the
## continue and the entry of a name. Presses A mostly, Start and the
## stick now and then.
func _press_through_screens() -> void:
	var held := {}
	if _frame % 8 < 3:
		var roll := _rng.randf()
		if roll < 0.6:
			held["a"] = true
		elif roll < 0.7:
			held["start"] = true
		elif roll < 0.9:
			held[["left", "right", "up", "down"][_rng.randi_range(0, 3)]] = true
		elif roll < 0.95:
			held["b"] = true
	_hold(held)


## Holds the game's actions in `held` down and lets go of the others.
func _hold(held: Dictionary) -> void:
	for button: String in Settings.ACTIONS:
		var action := Settings.ACTION_PREFIX + button
		var down: bool = held.get(button, false)
		if down and not _held_actions.has(action):
			Input.action_press(action)
			_held_actions[action] = true
		elif not down and _held_actions.has(action):
			Input.action_release(action)
			_held_actions.erase(action)


func _let_go_all() -> void:
	_hold({})


func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	_held_keys.append(event)


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	_held_keys.append(event)


# --- checks ------------------------------------------------------------------

## Looks for a game that stopped, a menu where there should be none, or a
## screen the game does not move on from.
func _check() -> String:
	var machine: NeoGeoMachine = main.machine
	if machine == null:
		return "there is no machine"
	if machine.halted:
		return "the machine stopped%s" % (" at untranslated code %06X" % machine.missing_block if machine.missing_block >= 0 else "")
	var state: String = main.testing_state()
	var menu: Menu = main._menu
	if state == "playing" and menu.visible:
		return "the menu shows while the game plays"
	if state == "paused" and not menu.is_open():
		return "the game is paused with no menu open"
	if state != "playing":
		_still_frames = 0
		_screen_frames = 0
		_parked_frames = 0
		return ""
	var machine_frame: int = main.frame
	_still_frames = _still_frames + _CHECK_EVERY if machine_frame == _last_machine_frame else 0
	_last_machine_frame = machine_frame
	if _still_frames > _MAX_STILL_FRAMES:
		return "the machine stood still at frame %d for %d frames with nothing paused" % [machine_frame, _still_frames]
	var ram: PackedByteArray = machine.ram
	var screen := "main %d, game %d, courses %d, race %d" % [ram.decode_u16(_MAIN),
		ram.decode_u16(GameFlow.GAME_STATE & 0xFFFF), ram.decode_u16(GameFlow.COURSES_STATE & 0xFFFF),
		ram.decode_u16(GameFlow.RACE_STATE & 0xFFFF)]
	if _driving():
		_screen_frames = 0
		var at := Vector2i(machine.r16(_CAR + Car.X), machine.r16(_CAR + Car.Y))
		if absi(at.x - _parked_at.x) < 24 and absi(at.y - _parked_at.y) < 24:
			_parked_frames += _CHECK_EVERY
		else:
			_parked_frames = 0
			_parked_at = at
		if _parked_frames > _MAX_PARKED_FRAMES:
			_reached["stuck at a wall"] = _reached.get("stuck at a wall", 0) + 1
			# the clock runs out sooner or later; this only notes it
			_parked_frames = 0
		var course := machine.r16(GameFlow.COURSE)
		_reached["course %d" % course] = true
		if not course in _courses:
			_courses.append(course)
		return ""
	if screen != _screen:
		_screen = screen
		_screen_frames = 0
	_screen_frames += _CHECK_EVERY
	if _screen_frames > _MAX_SCREEN_FRAMES:
		return "the game stayed at %s for %d frames" % [screen, _screen_frames]
	return ""


func _finish(exit_code: int, message: String) -> void:
	_finished = true
	_let_go_all()
	var reached := _reached.keys()
	reached.sort()
	var what := ", ".join(reached.map(func(key: String) -> String:
		return key if not (_reached[key] is int) else "%s %d" % [key, _reached[key]]))
	print("BOT %s: %s; reached: %s" % ["PASS" if exit_code == 0 else "FAIL", message, what])
	main._quit(exit_code)


func _exit_tree() -> void:
	if _finished:
		return
	_finished = true
	var reached := _reached.keys()
	reached.sort()
	if _quitting:
		print("BOT PASS: seed %d, %d games, then Quit to desktop; reached: %s" % [_seed, _game, ", ".join(reached)])
	else:
		print("BOT FAIL: seed %d, game %d (%s), frame %d: the game quit by itself" % [_seed, _game, _game_description, _frame])


## Closes the window as the player's window manager does: the game hears of
## it, then the tree quits, as it does on its own for a real window.
func _close_window() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	if get_tree().auto_accept_quit:
		get_tree().quit()
