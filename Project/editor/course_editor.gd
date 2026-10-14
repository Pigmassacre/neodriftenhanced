class_name CourseEditor
extends Control
## The course editor: makes and changes the courses of mods
## (mods/mod_courses.gd) with the mouse, over a view of the course
## (editor/course_view.gd). A course starts as a copy of one of the game's
## and is kept as a mod in the user's mods folder, so that what is made
## here is driven like any other mod's course, and can be shared as one.
##
## Its tools, each with a palette at the side:
##
## - Cells: puts cells on the map, and gives a place a cell of its own.
## - Ground: paints the ground codes of cells (walls, edges, surfaces,
##   gates).
## - Scenery: puts things beside the road, moves them and takes them away.
## - Route: the boxes the other cars drive for, and their speeds.
## - Start: where the car starts and faces, and the lines of the bar that
##   shows how far along the course the car is.
## - Signs: the signs of the turns ahead, by place.
##
## Every change can be undone. Saving writes the mod; test driving saves
## and drives the course.

## The course is saved and driven: the mod's folder name and the course it
## is made from.
signal test_drive(mod_id: String, base: int)
signal closed

const ExportCourse := preload("res://tools/export_course.gd")
const Scenery := preload("res://game/scenery.gd")
const ModCourses := preload("res://mods/mod_courses.gd")
const CourseView := preload("res://editor/course_view.gd")

enum Tool {CELLS, GROUND, SCENERY, ROUTE, START, SIGNS}
const TOOL_NAMES := ["Cells", "Ground", "Scenery", "Route", "Start", "Signs"]
const TOOL_HELP := [
	"Left: put the chosen cell here (with its scenery).  Right: choose the cell here.",
	"Left: paint the chosen code.  Right: choose the code here.  Every place with this cell changes; give it a cell of its own first to change one place alone.",
	"Left: put the chosen thing, or pick one up and move it.  Right: take it away.",
	"Left: choose a box and move it (its corner sizes it), or add one after the chosen.  Right: take a box away.",
	"Left: put the start here.  Shift and left: face the car towards here.  Drag a line to move it.",
	"Left: put the chosen sign here.  Right: take it away.",
]
const CODES_SHOWN := 0.45
const PANEL_WIDTH := 340
const THUMB := 48
## The time a frame may give to drawing the pictures of cells.
const DRAW_BUDGET_MSEC := 12
const UNDO_STEPS := 200
## The signs the game has.
const SIGNS := 32
## A new box of the route.
const NEW_BOX := Vector2i(192, 128)

var data: CourseData
var folder := ""
var machine: NeoGeoMachine
var tool := Tool.CELLS
var show_codes := false
var show_scenery := true
var show_route := false
var chosen_cell := 0
var chosen_code := 0x50
var brush := 2
var chosen_kind := 1
var chosen_sign := 1
var selected_thing := -1
var selected_point := -1
var selected_line := -1

var _view: CourseView
var _status: Label
var _help: Label
var _tool_buttons: Array[Button] = []
var _palettes: Array[Control] = []
var _cell_list: ItemList
var _code_list: ItemList
var _kind_list: ItemList
var _sign_list: ItemList
var _point_fields: Array[SpinBox] = []
var _facing: SpinBox
var _progress: LineEdit
var _rivals: LineEdit
var _name: LineEdit
var _time: LineEdit
var _music: OptionButton
var _arcade: CheckBox
var _codes_check: CheckBox
var _confirm: ConfirmationDialog
var _filling_fields := false

var _cell_textures := {}
var _code_textures := {}
var _kind_textures := {}
var _kind_sizes := {}
var _waiting_cells: Array[int] = []
var _waiting_kinds: Array[int] = []
var _changed_codes := {}
var _dirty := false
## Each step: what it changed and the values from before.
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
## The step being made while a button is held.
var _step := {}
var _dragging := ""
var _grab := Vector2i.ZERO
var _last_place := -1
var _offsets := {}


## Opens the course of the mod at `path`, or with `path` empty a new course
## made from the game's course `base`.
func open(path: String, base := 1) -> void:
	machine = MachineLoader.create(true, false)
	if machine == null:
		closed.emit()
		return
	if path == "":
		path = _new_folder(base)
		ExportCourse.export_course(machine, base, path, true)
	folder = path
	data = CourseData.from_mod(machine, folder)
	_set_up_offsets()
	_build()
	_fill_settings()
	_view.zoom = 0.3
	_view.look_at_course(Vector2(data.start))
	_choose_tool(Tool.CELLS)


func _exit_tree() -> void:
	if machine != null:
		machine.release()
		machine = null


