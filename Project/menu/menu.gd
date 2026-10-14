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
##
## The look: the game's picture dimmed behind a dark slanted panel with
## streaks going by (menu_backdrop.gdshader), the page's name large over
## its rows, and the rows slanted bars that slide out and light up when
## chosen (menu_row.gdshader). A bar along the bottom says what the chosen
## row is for and which keys do what.

signal arcade_chosen
## A stage chosen to drive on its own: 0 for the practice stage.
signal stage_chosen(stage: int)
## A course of a mod's (mods/mod_courses.gd), made from course `stage`.
signal course_chosen(mod: String, stage: int)
signal resumed
signal main_menu_chosen
signal quit_chosen
## A setting of this section of Settings.KEPT (or "controls") was changed.
signal changed(section: String)
## The course editor, on the course of the mod at `path`, or with `path`
## empty on a new course made from the game's course `base`.
signal editor_chosen(path: String, base: int)
## A page has been left for the one before it.
signal page_left(page: String)

const BACKDROP_SHADER := preload("res://menu/menu_backdrop.gdshader")
const TITLE_SHADER := preload("res://menu/menu_title.gdshader")
const ROW_SHADER := preload("res://menu/menu_row.gdshader")

const STAGES := 7
const INK := Color(0.02, 0.03, 0.07)
const TEXT := Color(0.94, 0.95, 0.98)
const FAINT := Color(0.94, 0.95, 0.98, 0.5)
const ACCENT := Color(1.0, 0.42, 0.08)
const SECOND := Color(0.16, 0.89, 1.0)
## Sizes in hundredths of the window's height.
const HERO_SIZE := 11.5
const TITLE_SIZE := 8.0
const CRUMB_SIZE := 2.1
const TEXT_SIZE := 3.0
const SMALL_SIZE := 2.1
const ROW_HEIGHT := 5.4
## The rows of the main menu and the pause menu, which are few.
const BIG_ROW_HEIGHT := 7.2
const BIG_TEXT_SIZE := 3.9
const ROW_GAP := 0.9
const FOOTER := 7.0
const LEFT := 7.0
## How far across a row leans for each step up, and the panel's edge.
const ROW_SLANT := 0.32
const PANEL_SLANT := 0.18
## The steps of a volume.
const VOLUME_STEPS := 10
## How long things take, in seconds.
const APPEAR_TIME := 0.45
const SLIDE_TIME := 0.32
const STAGGER := 0.035
const CHOOSE_TIME := 0.12
## How far a chosen row slides out, in hundredths of the height.
const CHOSEN_SHIFT := 1.6

## What each page is called where the way to it is shown.
const ModCourses := preload("res://mods/mod_courses.gd")

const PAGE_NAMES := {
	"main": "Main menu", "pause": "Paused", "freeplay": "Freeplay", "options": "Options",
	"picture": "Picture", "sound": "Sound", "controls": "Controls", "game": "Game",
	"mods": "Mods", "editor": "Course editor",
}
## What a row is for, by its name.
const ABOUT := {
	"Arcade": "The whole game: every stage in turn, against the clock.",
	"Freeplay": "Any one stage, on its own.",
	"Options": "Picture, sound, controls and the game.",
	"Mods": "Turn on and off what has been added to the game.",
	"Course editor": "Make courses of your own, and change those made before.",
	"Quit to desktop": "Close the game.",
	"Resume": "Back to the race.",
	"Quit to main menu": "Leave this game for the main menu.",
	"Practice stage": "The practice course, to get to know the car.",
	"Picture": "Window, scaling, wide picture and the CRT.",
	"Sound": "How loud the music and the effects are.",
	"Controls": "Keys and gamepad buttons.",
	"Game": "HUD, map and continues.",
	"Full screen": "The whole screen, or a window.",
	"Window size": "The size of the window when not full screen.",
	"V-Sync": "Waits for the display between frames, so the picture does not tear.",
	"Wide picture": "Shows more of the course at the sides on a wide screen.",
	"Whole-number scaling": "Scales by whole numbers only, so every pixel is the same size.",
	"CRT": "Curved glass, scanlines and a shadow mask, as on an arcade monitor.",
	"CRT curvature": "How much the CRT's glass curves.",
	"Transparent shadows": "Shadows drawn see-through, instead of flickering as on the original.",
	"Volume": "Everything together.",
	"Music": "The music alone.",
	"Effects": "Engines, tyres and the rest.",
	"HUD": "New is drawn at the window's resolution, Original is the game's own.",
	"Map of the course": "A map of the course during a race.",
	"Free continues": "Continue without putting in another coin.",
	"Back": "Back to the page before.",
}

