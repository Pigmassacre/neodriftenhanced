class_name Menu
extends Control
## The menus: the main menu, the options and the menu of a paused game.
## Drawn over the game's picture at the window's own resolution, and worked
## with the keyboard, a gamepad or the mouse.
##
## A menu is a page of rows; `open` shows one, and choosing a row that leads
## to another page puts that page on top of it. The menu changes `settings`
## itself and says so with `changed`; what a choice means for the game is
## left to whoever listens.

signal arcade_chosen
## A stage chosen to drive on its own: 0 for the practice stage.
signal stage_chosen(stage: int)
signal resumed
signal main_menu_chosen
signal quit_chosen
## A setting of this section of Settings.KEPT (or "controls") was changed.
signal changed(section: String)

const STAGES := 7
const SHADE := Color(0.02, 0.03, 0.07, 0.72)
const TEXT := Color(0.93, 0.94, 0.97)
const FAINT := Color(0.93, 0.94, 0.97, 0.55)
const CHOSEN := Color(1.0, 0.8, 0.15)
const BAR := Color(0.93, 0.94, 0.97, 0.2)
## Sizes in hundredths of the window's height.
const TITLE_SIZE := 7.0
const TEXT_SIZE := 3.4
const ROW_HEIGHT := 6.2
const WIDTH := 78.0
## The steps of a volume.
const VOLUME_STEPS := 10

var settings: Settings

## The pages open, the one shown last, as [name, the row that had the focus].
var _pages: Array = []
var _unit := 8.0
var _shade: ColorRect
var _box: VBoxContainer
var _title: Label
var _rows: VBoxContainer
var _hint: Label
var _cover: Label
var _font: FontVariation
var _heading_font: FontVariation
## The control and place a key or button is awaited for, and its button.
var _awaited_action := ""
var _awaited_place := 0
var _awaited_button: Button


func _ready() -> void:
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.5
	_heading_font = FontVariation.new()
	_heading_font.base_font = ThemeDB.fallback_font
	_heading_font.variation_embolden = 1.2
	_heading_font.variation_transform = Transform2D(Vector2(1.0, 0.22), Vector2(0.0, 1.0), Vector2.ZERO)
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_cover = Label.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_cover)
	_box = VBoxContainer.new()
	add_child(_box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	_rows = VBoxContainer.new()
	_box.add_child(_rows)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_hint)
	resized.connect(_fit)
	visible = false


## Shows the menu with `page` alone open: "main" or "pause" (or any other,
## which then has nowhere to go back to).
func open(page: String) -> void:
	_pages = [[page, 0]]
	_cover.visible = false
	_box.visible = true
	_shade.color = SHADE
	visible = true
	_fit()


## Shows nothing but `text` on black, for while a game is got ready.
func cover(text: String) -> void:
	_pages = []
	_stop_awaiting()
	_cover.text = text
	_cover.visible = true
	_box.visible = false
	_shade.color = Color.BLACK
	visible = true
	_fit()


func close() -> void:
	_pages = []
	_stop_awaiting()
	visible = false


func is_open() -> bool:
	return visible and not _pages.is_empty()


func _fit() -> void:
	_unit = maxf(size.y, 200.0) / 100.0
	_cover.add_theme_font_override("font", _heading_font)
	_cover.add_theme_font_size_override("font_size", int(TITLE_SIZE * 0.7 * _unit))
	_cover.add_theme_color_override("font_color", TEXT)
	if not _pages.is_empty():
		_show()


# --- pages -------------------------------------------------------------------

func _show() -> void:
	_stop_awaiting()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_rows.add_theme_constant_override("separation", int(0.5 * _unit))
	_box.add_theme_constant_override("separation", int(2.5 * _unit))
	_title.add_theme_font_override("font", _heading_font)
	_title.add_theme_font_size_override("font_size", int(TITLE_SIZE * _unit))
	_title.add_theme_color_override("font_color", CHOSEN)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("outline_size", int(1.2 * _unit))
	_hint.add_theme_font_override("font", _font)
	_hint.add_theme_font_size_override("font_size", int(TEXT_SIZE * 0.75 * _unit))
	_hint.add_theme_color_override("font_color", FAINT)
	_hint.text = ""
	var width := WIDTH
	match _pages[-1][0]:
		"main":
			_title.text = "Neo Drift Out"
			_item("Arcade", func() -> void: arcade_chosen.emit())
			_item("Freeplay", go.bind("freeplay"))
			_item("Options", go.bind("options"))
			_item("Quit to desktop", func() -> void: quit_chosen.emit())
		"pause":
			_title.text = "Paused"
			_item("Resume", func() -> void: resumed.emit())
			_item("Options", go.bind("options"))
			_item("Quit to main menu", func() -> void: main_menu_chosen.emit())
			_item("Quit to desktop", func() -> void: quit_chosen.emit())
		"freeplay":
			_title.text = "Freeplay"
			for stage in STAGES:
				_item("Practice stage" if stage == 0 else "Stage %d" % stage,
						func() -> void: stage_chosen.emit(stage))
			_item("Back", _back)
		"options":
			_title.text = "Options"
			_item("Picture", go.bind("picture"))
			_item("Sound", go.bind("sound"))
			_item("Controls", go.bind("controls"))
			_item("Game", go.bind("game"))
			_item("Back", _back)
		"picture":
			_title.text = "Picture"
			_switch("Full screen", "picture", "full_screen")
			_window_size()
			_switch("Vertical sync", "picture", "vsync")
			_switch("Wide picture", "picture", "wide")
			_switch("Whole-number scaling", "picture", "whole_pixels")
			_switch("Picture-tube look", "picture", "crt")
			_switch("See-through shadows", "picture", "translucency")
			_item("Back", _back)
		"sound":
			_title.text = "Sound"
			_volume("Volume", "volume")
			_volume("Music", "music")
			_volume("Effects", "effects")
			_item("Back", _back)
		"game":
			_title.text = "Game"
			_switch("Map of the course", "game", "map")
			_switch("Free continues", "game", "free_continues")
			_item("Back", _back)
		"controls":
			_title.text = "Controls"
			width = 110.0
			_controls()
			_hint.text = "Choose a place, then press what it should be.  Esc leaves it as it is, Delete empties it."
	_box.custom_minimum_size.x = minf(width * _unit, size.x * 0.94)
	_box.reset_size()
	_box.position = ((size - _box.size) / 2).round()
	_focus_row(_pages[-1][1])