## A folder for a new course, in the user's mods.
static func _new_folder(base: int) -> String:
	var mods := ProjectSettings.globalize_path("user://mods")
	DirAccess.make_dir_recursive_absolute(mods)
	var stem := "course_%s" % ("practice" if base == 0 else "stage%d" % base)
	var number := 1
	while DirAccess.dir_exists_absolute(mods.path_join("%s_%d" % [stem, number])):
		number += 1
	return mods.path_join("%s_%d" % [stem, number])


# --- the look ----------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _theme()
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.08)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 0)
	add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	columns.add_child(left)
	var bar := HBoxContainer.new()
	left.add_child(_padded(bar, Color(0.09, 0.1, 0.13)))
	var group := ButtonGroup.new()
	for index in TOOL_NAMES.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, TOOL_NAMES[index]]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_choose_tool.bind(index))
		bar.add_child(button)
		_tool_buttons.append(button)
	bar.add_child(_spacer())
	_codes_check = _check(bar, "Ground codes (G)", show_codes, func(on: bool) -> void:
		show_codes = on
		_view.queue_redraw())
	_check(bar, "Scenery", show_scenery, func(on: bool) -> void:
		show_scenery = on
		_view.queue_redraw())
	_check(bar, "Route", show_route, func(on: bool) -> void:
		show_route = on
		_view.queue_redraw())
	_view = CourseView.new()
	_view.editor = self
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_view)
	var foot := VBoxContainer.new()
	left.add_child(_padded(foot, Color(0.09, 0.1, 0.13)))
	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.add_theme_color_override("font_color", Color(0.94, 0.95, 0.98))
	foot.add_child(_help)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	foot.add_child(_status)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = PANEL_WIDTH
	var panel := _padded(side, Color(0.08, 0.09, 0.12))
	columns.add_child(panel)
	var title := Label.new()
	title.text = "Course editor"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.08))
	side.add_child(title)
	var where := Label.new()
	where.text = folder
	where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	side.add_child(where)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(stack)
	for index in TOOL_NAMES.size():
		var palette := VBoxContainer.new()
		palette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(palette)
		_palettes.append(palette)
	_build_cells(_palettes[Tool.CELLS])
	_build_ground(_palettes[Tool.GROUND])
	_build_scenery(_palettes[Tool.SCENERY])
	_build_route(_palettes[Tool.ROUTE])
	_build_start(_palettes[Tool.START])
	_build_signs(_palettes[Tool.SIGNS])

	side.add_child(HSeparator.new())
	_name = _field(side, "Name", LineEdit.new())
	_name.text_changed.connect(func(text: String) -> void:
		data.name = text
		_dirty = true)
	_time = _field(side, "Seconds: at the start, then at each checkpoint", LineEdit.new())
	_time.text_submitted.connect(_set_time.unbind(1))
	_time.focus_exited.connect(_set_time)
	var row := HBoxContainer.new()
	side.add_child(row)
	var music_label := Label.new()
	music_label.text = "Music of"
	row.add_child(music_label)
	_music = OptionButton.new()
	for course in ModCourses.COURSE_COUNT:
		_music.add_item("Practice" if course == 0 else "Stage %d" % course, course)
	_music.item_selected.connect(func(index: int) -> void:
		data.music = index
		_dirty = true)
	row.add_child(_music)
	_arcade = CheckBox.new()
	_arcade.text = "In Arcade"
	_arcade.tooltip_text = "Driven in Arcade in place of the course it is made from."
	_arcade.toggled.connect(func(on: bool) -> void:
		data.arcade = on
		_dirty = true)
	row.add_child(_arcade)

	var buttons := HBoxContainer.new()
	side.add_child(buttons)
	_button(buttons, "Undo", _undo_step)
	_button(buttons, "Redo", _redo_step)
	_button(buttons, "Save", save)
	var drive := HBoxContainer.new()
	side.add_child(drive)
	var test := _button(drive, "Test drive", _test_drive)
	test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test.add_theme_color_override("font_color", Color(1.0, 0.42, 0.08))
	_button(drive, "Close", _close)

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = "Close without saving the changes?"
	_confirm.ok_button_text = "Close"
	_confirm.confirmed.connect(func() -> void: closed.emit())
	add_child(_confirm)