var settings: Settings

## The pages open, the one shown last, as [name, the row that had the focus].
var _pages: Array = []
var _unit := 8.0
var _backdrop: ColorRect
var _backdrop_material: ShaderMaterial
var _crumb: Label
var _title: Label
var _title_material: ShaderMaterial
var _tag: Label
## The page's name again, huge and only outlined, low on the panel.
var _watermark: Label
var _watermark_clip: Control
var _list: Control
var _about: Label
var _keys: Label
## What the bar at the bottom says while no row says more.
var _page_about := ""
var _font: FontVariation
var _heavy_font: FontVariation
var _spaced_font: FontVariation
## Where the next row goes, and how wide rows are, in pixels.
var _next_y := 0.0
var _row_width := 0.0
var _row_number := 0
var _row_height := ROW_HEIGHT
var _text_size := TEXT_SIZE
## The rows of the page in the order they slide in.
var _arrivals: Array[Control] = []
var _appearing: Tween
var _panel_moving: Tween
## The control and place a key or button is awaited for, and its button.
var _awaited_action := ""
var _awaited_place := 0
var _awaited_button: Button


func _ready() -> void:
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.6
	_heavy_font = FontVariation.new()
	_heavy_font.base_font = ThemeDB.fallback_font
	_heavy_font.variation_embolden = 1.5
	_heavy_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.24, 1.0), Vector2.ZERO)
	_spaced_font = FontVariation.new()
	_spaced_font.base_font = ThemeDB.fallback_font
	_spaced_font.variation_embolden = 0.7
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop_material = ShaderMaterial.new()
	_backdrop_material.shader = BACKDROP_SHADER
	_backdrop_material.set_shader_parameter("accent", ACCENT)
	_backdrop_material.set_shader_parameter("second", SECOND)
	_backdrop_material.set_shader_parameter("ink", INK)
	_backdrop_material.set_shader_parameter("slant", PANEL_SLANT)
	_backdrop_material.set_shader_parameter("panel", 0.0)
	_backdrop.material = _backdrop_material
	add_child(_backdrop)
	_watermark_clip = Control.new()
	_watermark_clip.clip_contents = true
	_watermark_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_watermark_clip)
	_watermark = Label.new()
	_watermark.uppercase = true
	_watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watermark_clip.add_child(_watermark)
	_crumb = Label.new()
	_crumb.uppercase = true
	add_child(_crumb)
	_title = Label.new()
	_title.uppercase = true
	_title_material = ShaderMaterial.new()
	_title_material.shader = TITLE_SHADER
	_title.material = _title_material
	add_child(_title)
	_tag = Label.new()
	_tag.uppercase = true
	add_child(_tag)
	_list = Control.new()
	add_child(_list)
	_about = Label.new()
	_about.clip_text = true
	add_child(_about)
	_keys = Label.new()
	_keys.uppercase = true
	_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_keys)
	for label: Label in [_crumb, _title, _tag, _about, _keys]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_fit)
	visible = false


## Shows the menu with `page` alone open: "main" or "pause" (or any other,
## which then has nowhere to go back to).
func open(page: String) -> void:
	_pages = []
	_backdrop_material.set_shader_parameter("cover", 0.0)
	_come_on()
	_fit()
	_pages = [[page, 0]]
	_show()


