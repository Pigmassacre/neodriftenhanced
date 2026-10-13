class_name Settings
extends RefCounted
## What the player has chosen in the options menu, kept in a file between
## runs, and the keys and gamepad buttons of the game's controls.
##
## A control is an input action named ACTION_PREFIX + its name. Each has
## three places for what works it: a key, and two for a gamepad's buttons
## and sticks. A place holds "" for nothing, "key:PHYSICAL KEYCODE",
## "button:INDEX" or "axis:INDEX:+" (or "-") for a stick or trigger moved
## that way.

const ACTION_PREFIX := "game_"
const PLACES := 3
## The controls in the order the menu lists them, and what it calls them.
const ACTIONS: Array[String] = ["up", "down", "left", "right", "a", "b", "c", "d", "start", "coin", "pause"]
const ACTION_NAMES := {
	"up": "Up", "down": "Down", "left": "Left", "right": "Right",
	"a": "Accelerate (A)", "b": "Brake (B)", "c": "Button C", "d": "Button D",
	"start": "Start", "coin": "Insert coin", "pause": "Pause",
}
const DEFAULT_CONTROLS := {
	"up": ["key:%d" % KEY_UP, "button:%d" % JOY_BUTTON_DPAD_UP, "axis:%d:-" % JOY_AXIS_LEFT_Y],
	"down": ["key:%d" % KEY_DOWN, "button:%d" % JOY_BUTTON_DPAD_DOWN, "axis:%d:+" % JOY_AXIS_LEFT_Y],
	"left": ["key:%d" % KEY_LEFT, "button:%d" % JOY_BUTTON_DPAD_LEFT, "axis:%d:-" % JOY_AXIS_LEFT_X],
	"right": ["key:%d" % KEY_RIGHT, "button:%d" % JOY_BUTTON_DPAD_RIGHT, "axis:%d:+" % JOY_AXIS_LEFT_X],
	"a": ["key:%d" % KEY_Z, "button:%d" % JOY_BUTTON_A, "axis:%d:+" % JOY_AXIS_TRIGGER_RIGHT],
	"b": ["key:%d" % KEY_X, "button:%d" % JOY_BUTTON_B, "axis:%d:+" % JOY_AXIS_TRIGGER_LEFT],
	"c": ["key:%d" % KEY_C, "button:%d" % JOY_BUTTON_X, ""],
	"d": ["key:%d" % KEY_V, "button:%d" % JOY_BUTTON_Y, ""],
	"start": ["key:%d" % KEY_1, "button:%d" % JOY_BUTTON_START, ""],
	"coin": ["key:%d" % KEY_5, "button:%d" % JOY_BUTTON_BACK, ""],
	"pause": ["key:%d" % KEY_ESCAPE, "button:%d" % JOY_BUTTON_START, ""],
}
const HUD_NEW := 0
const HUD_ORIGINAL := 1
const HUD_NONE := 2
const HUD_NAMES: Array[String] = ["New", "Original", "None"]
## The curve of the picture tube's glass at its most (video/crt.gdshader).
const MOST_CRT_CURVE := 0.15
## How far a stick or trigger must be moved to count.
const STICK_MOVED := 0.5
const BUTTON_NAMES: Array[String] = [
	"A", "B", "X", "Y", "Back", "Guide", "Start", "Left stick", "Right stick", "LB", "RB",
	"Pad up", "Pad down", "Pad left", "Pad right",
]
const AXIS_NAMES := {
	"0:-": "Stick left", "0:+": "Stick right", "1:-": "Stick up", "1:+": "Stick down",
	"2:-": "Right stick left", "2:+": "Right stick right", "3:-": "Right stick up", "3:+": "Right stick down",
	"4:+": "LT", "5:+": "RT",
}
## The window sizes offered.
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(640, 448), Vector2i(960, 672), Vector2i(1280, 720), Vector2i(1280, 896), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160),
]