func _theme() -> Theme:
	var made := Theme.new()
	made.default_font_size = 15
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.13, 0.15, 0.19)
	flat.set_corner_radius_all(3)
	flat.set_content_margin_all(6)
	var lit := flat.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.2, 0.23, 0.29)
	var on := flat.duplicate() as StyleBoxFlat
	on.bg_color = Color(1.0, 0.42, 0.08)
	for kind in ["Button", "OptionButton"]:
		made.set_stylebox("normal", kind, flat)
		made.set_stylebox("hover", kind, lit)
		made.set_stylebox("pressed", kind, on)
		made.set_stylebox("hover_pressed", kind, on)
		made.set_color("font_pressed_color", kind, Color(0.02, 0.03, 0.07))
		made.set_color("font_hover_pressed_color", kind, Color(0.02, 0.03, 0.07))
	var field := flat.duplicate() as StyleBoxFlat
	field.bg_color = Color(0.04, 0.05, 0.07)
	made.set_stylebox("normal", "LineEdit", field)
	made.set_stylebox("panel", "ItemList", field)
	made.set_color("font_selected_color", "ItemList", Color(0.02, 0.03, 0.07))
	var chosen := flat.duplicate() as StyleBoxFlat
	chosen.bg_color = Color(1.0, 0.42, 0.08)
	made.set_stylebox("selected", "ItemList", chosen)
	made.set_stylebox("selected_focus", "ItemList", chosen)
	return made