## Puts `page` on top of the one shown.
func go(page: String) -> void:
	_pages[-1][1] = _focused_row()
	_pages.append([page, 0])
	_show()


func _back() -> void:
	if _pages.size() > 1:
		_pages.pop_back()
		_show()
	elif not _pages.is_empty() and _pages[0][0] == "pause":
		resumed.emit()


## The buttons of the page, in the order the focus is remembered by.
func _buttons() -> Array[Node]:
	return _rows.find_children("*", "Button", true, false)


func _focused_row() -> int:
	var buttons := _buttons()
	for index in buttons.size():
		if (buttons[index] as Button).has_focus():
			return index
	return 0


func _focus_row(index: int) -> void:
	var buttons := _buttons()
	if not buttons.is_empty():
		(buttons[clampi(index, 0, buttons.size() - 1)] as Button).grab_focus()


# --- rows --------------------------------------------------------------------

func _box_style(colour: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = border
	style.set_border_width_all(maxi(int(0.3 * _unit), 1) if border.a > 0 else 0)
	style.set_corner_radius_all(int(1.2 * _unit))
	style.content_margin_left = 3.0 * _unit
	style.content_margin_right = 3.0 * _unit
	style.anti_aliasing = true
	return style


func _button(text: String, height := ROW_HEIGHT) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = height * _unit
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", int(TEXT_SIZE * _unit * minf(height / ROW_HEIGHT * 1.15, 1.0)))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", CHOSEN)
	button.add_theme_color_override("font_pressed_color", CHOSEN)
	button.add_theme_color_override("font_hover_pressed_color", CHOSEN)
	button.add_theme_stylebox_override("normal", _box_style(Color(0, 0, 0, 0.35)))
	button.add_theme_stylebox_override("hover", _box_style(Color(0.2, 0.22, 0.3, 0.5)))
	button.add_theme_stylebox_override("pressed", _box_style(Color(0.2, 0.22, 0.3, 0.7)))
	button.add_theme_stylebox_override("focus", _box_style(Color(1.0, 0.8, 0.15, 0.1), CHOSEN))
	# the mouse over a row chooses it, as the arrow keys do
	button.mouse_entered.connect(button.grab_focus)
	return button


func _item(text: String, chosen: Callable) -> Button:
	var button := _button(text)
	button.pressed.connect(chosen)
	_rows.add_child(button)
	return button