## Shows nothing but `text` (a stage's name, or nothing for the whole game)
## on the backdrop alone, for while a game is got ready.
func cover(text: String) -> void:
	_pages = []
	_stop_awaiting()
	_backdrop_material.set_shader_parameter("cover", 1.0)
	_come_on()
	_fit()
	_clear_rows()
	_crumb.text = "Starting"
	_title.text = text if text != "" else "Arcade"
	_tag.visible = false
	_place_header(false)
	_page_about = "Getting the board ready"
	_about.text = _page_about
	_keys.text = ""
	_row_width = 40.0 * _unit
	var bar := Segments.new()
	bar.steps = 16
	bar.running = true
	bar.lit = ACCENT
	_add(bar, 1.6)
	_watermark_clip.size = Vector2(_left() + _row_width + 4.0 * _unit, size.y - FOOTER * _unit)
	_move_panel(true)
	_slide_in(true)


func close() -> void:
	_pages = []
	_stop_awaiting()
	visible = false


func is_open() -> bool:
	return visible and not _pages.is_empty()


## The backdrop sweeps in, unless the menu is already on.
func _come_on() -> void:
	if visible:
		return
	visible = true
	if _appearing != null:
		_appearing.kill()
	_backdrop_material.set_shader_parameter("appear", 0.0)
	_appearing = create_tween()
	_appearing.tween_method(func(value: float) -> void:
		_backdrop_material.set_shader_parameter("appear", value), 0.0, 1.0, APPEAR_TIME)


func _fit() -> void:
	_unit = maxf(size.y, 200.0) / 100.0
	_font.spacing_glyph = roundi(0.06 * _unit)
	_spaced_font.spacing_glyph = roundi(0.45 * _unit)
	_backdrop_material.set_shader_parameter("size", size)
	_backdrop_material.set_shader_parameter("footer", FOOTER * _unit)
	_style_label(_crumb, _spaced_font, CRUMB_SIZE, SECOND)
	_style_label(_about, _font, SMALL_SIZE * 1.1, TEXT)
	_style_label(_keys, _spaced_font, SMALL_SIZE * 0.9, FAINT)
	_style_label(_tag, _spaced_font, SMALL_SIZE, INK)
	var tag_box := StyleBoxFlat.new()
	tag_box.bg_color = ACCENT
	tag_box.skew = Vector2(0.3, 0.0)
	tag_box.content_margin_left = 1.6 * _unit
	tag_box.content_margin_right = 1.4 * _unit
	tag_box.content_margin_top = 0.2 * _unit
	tag_box.content_margin_bottom = 0.2 * _unit
	_tag.add_theme_stylebox_override("normal", tag_box)
	var footer_top := size.y - FOOTER * _unit
	_about.position = Vector2(_left(), footer_top + 1.6 * _unit)
	_about.size = Vector2(size.x * 0.55 - _left(), 4.0 * _unit)
	_keys.position = Vector2(size.x * 0.55, footer_top + 1.9 * _unit)
	_keys.size = Vector2(size.x * 0.45 - _left() * 0.6, 4.0 * _unit)
	if not _pages.is_empty():
		_pages[-1][1] = _focused_row()
		_show(false)


func _left() -> float:
	return maxf(LEFT * _unit, size.x * 0.05)