func _padded(inside: Control, colour: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", box)
	panel.add_child(inside)
	return panel


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _check(parent: Control, text: String, on: bool, toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(toggled)
	parent.add_child(check)
	return check


func _button(parent: Control, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


func _field(parent: Control, text: String, control: Control) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	label.add_theme_font_size_override("font_size", 12)
	parent.add_child(label)
	parent.add_child(control)
	return control


func _note(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	parent.add_child(label)
	return label


func _list(parent: Control, icons: bool) -> ItemList:
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.focus_mode = Control.FOCUS_NONE
	if icons:
		list.max_columns = 0
		list.icon_mode = ItemList.ICON_MODE_TOP
		list.fixed_icon_size = Vector2i(THUMB, THUMB)
		list.fixed_column_width = THUMB + 8
		list.same_column_width = true
	parent.add_child(list)
	return list


# --- the palettes ------------------------------------------------------------

func _build_cells(palette: VBoxContainer) -> void:
	_note(palette, "Cells of the course. Those on the map come first.")
	_cell_list = _list(palette, true)
	_cell_list.item_selected.connect(func(index: int) -> void:
		chosen_cell = _cell_list.get_item_metadata(index))
	_button(palette, "Give the place a cell of its own", _own_cell)
	_note(palette, "A cell of its own is a copy that only that place shows: its ground codes can then be painted alone, and its picture (course/cells/NUMBER.png in the mod's folder) painted over in any paint program.")
	_fill_cells()


func _fill_cells() -> void:
	_cell_list.clear()
	var order: Array[int] = []
	var seen := {}
	for cell in data.map:
		if not seen.has(cell):
			seen[cell] = true
			order.append(cell)
	order.sort()
	var rest: Array[int] = []
	for cell in data.game_cells:
		if not seen.has(cell):
			rest.append(cell)
	order.append_array(rest)
	for cell in order:
		var index := _cell_list.add_item(str(cell), cell_texture(cell))
		_cell_list.set_item_metadata(index, cell)
		_cell_list.set_item_tooltip(index, "Cell %d, at %d places" % [cell, data.uses_of(cell)])
		if cell == chosen_cell:
			_cell_list.select(index)


func _build_ground(palette: VBoxContainer) -> void:
	_note(palette, "What a car finds on the ground. Gates are two strips, the first before the second; driving through both passes a checkpoint.")
	var row := HBoxContainer.new()
	palette.add_child(row)
	var label := Label.new()
	label.text = "Brush"
	row.add_child(label)
	for size: int in [1, 2, 4, 8]:
		var button := Button.new()
		button.text = "%d" % size
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = size == brush
		button.pressed.connect(func() -> void:
			brush = size
			for other in row.get_children():
				if other is Button:
					other.button_pressed = other == button)
		row.add_child(button)
	_code_list = _list(palette, false)
	_code_list.add_theme_font_size_override("font_size", 12)
	for code in 0x80:
		var swatch := Image.create_empty(14, 14, false, Image.FORMAT_RGB8)
		swatch.fill(ModCourses.code_colour(code))
		var index := _code_list.add_item("%3d  %s" % [code, ExportCourse.describe(machine, data.base, code)],
				ImageTexture.create_from_image(swatch))
		_code_list.set_item_metadata(index, code)
	_code_list.select(chosen_code)
	_code_list.item_selected.connect(func(index: int) -> void:
		chosen_code = _code_list.get_item_metadata(index))


func _build_scenery(palette: VBoxContainer) -> void:
	_note(palette, "Things to put beside the road. Those of this course come first.")
	_kind_list = _list(palette, true)
	var order: Array[int] = []
	var seen := {}
	for thing in data.scenery:
		if not seen.has(thing.z):
			seen[thing.z] = true
			order.append(thing.z)
	order.sort()
	for kind in range(1, data.scenery_kinds()):
		if not seen.has(kind):
			order.append(kind)
	for kind in order:
		var index := _kind_list.add_item(str(kind))
		_kind_list.set_item_metadata(index, kind)
		_waiting_kinds.append(kind)
	_kind_list.select(0)
	chosen_kind = order[0] if not order.is_empty() else 1
	_kind_list.item_selected.connect(func(index: int) -> void:
		chosen_kind = _kind_list.get_item_metadata(index))
	_note(palette, "Some things are other courses' and look right only in their colours.")


func _build_route(palette: VBoxContainer) -> void:
	_note(palette, "The other cars drive from box to box, in order, slowing to each box's speed on the way. A box is reached when a car is in it.")
	var grid := GridContainer.new()
	grid.columns = 2
	palette.add_child(grid)
	for name: String in ["x", "y", "Width", "Height", "Speed"]:
		var label := Label.new()
		label.text = name
		grid.add_child(label)
		var field := SpinBox.new()
		field.min_value = 0
		field.max_value = 0xFFFF
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var which := _point_fields.size()
		field.value_changed.connect(func(value: float) -> void:
			if _filling_fields or selected_point < 0:
				return
			_remember_now("waypoints")
			data.waypoints[selected_point][which] = int(value)
			_changed()
			_view.queue_redraw())
		grid.add_child(field)
		_point_fields.append(field)
	var buttons := HBoxContainer.new()
	palette.add_child(buttons)
	_button(buttons, "Earlier", _move_point.bind(-1))
	_button(buttons, "Later", _move_point.bind(1))
	_button(buttons, "Take away", _delete_point)
	_rivals = _field(palette, "The box each of the other cars starts for", LineEdit.new())
	_rivals.text_submitted.connect(_set_rivals.unbind(1))
	_rivals.focus_exited.connect(_set_rivals)
	palette.add_child(_spacer())


func _build_start(palette: VBoxContainer) -> void:
	_note(palette, "The car starts at the dot, facing the arrow; the other cars start beside it. The lines are what the bar at the side of the race measures: the start, each checkpoint and the finish. The checkpoints themselves are the gates on the ground.")
	_facing = _field(palette, "Facing, in degrees: 0 is right, 90 down the course, 270 up", SpinBox.new())
	_facing.min_value = 0
	_facing.max_value = 360
	_facing.step = 0.01
	_facing.value_changed.connect(func(value: float) -> void:
		if _filling_fields:
			return
		_remember_now("start")
		data.facing = value
		_changed()
		_view.queue_redraw())
	_progress = _field(palette, "y of the lines, from the start to the finish", LineEdit.new())
	_progress.text_submitted.connect(_set_progress.unbind(1))
	_progress.focus_exited.connect(_set_progress)
	palette.add_child(_spacer())


func _build_signs(palette: VBoxContainer) -> void:
	_note(palette, "A sign shows when the car comes into a place marked with it, and not again until it has been in a place with another.")
	_sign_list = _list(palette, false)
	for sign in SIGNS:
		var index := _sign_list.add_item("Sign %d" % sign if sign > 0 else "None")
		_sign_list.set_item_metadata(index, sign)
	_sign_list.select(chosen_sign)
	_sign_list.item_selected.connect(func(index: int) -> void:
		chosen_sign = _sign_list.get_item_metadata(index))


func _fill_settings() -> void:
	_filling_fields = true
	_name.text = data.name
	_time.text = ", ".join(data.time.map(func(value: Variant) -> String: return str(value)))
	_music.select(clampi(data.music, 0, ModCourses.COURSE_COUNT - 1))
	_arcade.button_pressed = data.arcade
	_facing.value = data.facing
	_progress.text = ", ".join(data.progress.map(func(value: Variant) -> String: return str(int(value))))
	_rivals.text = ", ".join(data.rivals_from.map(func(value: Variant) -> String: return str(int(value))))
	_fill_point()
	_filling_fields = false


func _fill_point() -> void:
	var was := _filling_fields
	_filling_fields = true
	for index in _point_fields.size():
		_point_fields[index].editable = selected_point >= 0
		_point_fields[index].value = data.waypoints[selected_point][index] if selected_point >= 0 else 0
	_filling_fields = was


func _numbers(text: String) -> Array:
	var values := []
	for part in text.replace(" ", ",").split(",", false):
		if part.is_valid_float():
			values.append(part.to_float())
	return values


func _set_time() -> void:
	var values := _numbers(_time.text)
	if not values.is_empty() and values != data.time:
		data.time = values
		_dirty = true
	_fill_settings()


func _set_progress() -> void:
	var values := _numbers(_progress.text).map(func(value: float) -> int: return int(value))
	if values.size() >= 2 and values != data.progress:
		_remember_now("progress")
		data.progress = values
		_changed()
	_fill_settings()
	_view.queue_redraw()


func _set_rivals() -> void:
	var values := _numbers(_rivals.text).map(func(value: float) -> int: return clampi(int(value), 0, 255))
	if not values.is_empty() and values != data.rivals_from:
		_remember_now("rivals")
		data.rivals_from = values
		_changed()
	_fill_settings()
	_view.queue_redraw()


func _choose_tool(chosen: int) -> void:
	tool = chosen
	for index in _palettes.size():
		_palettes[index].visible = index == chosen
		_tool_buttons[index].button_pressed = index == chosen
	_help.text = TOOL_HELP[chosen]
	if chosen == Tool.GROUND and not show_codes:
		show_codes = true
		_codes_check.button_pressed = true
	_view.queue_redraw()


# --- pictures ----------------------------------------------------------------

## The picture of a cell, or null while it is still to be drawn.
func cell_texture(cell: int) -> Texture2D:
	if _cell_textures.has(cell):
		return _cell_textures[cell]
	if data.painted.has(cell):
		_cell_textures[cell] = ImageTexture.create_from_image(data.painted[cell])
		return _cell_textures[cell]
	if not cell in _waiting_cells:
		_waiting_cells.append(cell)
	return null


func codes_texture(cell: int) -> Texture2D:
	if not _code_textures.has(cell):
		_code_textures[cell] = ImageTexture.create_from_image(data.codes_image(cell))
	return _code_textures[cell]


func kind_texture(kind: int) -> Texture2D:
	if not _kind_textures.has(kind):
		var image := data.scenery_picture(kind)
		_kind_sizes[kind] = image.get_size()
		_kind_textures[kind] = ImageTexture.create_from_image(image)
	return _kind_textures[kind]


## Where a thing's picture is drawn on the course: its offsets are those
## the game places it with (game/scenery.gd).
func thing_rect(thing: Vector3i) -> Rect2:
	if not _kind_sizes.has(thing.z):
		kind_texture(thing.z)
	var offset: Vector2i = _offsets.get(thing.z, Vector2i(16, 40))
	return Rect2(Vector2(thing.x - offset.x, thing.y - offset.y), _kind_sizes[thing.z])


func _set_up_offsets() -> void:
	for table: Dictionary in [Scenery.STANDING, Scenery.FLUTTERING, Scenery.SWAYING]:
		for address: int in table:
			var kind: Array = table[address]
			_offsets[kind[-1]] = Vector2i(kind[0], kind[1])
	for address: int in Scenery.KNOCKED_OVER:
		_offsets[Scenery.KNOCKED_OVER[address][0]] = Vector2i(Scenery.KNOCKED_OFFSET_X, Scenery.KNOCKED_OFFSET_Y)
	for address: int in Scenery.CROSSING:
		_offsets[Scenery.CROSSING[address][0]] = Vector2i(Scenery.CROSSING_OFFSET_X, Scenery.LIFT_LEAST)


func _process(_delta: float) -> void:
	if data == null:
		return
	var started := Time.get_ticks_msec()
	var drawn := false
	while not _waiting_cells.is_empty() and Time.get_ticks_msec() - started < DRAW_BUDGET_MSEC:
		var cell: int = _waiting_cells.pop_front()
		_cell_textures[cell] = ImageTexture.create_from_image(data.cell_picture(cell))
		drawn = true
	if drawn:
		_view.queue_redraw()
		_refresh_icons(_cell_list, _cell_textures)
	while not _waiting_kinds.is_empty() and Time.get_ticks_msec() - started < DRAW_BUDGET_MSEC:
		var kind: int = _waiting_kinds.pop_front()
		kind_texture(kind)
		drawn = true
	if drawn:
		_refresh_icons(_kind_list, _kind_textures)
	if _waiting_cells.is_empty() and _cell_list != null and _cell_list.item_count > 0:
		# the rest of the cells, for the palette
		for index in _cell_list.item_count:
			if _cell_list.get_item_icon(index) == null:
				cell_texture(_cell_list.get_item_metadata(index))
				break


func _refresh_icons(list: ItemList, textures: Dictionary) -> void:
	if list == null:
		return
	for index in list.item_count:
		if list.get_item_icon(index) == null and textures.has(list.get_item_metadata(index)):
			list.set_item_icon(index, textures[list.get_item_metadata(index)])


# --- the mouse on the course -------------------------------------------------

func view_pressed(at: Vector2i, button: int, event: InputEventMouseButton) -> void:
	_step = {}
	var place := data.place_at(at)
	_last_place = place
	match tool:
		Tool.CELLS:
			if button == MOUSE_BUTTON_LEFT:
				_put_cell(place)
			elif button == MOUSE_BUTTON_RIGHT:
				_choose_in(_cell_list, data.map[place])
				chosen_cell = data.map[place]
		Tool.GROUND:
			if button == MOUSE_BUTTON_LEFT:
				_paint_codes(at)
			elif button == MOUSE_BUTTON_RIGHT:
				var code := _code_at(at)
				chosen_code = code
				_choose_in(_code_list, code)
		Tool.SCENERY:
			var found := _thing_at(at)
			if button == MOUSE_BUTTON_LEFT:
				_remember("scenery")
				if found < 0:
					data.scenery.append(Vector3i(at.x, at.y, chosen_kind))
					found = data.scenery.size() - 1
					_changed()
				else:
					chosen_kind = data.scenery[found].z
					_choose_in(_kind_list, chosen_kind)
				selected_thing = found
				_dragging = "thing"
				_grab = at - Vector2i(data.scenery[found].x, data.scenery[found].y)
			elif button == MOUSE_BUTTON_RIGHT and found >= 0:
				_remember("scenery")
				data.scenery.remove_at(found)
				selected_thing = -1
				_changed()
		Tool.ROUTE:
			_press_route(at, button)
		Tool.START:
			if button != MOUSE_BUTTON_LEFT:
				return
			var line := _line_at(at)
			if line >= 0 and not event.shift_pressed:
				selected_line = line
				_dragging = "line"
				_remember("progress")
				return
			_remember("start")
			if event.shift_pressed:
				_face_towards(at)
			else:
				data.start = at
				_dragging = "start"
			_changed()
		Tool.SIGNS:
			if button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT:
				_remember("signs")
				data.signs[place] = chosen_sign if button == MOUSE_BUTTON_LEFT else 0
				_changed()


func view_moved(at: Vector2i, buttons: int, event: InputEventMouseMotion) -> void:
	var place := data.place_at(at)
	_show_status(at)
	if buttons & MOUSE_BUTTON_MASK_LEFT == 0:
		return
	match tool:
		Tool.CELLS:
			if place != _last_place:
				_last_place = place
				_put_cell(place)
		Tool.GROUND:
			_paint_codes(at)
		Tool.SCENERY:
			if _dragging == "thing" and selected_thing >= 0:
				var moved := at - _grab
				data.scenery[selected_thing] = Vector3i(moved.x, maxi(moved.y, 0), data.scenery[selected_thing].z)
				_changed()
		Tool.ROUTE:
			_drag_route(at)
		Tool.START:
			if _dragging == "line" and selected_line >= 0:
				data.progress[selected_line] = clampi(at.y, 0, data.down * CourseData.CELL - 1)
				_changed()
			elif _dragging == "start":
				if event.shift_pressed:
					_face_towards(at)
				else:
					data.start = at
				_changed()
		Tool.SIGNS:
			if place != _last_place:
				_last_place = place
				_remember("signs")
				data.signs[place] = chosen_sign
				_changed()


func view_released(_at: Vector2i, _button: int) -> void:
	_dragging = ""
	if not _step.is_empty():
		_undo.append(_step)
		if _undo.size() > UNDO_STEPS:
			_undo.pop_front()
		_redo.clear()
	_step = {}
	_fill_settings()


## Ctrl and the wheel: the next or the one before in the palette.
func view_wheel(way: int) -> void:
	var list: ItemList = [_cell_list, _code_list, _kind_list, null, null, _sign_list][tool]
	if list == null or list.item_count == 0:
		return
	var at := list.get_selected_items()[0] if list.is_anything_selected() else 0
	at = clampi(at + way, 0, list.item_count - 1)
	list.select(at)
	list.ensure_current_is_visible()
	list.item_selected.emit(at)


func _show_status(at: Vector2i) -> void:
	var place := data.place_at(at)
	var cell := data.map[place]
	_status.text = "x %d  y %d    place %d (column %d, row %d)    cell %d, at %d places    code %d    %s" % [
		posmod(at.x, data.across * CourseData.CELL), at.y, place, place % data.across, place / data.across,
		cell, data.uses_of(cell), _code_at(at), "unsaved changes" if _dirty else "saved"]


func _choose_in(list: ItemList, value: int) -> void:
	for index in list.item_count:
		if list.get_item_metadata(index) == value:
			list.select(index)
			list.ensure_current_is_visible()
			return


func _put_cell(place: int) -> void:
	if data.map[place] == chosen_cell:
		return
	_remember("map")
	_remember("scenery")
	var corner := data.place_corner(place)
	var kept: Array[Vector3i] = []
	for thing in data.scenery:
		if thing.x >> 8 != corner.x >> 8 or thing.y >> 8 != corner.y >> 8:
			kept.append(thing)
	kept.append_array(data.cell_scenery_at(chosen_cell, place))
	data.scenery = kept
	selected_thing = -1
	data.map[place] = chosen_cell
	_changed()


func _own_cell() -> void:
	if _last_place < 0:
		_help.text = "Click a place on the map first."
		return
	_step = {}
	_remember("map")
	_remember("painted")
	var cell := data.free_cell()
	_remember("codes:%d" % cell)
	data.make_own_cell(_last_place)
	_cell_textures.erase(cell)
	_code_textures.erase(cell)
	_changed_codes[cell] = true
	_changed()
	view_released(Vector2i.ZERO, 0)
	chosen_cell = cell
	_fill_cells()
	_help.text = "Place %d has cell %d of its own now. Its picture is saved as course/cells/%d.png." % [_last_place, cell, cell]


func _code_at(at: Vector2i) -> int:
	var cell := data.map[data.place_at(at)]
	var codes: PackedByteArray = data.codes.get(cell, PackedByteArray())
	var index := (posmod(at.y, CourseData.CELL) >> 3) * CourseData.CODES + (posmod(at.x, CourseData.CELL) >> 3)
	return codes[index] if index < codes.size() else 0


func _paint_codes(at: Vector2i) -> void:
	var first := Vector2i(floori(at.x / 8.0) - brush / 2, floori(at.y / 8.0) - brush / 2)
	for down in brush:
		for across in brush:
			var spot := (first + Vector2i(across, down)) * 8
			if spot.y < 0 or spot.y >= data.down * CourseData.CELL:
				continue
			var cell := data.map[data.place_at(spot)]
			var key := "codes:%d" % cell
			_remember(key)
			var codes: PackedByteArray = data.codes.get(cell, PackedByteArray())
			if codes.is_empty():
				codes.resize(CourseData.CODES * CourseData.CODES)
			var index := (posmod(spot.y, CourseData.CELL) >> 3) * CourseData.CODES + (posmod(spot.x, CourseData.CELL) >> 3)
			if codes[index] == chosen_code:
				continue
			codes[index] = chosen_code
			data.codes[cell] = codes
			_changed_codes[cell] = true
			_code_textures.erase(cell)
			_changed()


func _thing_at(at: Vector2i) -> int:
	var best := -1
	var width := data.across * CourseData.CELL
	for index in data.scenery.size():
		var rect := thing_rect(data.scenery[index])
		for shift: int in [-width, 0, width]:
			if Rect2(rect.position + Vector2(shift, 0), rect.size).has_point(Vector2(at)):
				if best < 0 or data.scenery[index].y > data.scenery[best].y:
					best = index
	return best


func _press_route(at: Vector2i, button: int) -> void:
	var found := -1
	for index in data.waypoints.size():
		var point := data.waypoints[index]
		if absi(at.x - point[0]) <= point[2] / 2 and absi(at.y - point[1]) <= point[3] / 2:
			found = index
	if button == MOUSE_BUTTON_RIGHT:
		if found >= 0:
			selected_point = found
			_delete_point()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	_remember("waypoints")
	if selected_point >= 0:
		var chosen := data.waypoints[selected_point]
		var corner := Vector2i(chosen[0] + chosen[2] / 2, chosen[1] + chosen[3] / 2)
		if (Vector2(at - corner) * _view.zoom).length() <= 8.0:
			_dragging = "corner"
			return
	if found < 0:
		var speed := data.waypoints[selected_point][4] if selected_point >= 0 else 2000
		var point := PackedInt32Array([at.x, at.y, NEW_BOX.x, NEW_BOX.y, speed])
		found = selected_point + 1 if selected_point >= 0 else data.waypoints.size()
		data.waypoints.insert(found, point)
		_changed()
	selected_point = found
	_dragging = "point"
	_grab = at - Vector2i(data.waypoints[found][0], data.waypoints[found][1])
	_fill_point()


func _drag_route(at: Vector2i) -> void:
	if selected_point < 0:
		return
	var point := data.waypoints[selected_point]
	if _dragging == "corner":
		point[2] = maxi(absi(at.x - point[0]) * 2, 16)
		point[3] = maxi(absi(at.y - point[1]) * 2, 16)
	elif _dragging == "point":
		point[0] = at.x - _grab.x
		point[1] = at.y - _grab.y
	else:
		return
	data.waypoints[selected_point] = point
	_changed()
	_fill_point()


func _move_point(way: int) -> void:
	var to := selected_point + way
	if selected_point < 0 or to < 0 or to >= data.waypoints.size():
		return
	_remember_now("waypoints")
	var point := data.waypoints[selected_point]
	data.waypoints.remove_at(selected_point)
	data.waypoints.insert(to, point)
	selected_point = to
	_changed()
	_fill_point()


func _delete_point() -> void:
	if selected_point < 0 or data.waypoints.size() <= 2:
		return
	_remember_now("waypoints")
	data.waypoints.remove_at(selected_point)
	selected_point = mini(selected_point, data.waypoints.size() - 1)
	_changed()
	_fill_point()


func _line_at(at: Vector2i) -> int:
	for index in data.progress.size():
		if absf((at.y - int(data.progress[index])) * _view.zoom) <= 6.0:
			return index
	return -1


func _face_towards(at: Vector2i) -> void:
	var way := Vector2(at - data.start)
	if way.length() < 1.0:
		return
	data.facing = snappedf(fposmod(rad_to_deg(way.angle()), 360.0), 0.01)
	_fill_settings()


# --- keeping and undoing -----------------------------------------------------

func _changed() -> void:
	_dirty = true
	_view.queue_redraw()


func _value_of(key: String) -> Variant:
	if key.begins_with("codes:"):
		var cell := key.trim_prefix("codes:").to_int()
		return (data.codes[cell] as PackedByteArray).duplicate() if data.codes.has(cell) else null
	match key:
		"map": return data.map.duplicate()
		"signs": return data.signs.duplicate()
		"scenery": return data.scenery.duplicate()
		"waypoints":
			var copy: Array[PackedInt32Array] = []
			for point in data.waypoints:
				copy.append(point.duplicate())
			return copy
		"start": return [data.start, data.facing]
		"progress": return data.progress.duplicate()
		"rivals": return data.rivals_from.duplicate()
		"painted": return data.painted.duplicate()
	return null


func _set_value(key: String, value: Variant) -> void:
	if key.begins_with("codes:"):
		var cell := key.trim_prefix("codes:").to_int()
		if value == null:
			data.codes.erase(cell)
		else:
			data.codes[cell] = value
		_changed_codes[cell] = true
		_code_textures.erase(cell)
		return
	match key:
		"map": data.map = value
		"signs": data.signs = value
		"scenery": data.scenery = value
		"waypoints": data.waypoints = value
		"start":
			data.start = value[0]
			data.facing = value[1]
		"progress": data.progress = value
		"rivals": data.rivals_from = value
		"painted":
			data.painted = value
			_cell_textures.clear()


## Keeps what `key` is before the step being made changes it.
func _remember(key: String) -> void:
	if not _step.has(key):
		_step[key] = _value_of(key)


## The same for a change made at once, outside a drag.
func _remember_now(key: String) -> void:
	_step = {}
	_remember(key)
	_undo.append(_step)
	_redo.clear()
	_step = {}


func _undo_step() -> void:
	_swap(_undo, _redo)


func _redo_step() -> void:
	_swap(_redo, _undo)


func _swap(from: Array[Dictionary], to: Array[Dictionary]) -> void:
	if from.is_empty():
		return
	var step: Dictionary = from.pop_back()
	var back := {}
	for key: String in step:
		back[key] = _value_of(key)
		_set_value(key, step[key])
	to.append(back)
	selected_thing = -1
	selected_point = mini(selected_point, data.waypoints.size() - 1)
	_dirty = true
	if step.has("map") or step.has("painted"):
		_fill_cells()
	_fill_settings()
	_view.queue_redraw()


func save() -> void:
	_set_time()
	data.save(folder, _changed_codes)
	_changed_codes.clear()
	_dirty = false
	_help.text = "Saved to %s." % folder


func _test_drive() -> void:
	save()
	test_drive.emit(folder.get_file(), data.base)


func _close() -> void:
	if _dirty:
		_confirm.popup_centered()
	else:
		closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var handled := true
	if key.ctrl_pressed and key.keycode == KEY_Z:
		_redo_step() if key.shift_pressed else _undo_step()
	elif key.ctrl_pressed and key.keycode == KEY_Y:
		_redo_step()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		save()
	elif key.keycode >= KEY_1 and key.keycode < KEY_1 + TOOL_NAMES.size():
		_choose_tool(key.keycode - KEY_1)
	elif key.keycode == KEY_G:
		_codes_check.button_pressed = not show_codes
	elif key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
		if tool == Tool.SCENERY and selected_thing >= 0:
			_remember_now("scenery")
			data.scenery.remove_at(selected_thing)
			selected_thing = -1
			_changed()
		elif tool == Tool.ROUTE:
			_delete_point()
	elif key.keycode == KEY_ESCAPE:
		_close()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()
