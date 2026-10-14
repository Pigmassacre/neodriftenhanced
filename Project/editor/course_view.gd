extends Control
## The course editor's view of a course: the cells' pictures, and over them
## what the editor's tools work on. Dragged about with the middle mouse
## button (or the left with Space held), zoomed with the wheel; what the
## other buttons do is the editor's (editor/course_editor.gd).

const CELL := CourseData.CELL
const MOST_ZOOM := 4.0
const LEAST_ZOOM := 0.03
const BACKGROUND := Color(0.06, 0.07, 0.09)
const GRID := Color(1, 1, 1, 0.12)
const MARK := Color(1.0, 0.42, 0.08)
const SECOND := Color(0.16, 0.89, 1.0)

var editor: CourseEditor
## How many pixels of the view a pixel of the course is, and the course
## position at the view's top left.
var zoom := 0.25
var origin := Vector2.ZERO
## Where the mouse is on the course.
var hover := Vector2i.ZERO

var _look_at := Vector2.INF
var _panning := false
var _space := false
var _font: Font


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_font = ThemeDB.fallback_font


func to_view(at: Vector2) -> Vector2:
	return (at - origin) * zoom


func to_course(at: Vector2) -> Vector2:
	return at / zoom + origin


## Shows `at` of the course in the middle of the view (once it has a size).
func look_at_course(at: Vector2) -> void:
	if size == Vector2.ZERO:
		_look_at = at
		return
	origin = at - size / zoom / 2.0
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _look_at != Vector2.INF and size != Vector2.ZERO:
		look_at_course(_look_at)
		_look_at = Vector2.INF


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var fixed := to_course(button.position)
				var factor := 1.2 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2
				if button.ctrl_pressed:
					# Ctrl and the wheel go through the editor's palette
					editor.view_wheel(1 if button.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
				else:
					zoom = clampf(zoom * factor, LEAST_ZOOM, MOST_ZOOM)
					origin = fixed - button.position / zoom
				queue_redraw()
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE or (button.button_index == MOUSE_BUTTON_LEFT and _space):
			_panning = button.pressed
			accept_event()
			return
		grab_focus()
		hover = Vector2i(to_course(button.position).floor())
		if button.pressed:
			editor.view_pressed(hover, button.button_index, button)
		else:
			editor.view_released(hover, button.button_index)
		queue_redraw()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _panning:
			origin -= motion.relative / zoom
		else:
			hover = Vector2i(to_course(motion.position).floor())
			editor.view_moved(hover, motion.button_mask, motion)
		queue_redraw()
		accept_event()
		return
	var key := event as InputEventKey
	if key != null and key.keycode == KEY_SPACE:
		_space = key.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _space else Control.CURSOR_CROSS
		accept_event()
		return
	if key != null and key.pressed:
		var step := 64.0 / zoom
		match key.keycode:
			KEY_LEFT: origin.x -= step
			KEY_RIGHT: origin.x += step
			KEY_UP: origin.y -= step
			KEY_DOWN: origin.y += step
			_: return
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var data: CourseData = editor.data
	if data == null:
		return
	var top_left := origin
	var bottom_right := to_course(size)
	var first := Vector2i((top_left / CELL).floor())
	var last := Vector2i((bottom_right / CELL).floor())
	var tool: int = editor.tool
	var show_codes: bool = editor.show_codes
	var cell_size := Vector2(CELL, CELL) * zoom
	for row in range(maxi(first.y, 0), mini(last.y, data.down - 1) + 1):
		for column in range(first.x, last.x + 1):
			var place := row * data.across + posmod(column, data.across)
			var cell := data.map[place]
			var rect := Rect2(to_view(Vector2(column * CELL, row * CELL)), cell_size)
			var texture: Texture2D = editor.cell_texture(cell)
			if texture != null:
				draw_texture_rect(texture, rect, false)
			else:
				draw_rect(rect, Color(0.2, 0.22, 0.25))
			if column < 0 or column >= data.across:
				# the course again, as it goes round
				draw_rect(rect, Color(0, 0, 0, 0.45))
			if show_codes:
				draw_texture_rect(editor.codes_texture(cell), rect, false, Color(1, 1, 1, CourseEditor.CODES_SHOWN))
			if zoom >= 0.08:
				draw_rect(rect, GRID, false, 1.0)
			if tool == CourseEditor.Tool.CELLS and zoom >= 0.12:
				_text(rect.position + Vector2(4, 4), str(cell), Color(1, 1, 1, 0.8), 11)
			if tool == CourseEditor.Tool.SIGNS and data.signs[place] != 0:
				draw_rect(rect, Color(SECOND, 0.25))
				_text(rect.position + rect.size / 2.0 - Vector2(8, 10), str(data.signs[place]), Color.WHITE,
						maxi(12, int(48 * zoom)))
	if tool == CourseEditor.Tool.SCENERY or editor.show_scenery:
		_draw_scenery(data, top_left, bottom_right)
	if tool == CourseEditor.Tool.ROUTE or editor.show_route:
		_draw_route(data)
	if tool == CourseEditor.Tool.START or editor.show_route:
		_draw_start(data)
	_draw_hover(data)


func _draw_scenery(data: CourseData, top_left: Vector2, bottom_right: Vector2) -> void:
	var order: Array = range(data.scenery.size())
	order.sort_custom(func(a: int, b: int) -> bool: return data.scenery[a].y < data.scenery[b].y)
	var width := data.across * CELL
	for index: int in order:
		var thing: Vector3i = data.scenery[index]
		var rect: Rect2 = editor.thing_rect(thing)
		for shift: int in [-width, 0, width]:
			var moved := Rect2(rect.position + Vector2(shift, 0), rect.size)
			if moved.end.x < top_left.x or moved.position.x > bottom_right.x \
					or moved.end.y < top_left.y or moved.position.y > bottom_right.y:
				continue
			var view := Rect2(to_view(moved.position), moved.size * zoom)
			var texture: Texture2D = editor.kind_texture(thing.z)
			if texture != null:
				draw_texture_rect(texture, view, false)
			else:
				draw_rect(view, Color(0.5, 0.8, 0.4, 0.5))
			if index == editor.selected_thing:
				draw_rect(view, MARK, false, 2.0)
			var foot := to_view(Vector2(thing.x + shift, thing.y))
			draw_circle(foot, 3.0, MARK if index == editor.selected_thing else Color(1, 1, 1, 0.7))


func _draw_route(data: CourseData) -> void:
	var before := Vector2.INF
	for index in data.waypoints.size():
		var point := data.waypoints[index]
		var centre := to_view(Vector2(point[0], point[1]))
		var half := Vector2(point[2], point[3]) / 2.0 * zoom
		var chosen: bool = index == editor.selected_point
		var colour := MARK if chosen else SECOND
		draw_rect(Rect2(centre - half, half * 2.0), Color(colour, 0.18))
		draw_rect(Rect2(centre - half, half * 2.0), colour, false, 2.0 if chosen else 1.0)
		if chosen:
			draw_rect(Rect2(centre + half - Vector2(5, 5), Vector2(10, 10)), MARK)
		if before != Vector2.INF:
			draw_line(before, centre, Color(SECOND, 0.8), 2.0)
		before = centre
		_text(centre + Vector2(4, -4), "%d" % index, Color.WHITE, 13)
		if zoom >= 0.15:
			_text(centre + Vector2(4, 12), "speed %d" % point[4], Color(1, 1, 1, 0.7), 11)
	var first: Array = data.rivals_from
	for rival in first.size():
		var at := int(first[rival])
		if at >= 0 and at < data.waypoints.size():
			var point := data.waypoints[at]
			_text(to_view(Vector2(point[0], point[1])) + Vector2(-30, -8 - rival * 14),
					"car %d" % (rival + 1), Color(1, 0.9, 0.3), 11)


func _draw_start(data: CourseData) -> void:
	var width := size.x
	for index in data.progress.size():
		var y: float = to_view(Vector2(0, float(data.progress[index]))).y
		var chosen: bool = index == editor.selected_line
		var colour := MARK if chosen else Color(1, 0.9, 0.3)
		draw_line(Vector2(0, y), Vector2(width, y), colour, 2.0 if chosen else 1.0)
		var label := "Start" if index == 0 else "Finish" if index == data.progress.size() - 1 else "Checkpoint %d" % index
		_text(Vector2(8, y - 16), "%s  y %d" % [label, int(data.progress[index])], colour, 13)
	var at := to_view(Vector2(data.start))
	var facing := deg_to_rad(data.facing)
	# 0 faces right, and the angle goes round clockwise (y goes down)
	var ahead := Vector2(cos(facing), sin(facing))
	draw_circle(at, 7.0, MARK)
	draw_line(at, at + ahead * 40.0, MARK, 3.0)
	draw_line(at + ahead * 40.0, at + ahead * 28.0 + ahead.orthogonal() * 8.0, MARK, 3.0)
	draw_line(at + ahead * 40.0, at + ahead * 28.0 - ahead.orthogonal() * 8.0, MARK, 3.0)


## What the tool would change, under the mouse.
func _draw_hover(data: CourseData) -> void:
	match editor.tool:
		CourseEditor.Tool.CELLS, CourseEditor.Tool.SIGNS:
			var corner := Vector2(floori(hover.x / float(CELL)) * CELL, floori(hover.y / float(CELL)) * CELL)
			draw_rect(Rect2(to_view(corner), Vector2(CELL, CELL) * zoom), MARK, false, 2.0)
		CourseEditor.Tool.GROUND:
			var brush: int = editor.brush
			var corner := Vector2((floori(hover.x / 8.0) - brush / 2) * 8, (floori(hover.y / 8.0) - brush / 2) * 8)
			draw_rect(Rect2(to_view(corner), Vector2(brush * 8, brush * 8) * zoom), MARK, false, 2.0)
			var cell := Vector2(floori(hover.x / float(CELL)) * CELL, floori(hover.y / float(CELL)) * CELL)
			draw_rect(Rect2(to_view(cell), Vector2(CELL, CELL) * zoom), Color(MARK, 0.5), false, 1.0)


func _text(at: Vector2, text: String, colour: Color, font_size: int) -> void:
	draw_string_outline(_font, at + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, at + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