func _style_label(label: Label, font: Font, text_size: float, colour: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", int(text_size * _unit))
	label.add_theme_color_override("font_color", colour)


# --- pages -------------------------------------------------------------------

## Builds the page on top. `arriving`: it slides in.
func _show(arriving := true) -> void:
	_stop_awaiting()
	_clear_rows()
	var page: String = _pages[-1][0]
	var width := 50.0
	var keys := "↑↓  Choose      Enter  OK      Esc  Back"
	var changing := "↑↓  Choose      ←→  Change      Esc  Back"
	_page_about = ""
	_tag.visible = false
	var big := page == "main" or page == "pause"
	_row_height = BIG_ROW_HEIGHT if big else ROW_HEIGHT
	_text_size = BIG_TEXT_SIZE if big else TEXT_SIZE
	if big:
		width = 58.0
	match page:
		"main":
			_title.text = "Neo Drift Out"
			_tag.text = "Enhanced"
			_tag.visible = true
			keys = "↑↓  Choose      Enter  OK"
			_item("Arcade", func() -> void: arcade_chosen.emit())
			_item("Freeplay", go.bind("freeplay"))
			_item("Options", go.bind("options"))
			_item("Mods", go.bind("mods"))
			_item("Course editor", go.bind("editor"))
			_item("Quit to desktop", func() -> void: quit_chosen.emit())
		"editor":
			_title.text = "Course editor"
			_page_about = "Courses are kept as mods, in %s." % ProjectSettings.globalize_path("user://mods")
			for mod in Mods.find_all():
				if ModCourses.is_course(mod):
					var button := _item("Change: " + ModCourses.name_of(mod),
							func() -> void: editor_chosen.emit(mod.path, ModCourses.base_of(mod)))
					button.set_meta("about", "The course of the mod %s, in %s." % [mod.name, mod.path])
			for stage in STAGES:
				var button := _item("New, from the practice stage" if stage == 0 else "New, from stage %d" % stage,
						func() -> void: editor_chosen.emit("", stage))
				button.set_meta("about", "A new course, a copy of %s to start from." %
						("the practice stage" if stage == 0 else "stage %d" % stage))
			_item("Back", _back)
		"pause":
			_title.text = "Paused"
			keys = "↑↓  Choose      Enter  OK      Esc  Resume"
			_item("Resume", func() -> void: resumed.emit())
			_item("Options", go.bind("options"))
			_item("Quit to main menu", func() -> void: main_menu_chosen.emit())
			_item("Quit to desktop", func() -> void: quit_chosen.emit())
		"freeplay":
			_title.text = "Freeplay"
			for stage in STAGES:
				var button := _item("Practice stage" if stage == 0 else "Stage %d" % stage,
						func() -> void: stage_chosen.emit(stage))
				if stage > 0:
					button.set_meta("about", "Stage %d on its own." % stage)
			for mod in Mods.enabled(settings.mods_off):
				if ModCourses.is_course(mod):
					var base := ModCourses.base_of(mod)
					var button := _item(ModCourses.name_of(mod), func() -> void: course_chosen.emit(mod.id, base))
					button.set_meta("about", mod.description if mod.description != "" else "A course of the mod %s." % mod.name)
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
			width = 74.0
			keys = changing
			_switch("Full screen", "picture", "full_screen")
			_window_size()
			_switch("V-Sync", "picture", "vsync")
			_switch("Wide picture", "picture", "wide")
			_switch("Whole-number scaling", "picture", "whole_pixels")
			_switch("CRT", "picture", "crt")
			_volume("CRT curvature", "crt_curve", "picture")
			_switch("Transparent shadows", "picture", "translucency")
			_item("Back", _back)
		"sound":
			_title.text = "Sound"
			width = 74.0
			keys = changing
			_volume("Volume", "volume")
			_volume("Music", "music")
			_volume("Effects", "effects")
			_item("Back", _back)
		"game":
			_title.text = "Game"
			width = 74.0
			keys = changing
			_choice("HUD", "game", "hud", Settings.HUD_NAMES)
			_switch("Map of the course", "game", "map")
			_switch("Free continues", "game", "free_continues")
			_item("Back", _back)
		"mods":
			_title.text = "Mods"
			width = 74.0
			keys = changing
			_mods()
			_item("Back", _back)
		"controls":
			_title.text = "Controls"
			keys = "Enter  Change      Delete  Empty      Esc  Back"
			_page_about = "Choose a place, then press what it should be. Esc leaves it as it is."
	var names: Array[String] = []
	for open_page: Array in _pages:
		names.append(PAGE_NAMES.get(open_page[0], open_page[0]))
	_crumb.text = "   /   ".join(names)
	_keys.text = keys
	_about.text = _page_about
	_place_header(page == "main")
	if page == "controls":
		_row_width = minf(112.0 * _unit, size.x - _left() * 1.5)
		_controls()
	else:
		_row_width = minf(width * _unit, size.x - _left() * 2.0)
		for row in _list.get_children():
			(row as Control).size.x = _row_width
		_wrap_focus()
	_move_panel(arriving)
	_slide_in(arriving)
	_focus_row(_pages[-1][1])
	_watermark_clip.size = Vector2(_left() + _row_width + 4.0 * _unit, size.y - FOOTER * _unit)


## The way to the page, its name, and where its rows start.
func _place_header(hero: bool) -> void:
	var left := _left()
	_title.add_theme_font_override("font", _heavy_font)
	_title.add_theme_font_size_override("font_size", int((HERO_SIZE if hero else TITLE_SIZE) * _unit))
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", int(0.5 * _unit))
	_title.add_theme_constant_override("shadow_offset_y", int(0.5 * _unit))
	_crumb.position = Vector2(left + 0.4 * _unit, 8.0 * _unit)
	_crumb.size = Vector2(size.x - left * 2.0, 3.0 * _unit)
	_title.position = Vector2(left - 0.4 * _unit, 9.5 * _unit)
	_title.size = _title.get_minimum_size()
	_title_material.set_shader_parameter("box", _title.size)
	_title_material.set_shader_parameter("bottom", ACCENT.lerp(Color.WHITE, 0.35))
	if _tag.visible:
		_tag.size = _tag.get_minimum_size()
		_tag.position = Vector2(_title.position.x + _title.size.x + 1.2 * _unit,
				_title.position.y + _title.size.y * 0.72 - _tag.size.y)
	_list.position = Vector2(left, _title.position.y + _title.size.y + 3.0 * _unit)
	_watermark.text = _title.text
	_watermark.add_theme_font_override("font", _heavy_font)
	_watermark.add_theme_font_size_override("font_size", int(26.0 * _unit))
	_watermark.add_theme_color_override("font_color", Color(1, 1, 1, 0.0))
	_watermark.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.07))
	_watermark.add_theme_constant_override("outline_size", maxi(int(0.35 * _unit), 2))
	_watermark.size = _watermark.get_minimum_size()
	_watermark.position = Vector2(left * 0.4, size.y - FOOTER * _unit - _watermark.size.y * 0.8)
	_next_y = 0.0
	_row_number = 0