## The file they are kept in.
var path := "user://settings.cfg"

## The picture.
var full_screen := false
var window_size := Vector2i(1280, 896)
var vsync := true
## As wide a picture as the window; without, the original's 320 pixels.
var wide := true
var whole_pixels := false
var crt := false
## How much the picture tube's glass curves, from 0 to 1.
var crt_curve := 0.3
var translucency := true
## The game.
var map := true
## The HUD of a race: HUD_NEW, HUD_ORIGINAL or HUD_NONE.
var hud := HUD_NEW
var free_continues := true
## The sound, each from 0 to 1.
var volume := 1.0
var music := 1.0
var effects := 1.0
## For each control its PLACES places.
var controls := {}

## The properties kept in the file, by section.
const KEPT := {
	"picture": ["full_screen", "window_size", "vsync", "wide", "whole_pixels", "crt", "crt_curve", "translucency"],
	"game": ["hud", "map", "free_continues"],
	"sound": ["volume", "music", "effects"],
}


func _init() -> void:
	reset_controls()


func reset_controls() -> void:
	controls = DEFAULT_CONTROLS.duplicate(true)


func load_file() -> void:
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for section: String in KEPT:
		for property: String in KEPT[section]:
			var value: Variant = file.get_value(section, property, get(property))
			if typeof(value) == typeof(get(property)):
				set(property, value)
	for action in ACTIONS:
		var places: Variant = file.get_value("controls", action, null)
		if places is Array and places.size() == PLACES:
			controls[action] = places.map(func(place: Variant) -> String: return str(place))


func save_file() -> void:
	var file := ConfigFile.new()
	for section: String in KEPT:
		for property: String in KEPT[section]:
			file.set_value(section, property, get(property))
	for action in ACTIONS:
		file.set_value("controls", action, controls[action])
	file.save(path)


## Makes the input actions what `controls` says.
func apply_controls() -> void:
	for action in ACTIONS:
		var name := ACTION_PREFIX + action
		if InputMap.has_action(name):
			InputMap.action_erase_events(name)
		else:
			InputMap.add_action(name, STICK_MOVED)
		for place: String in controls[action]:
			var event := event_of(place)
			if event != null:
				InputMap.action_add_event(name, event)


static func event_of(place: String) -> InputEvent:
	var parts := place.split(":")
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(parts[1]) as Key
			return key
		"button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(parts[1]) as JoyButton
			return button
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(parts[1]) as JoyAxis
			motion.axis_value = -1.0 if parts[2] == "-" else 1.0
			return motion
	return null


## The place an event would be kept as, or "" for one that is no key press,
## button press or decided move of a stick.
static func place_of(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		return "key:%d" % key.physical_keycode
	var button := event as InputEventJoypadButton
	if button != null and button.pressed:
		return "button:%d" % button.button_index
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) > 0.7:
		return "axis:%d:%s" % [motion.axis, "-" if motion.axis_value < 0 else "+"]
	return ""


## What the menu calls a place.
static func place_name(place: String) -> String:
	var parts := place.split(":", true, 1)
	match parts[0]:
		"key":
			var code := DisplayServer.keyboard_get_keycode_from_physical(int(parts[1]) as Key)
			return OS.get_keycode_string(code)
		"button":
			var index := int(parts[1])
			return BUTTON_NAMES[index] if index < BUTTON_NAMES.size() else "Button %d" % index
		"axis":
			return AXIS_NAMES.get(parts[1], "Axis %s" % parts[1])
	return "-"


## The window sizes that fit the screen the window is on.
static func window_sizes(screen: Vector2i) -> Array[Vector2i]:
	var fitting: Array[Vector2i] = []
	for size in WINDOW_SIZES:
		if size.x <= screen.x and size.y <= screen.y:
			fitting.append(size)
	if fitting.is_empty():
		fitting.append(WINDOW_SIZES[0])
	return fitting