## A row with a name at the left and something at the right. `step` is
## called with -1 or 1 for left and right, and with 1 when it is chosen.
func _row(text: String, right: Control, step: Callable) -> Button:
	var button := _button("")
	var parts := HBoxContainer.new()
	parts.set_anchors_preset(Control.PRESET_FULL_RECT)
	parts.offset_left = 3.0 * _unit
	parts.offset_right = -3.0 * _unit
	parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts.add_child(label)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parts.add_child(right)
	button.add_child(parts)
	button.focus_entered.connect(func() -> void: parts.modulate = CHOSEN)
	button.focus_exited.connect(func() -> void: parts.modulate = Color.WHITE)
	button.pressed.connect(step.bind(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		for direction: int in [-1, 1]:
			if event.is_action_pressed("ui_left" if direction < 0 else "ui_right", true):
				step.call(direction)
				button.accept_event())
	_rows.add_child(button)
	return button


func _label(text: String, colour := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", int(TEXT_SIZE * _unit))
	label.add_theme_color_override("font_color", colour)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _change(section: String, property: String, value: Variant) -> void:
	settings.set(property, value)
	settings.save_file()
	changed.emit(section)


## A row that turns a setting on and off.
func _switch(text: String, section: String, property: String) -> void:
	var value := _label("")
	var tell := func() -> void: value.text = "On" if settings.get(property) else "Off"
	tell.call()
	_row(text, value, func(_direction: int) -> void:
		_change(section, property, not settings.get(property))
		tell.call())


func _window_size() -> void:
	var sizes := Settings.window_sizes(DisplayServer.screen_get_size(get_window().current_screen))
	var value := _label("")
	var tell := func() -> void: value.text = "%d x %d" % [settings.window_size.x, settings.window_size.y]
	tell.call()
	_row("Window size", value, func(direction: int) -> void:
		var index := sizes.find(settings.window_size)
		if index < 0:
			# a size of the player's own: on to the nearest offered
			index = 0
			for other in sizes.size():
				if sizes[other].y <= settings.window_size.y:
					index = other
		_change("picture", "window_size", sizes[posmod(index + direction, sizes.size())])
		tell.call())


func _volume(text: String, property: String) -> void:
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", int(2.0 * _unit))
	var bar := ProgressBar.new()
	bar.max_value = VOLUME_STEPS
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(30.0, 1.6) * _unit
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = BAR
	back.set_corner_radius_all(int(0.8 * _unit))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	fill.set_corner_radius_all(int(0.8 * _unit))
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	parts.add_child(bar)
	var value := _label("")
	value.custom_minimum_size.x = 9.0 * _unit
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parts.add_child(value)
	var tell := func() -> void:
		var steps := roundi(float(settings.get(property)) * VOLUME_STEPS)
		bar.value = steps
		value.text = "%d%%" % (steps * 100 / VOLUME_STEPS)
	tell.call()
	_row(text, parts, func(direction: int) -> void:
		var steps := roundi(float(settings.get(property)) * VOLUME_STEPS)
		_change("sound", property, clampi(steps + direction, 0, VOLUME_STEPS) / float(VOLUME_STEPS))
		tell.call())


# --- the controls ------------------------------------------------------------

func _controls() -> void:
	var height := 4.4
	var grid := GridContainer.new()
	grid.columns = 1 + Settings.PLACES
	grid.add_theme_constant_override("h_separation", int(1.0 * _unit))
	grid.add_theme_constant_override("v_separation", int(0.4 * _unit))
	for heading: String in ["", "Key", "Gamepad", "Gamepad"]:
		var label := _label(heading, FAINT)
		label.add_theme_font_size_override("font_size", int(TEXT_SIZE * 0.8 * _unit))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(label)
	for action in Settings.ACTIONS:
		var label := _label(Settings.ACTION_NAMES[action])
		label.add_theme_font_size_override("font_size", int(TEXT_SIZE * 0.85 * _unit))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		for place in Settings.PLACES:
			var button := _button(Settings.place_name(settings.controls[action][place]), height)
			button.custom_minimum_size.x = 24.0 * _unit
			button.clip_text = true
			button.pressed.connect(_await.bind(action, place, button))
			grid.add_child(button)
	_rows.add_child(grid)
	var below := HBoxContainer.new()
	below.add_theme_constant_override("separation", int(1.0 * _unit))
	for entry: Array in [["Back", _back], ["As they were at first", _reset_controls]]:
		var button := _button(entry[0], height + 0.8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		below.add_child(button)
	_rows.add_child(below)


func _reset_controls() -> void:
	settings.reset_controls()
	_controls_changed()
	_pages[-1][1] = _focused_row()
	_show()


func _controls_changed() -> void:
	settings.apply_controls()
	settings.save_file()
	changed.emit("controls")


func _await(action: String, place: int, button: Button) -> void:
	_stop_awaiting()
	_awaited_action = action
	_awaited_place = place
	_awaited_button = button
	button.text = "Press a key" if place == 0 else "Press a button"


func _stop_awaiting() -> void:
	if _awaited_action != "" and is_instance_valid(_awaited_button):
		_awaited_button.text = Settings.place_name(settings.controls[_awaited_action][_awaited_place])
	_awaited_action = ""
	_awaited_button = null


func _input(event: InputEvent) -> void:
	if _awaited_action == "" or not visible:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		if event is InputEventMouseButton and event.pressed:
			_stop_awaiting()
		return
	# nothing pressed now is to move the focus or choose a row
	get_viewport().set_input_as_handled()
	var place := Settings.place_of(event)
	if place == "":
		return
	var is_key := place.begins_with("key:")
	if is_key and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_stop_awaiting()
	elif is_key and (event as InputEventKey).physical_keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_take(_awaited_action, _awaited_place, "")
	elif is_key == (_awaited_place == 0):
		_take(_awaited_action, _awaited_place, place)


func _take(action: String, place: int, what: String) -> void:
	settings.controls[action][place] = what
	_stop_awaiting()
	_controls_changed()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
	elif _pages[0][0] == "pause" and _pages.size() == 1 \
			and event.is_action_pressed(Settings.ACTION_PREFIX + "pause"):
		resumed.emit()
		get_viewport().set_input_as_handled()