## The panel's edge moves to just right of the rows.
func _move_panel(arriving: bool) -> void:
	var edge := _left() + _row_width + 7.0 * _unit
	if _panel_moving != null:
		_panel_moving.kill()
	if not arriving:
		_backdrop_material.set_shader_parameter("panel", edge)
		return
	_panel_moving = create_tween()
	_panel_moving.tween_method(func(value: float) -> void:
		_backdrop_material.set_shader_parameter("panel", value),
		float(_backdrop_material.get_shader_parameter("panel")), edge, SLIDE_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


## The header and then the rows one after the other slide in from the left.
func _slide_in(arriving: bool) -> void:
	if not arriving:
		return
	var from := -6.0 * _unit
	var things: Array[Control] = [_watermark, _crumb, _title]
	if _tag.visible:
		things.append(_tag)
	things.append_array(_arrivals)
	var delay := 0.0
	for thing in things:
		if thing.has_meta("sliding"):
			(thing.get_meta("sliding") as Tween).kill()
		thing.set_meta("home", thing.position.x - float(thing.get_meta("shift", 0.0)))
		_offset(from, thing, "slide")
		thing.modulate.a = 0.0
		var tween := thing.create_tween().set_parallel()
		thing.set_meta("sliding", tween)
		tween.tween_method(_offset.bind(thing, "slide"), from, 0.0, SLIDE_TIME).set_delay(delay) \
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(thing, "modulate:a", 1.0, SLIDE_TIME * 0.6).set_delay(delay)
		delay += STAGGER


## A row is where it slides in from and, when chosen, out to, at once: its
## "home" with its "slide" and its "shift" added.
func _offset(value: float, thing: Control, part: String) -> void:
	thing.set_meta(part, value)
	thing.position.x = float(thing.get_meta("home", 0.0)) + float(thing.get_meta("slide", 0.0)) \
			+ float(thing.get_meta("shift", 0.0))


func _clear_rows() -> void:
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()
	_arrivals.clear()


## Puts `page` on top of the one shown.
func go(page: String) -> void:
	_pages[-1][1] = _focused_row()
	_pages.append([page, 0])
	_show()


func _back() -> void:
	if _pages.size() > 1:
		var left: String = _pages.pop_back()[0]
		_show()
		page_left.emit(left)
	elif not _pages.is_empty() and _pages[0][0] == "pause":
		resumed.emit()


## The buttons of the page, in the order the focus is remembered by.
func _buttons() -> Array[Node]:
	return _list.find_children("*", "Button", true, false)


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


## Up from the first row is the last, and down from the last the first.
func _wrap_focus() -> void:
	var buttons := _buttons()
	if buttons.size() < 2:
		return
	var first := buttons[0] as Button
	var last := buttons[-1] as Button
	first.focus_neighbor_top = first.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(first)


# --- rows --------------------------------------------------------------------

## A row's button: a slanted bar that lights up when chosen. What is drawn
## on it and is in its "inked" list is drawn dark while it is chosen.
func _bar(height: float) -> Button:
	var button := Button.new()
	for style: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button.custom_minimum_size.y = height * _unit
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = ROW_SHADER
	material.set_shader_parameter("slant", ROW_SLANT)
	material.set_shader_parameter("accent", ACCENT)
	material.set_shader_parameter("stripe", maxf(0.45 * _unit, 2.0))
	material.set_shader_parameter("chosen", 0.0)
	back.material = material
	button.add_child(back)
	button.resized.connect(func() -> void: material.set_shader_parameter("size", button.size))
	button.set_meta("material", material)
	button.set_meta("inked", [])
	button.focus_entered.connect(_chosen.bind(button, true))
	button.focus_exited.connect(_chosen.bind(button, false))
	button.pressed.connect(func() -> void:
		button.create_tween().tween_method(func(value: float) -> void:
			material.set_shader_parameter("flash", value), 1.0, 0.0, 0.3))
	# the mouse over a row chooses it, as the arrow keys do
	button.mouse_entered.connect(button.grab_focus)
	return button


## A row lights up and slides out, or goes back.
func _chosen(button: Button, chosen: bool) -> void:
	var material := button.get_meta("material") as ShaderMaterial
	if button.has_meta("moving"):
		(button.get_meta("moving") as Tween).kill()
	var tween := button.create_tween().set_parallel()
	tween.tween_method(func(value: float) -> void: material.set_shader_parameter("chosen", value),
			float(material.get_shader_parameter("chosen")), 1.0 if chosen else 0.0, CHOOSE_TIME)
	if button.get_parent() == _list:
		tween.tween_method(_offset.bind(button, "shift"), float(button.get_meta("shift", 0.0)),
				CHOSEN_SHIFT * _unit if chosen else 0.0, CHOOSE_TIME * 1.5) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	button.set_meta("moving", tween)
	for part: Control in button.get_meta("inked"):
		if part is Label:
			part.add_theme_color_override("font_color", INK if chosen else part.get_meta("colour") as Color)
		elif part is Segments:
			(part as Segments).chosen = chosen
	if chosen:
		_about.text = button.get_meta("about", _page_about)


## Puts a row under those before it.
func _add(row: Control, height: float) -> void:
	row.position = Vector2(0.0, _next_y)
	row.size = Vector2(_row_width, height * _unit)
	_next_y += (height + ROW_GAP) * _unit
	_list.add_child(row)
	_arrivals.append(row)


func _label(text: String, colour := TEXT, text_size := TEXT_SIZE, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.uppercase = true
	label.add_theme_font_override("font", font if font != null else _font)
	label.add_theme_font_size_override("font_size", int(text_size * _unit))
	label.add_theme_color_override("font_color", colour)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_meta("colour", colour)
	return label


## A row of the page with its number and name, and `right` at its right end.
func _named_row(text: String, right: Control = null) -> Button:
	var button := _bar(_row_height)
	button.set_meta("about", ABOUT.get(text, ""))
	var parts := HBoxContainer.new()
	parts.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lean := _row_height * _unit * ROW_SLANT * 0.5
	parts.offset_left = lean + 1.8 * _unit
	parts.offset_right = -lean - 2.0 * _unit
	parts.add_theme_constant_override("separation", int(1.6 * _unit))
	parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row_number += 1
	var number := _label("%02d" % _row_number, SECOND, SMALL_SIZE * _text_size / TEXT_SIZE, _spaced_font)
	var name := _label(text, TEXT, _text_size)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts.add_child(number)
	parts.add_child(name)
	var inked: Array = [number, name]
	if right != null:
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parts.add_child(right)
		inked.append(right)
		inked.append_array(right.find_children("*", "Label", true, false))
		for child in right.get_children():
			if child is Segments:
				inked.append(child)
	button.set_meta("inked", inked)
	button.add_child(parts)
	_add(button, _row_height)
	return button


func _item(text: String, chosen: Callable) -> Button:
	var button := _named_row(text)
	button.pressed.connect(chosen)
	return button


## A row with a name at the left and something at the right. `step` is
## called with -1 or 1 for left and right, and with 1 when it is chosen.
func _row(text: String, right: Control, step: Callable) -> Button:
	var button := _named_row(text, right)
	button.pressed.connect(step.bind(1))
	button.gui_input.connect(func(event: InputEvent) -> void:
		for direction: int in [-1, 1]:
			if event.is_action_pressed("ui_left" if direction < 0 else "ui_right", true):
				step.call(direction)
				button.accept_event())
	return button


## A value at the right end of a row.
func _value() -> Label:
	var value := _label("", SECOND, _text_size)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return value


## Shows `text` on `value`, between arrows; in the row's colour when `lit`.
func _tell(value: Label, text: String, lit := true) -> void:
	value.text = "‹  %s  ›" % text
	value.set_meta("colour", SECOND if lit else FAINT)
	if value.get_theme_color("font_color") != INK:
		value.add_theme_color_override("font_color", value.get_meta("colour") as Color)


func _change(section: String, property: String, value: Variant) -> void:
	settings.set(property, value)
	settings.save_file()
	changed.emit(section)


## A row that turns a setting on and off.
func _switch(text: String, section: String, property: String) -> void:
	var value := _value()
	var tell := func() -> void: _tell(value, "On" if settings.get(property) else "Off", settings.get(property))
	tell.call()
	_row(text, value, func(_direction: int) -> void:
		_change(section, property, not settings.get(property))
		tell.call())


## A row that goes through the values of a setting that is a number from
## 0 on, each with a name.
func _choice(text: String, section: String, property: String, names: Array[String]) -> void:
	var value := _value()
	var tell := func() -> void: _tell(value, names[clampi(settings.get(property), 0, names.size() - 1)])
	tell.call()
	_row(text, value, func(direction: int) -> void:
		_change(section, property, posmod(int(settings.get(property)) + direction, names.size()))
		tell.call())


## A row for each mod there is, that turns it on and off. What it changes
## shows once the menu is left or a game is started.
func _mods() -> void:
	var mods := Mods.find_all()
	var folders := Mods.folders()
	if mods.is_empty():
		_page_about = "No mods. Put them in %s or %s." % [folders[0], folders[1]]
		return
	_page_about = "Mods are put in %s or %s." % [folders[0], folders[1]]
	for mod in mods:
		var value := _value()
		var on := func() -> bool: return not mod.id in settings.mods_off
		var tell := func() -> void: _tell(value, "On" if on.call() else "Off", on.call())
		tell.call()
		var button := _row(mod.name, value, func(_direction: int) -> void:
			var off := settings.mods_off.duplicate()
			if on.call():
				off.append(mod.id)
			else:
				off.erase(mod.id)
			_change("mods", "mods_off", off)
			tell.call())
		var about := mod.description
		var by := " ".join([mod.version, ("by " + mod.author) if mod.author != "" else ""]).strip_edges()
		if by != "":
			about = "%s (%s)" % [about, by] if about != "" else by
		button.set_meta("about", about)


func _window_size() -> void:
	var sizes := Settings.window_sizes(DisplayServer.screen_get_size(get_window().current_screen))
	var value := _value()
	var tell := func() -> void: _tell(value, "%d × %d" % [settings.window_size.x, settings.window_size.y])
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


## A row that sets a setting from 0 to 1 in VOLUME_STEPS steps.
func _volume(text: String, property: String, section := "sound") -> void:
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", int(1.6 * _unit))
	var bar := Segments.new()
	bar.steps = VOLUME_STEPS
	bar.lit = SECOND
	bar.custom_minimum_size = Vector2(26.0, 1.6) * _unit
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parts.add_child(bar)
	var value := _label("", TEXT, _text_size)
	value.custom_minimum_size.x = 8.0 * _unit
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parts.add_child(value)
	var tell := func() -> void:
		var steps := roundi(float(settings.get(property)) * VOLUME_STEPS)
		bar.value = steps
		value.text = "%d%%" % (steps * 100 / VOLUME_STEPS)
	tell.call()
	_row(text, parts, func(direction: int) -> void:
		var steps := roundi(float(settings.get(property)) * VOLUME_STEPS)
		_change(section, property, clampi(steps + direction, 0, VOLUME_STEPS) / float(VOLUME_STEPS))
		tell.call())


## A bar of slanted steps, as many lit as `value`; or with `running`, a
## few lit going round, for something under way.
class Segments extends Control:
	var steps := 10
	var value := 0:
		set(to):
			value = to
			queue_redraw()
	var chosen := false:
		set(to):
			chosen = to
			queue_redraw()
	var running := false
	var lit := Color.WHITE

	func _process(_delta: float) -> void:
		if running and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var lean := size.y * 0.45
		var gap := maxf(size.y * 0.3, 2.0)
		var width := (size.x - lean - gap * (steps - 1)) / steps
		var turn := int(Time.get_ticks_msec() / 70.0)
		for step in steps:
			var on := step < value
			if running:
				on = posmod(step - turn, steps) < 4
			var colour := lit if on else Color(1, 1, 1, 0.14)
			if chosen:
				colour = Color(0.02, 0.03, 0.07) if on else Color(0.02, 0.03, 0.07, 0.25)
			var x := step * (width + gap)
			draw_colored_polygon(PackedVector2Array([Vector2(x + lean, 0.0), Vector2(x + lean + width, 0.0),
					Vector2(x + width, size.y), Vector2(x, size.y)]), colour)


# --- the controls ------------------------------------------------------------

func _controls() -> void:
	var height := 3.9
	var grid := GridContainer.new()
	grid.columns = 1 + Settings.PLACES
	grid.add_theme_constant_override("h_separation", int(1.2 * _unit))
	grid.add_theme_constant_override("v_separation", int(0.45 * _unit))
	for heading: String in ["", "Key", "Gamepad", "Gamepad"]:
		var label := _label(heading, SECOND, SMALL_SIZE, _spaced_font)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(label)
	for action in Settings.ACTIONS:
		var label := _label(Settings.ACTION_NAMES[action], TEXT, TEXT_SIZE * 0.8)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		for place in Settings.PLACES:
			var button := _small_bar(Settings.place_name(settings.controls[action][place]), height)
			button.custom_minimum_size.x = 25.0 * _unit
			button.pressed.connect(_await.bind(action, place, button))
			grid.add_child(button)
	_add(grid, grid.get_combined_minimum_size().y / _unit)
	var below := HBoxContainer.new()
	below.add_theme_constant_override("separation", int(1.2 * _unit))
	for entry: Array in [["Back", _back], ["As they were at first", _reset_controls]]:
		var button := _small_bar(entry[0], height + 0.8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		if entry[0] == "Back":
			button.set_meta("about", ABOUT["Back"])
		below.add_child(button)
	_add(below, height + 0.8)


## A small bar with its text in the middle, for the controls.
func _small_bar(text: String, height: float) -> Button:
	var button := _bar(height)
	var label := _label(text, TEXT, TEXT_SIZE * 0.75)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = height * _unit * ROW_SLANT * 0.5 + 0.8 * _unit
	label.offset_right = -label.offset_left
	button.add_child(label)
	button.set_meta("inked", [label])
	button.set_meta("label", label)
	return button


func _set_bar_text(button: Button, text: String) -> void:
	(button.get_meta("label") as Label).text = text


func _reset_controls() -> void:
	settings.reset_controls()
	_controls_changed()
	_pages[-1][1] = _focused_row()
	_show(false)


func _controls_changed() -> void:
	settings.apply_controls()
	settings.save_file()
	changed.emit("controls")


func _await(action: String, place: int, button: Button) -> void:
	_stop_awaiting()
	_awaited_action = action
	_awaited_place = place
	_awaited_button = button
	_set_bar_text(button, "Press a key" if place == 0 else "Press a button")


func _stop_awaiting() -> void:
	if _awaited_action != "" and is_instance_valid(_awaited_button):
		_set_bar_text(_awaited_button, Settings.place_name(settings.controls[_awaited_action][_awaited_place]))
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
