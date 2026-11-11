extends Control
## The course editor's view of a course: the cells' pictures, and over them
## what the editor's tools work on. What the mouse buttons do on the course
## is the editor's (editor/course_editor.gd).
##
## The map goes round both ways (the game takes a position's cell modulo the
## map's size), so the view has no edges: it draws the map again wherever it
## looks. The other cars' route runs through these copies as one unbroken
## line, and with `follow` on, scrolling moves the view along it, so the
## course reads as one road from the start to the finish however often it
## crosses the map's edges. The wheel scrolls, Ctrl and the wheel zooms, the
## middle button (or the left with Space held) drags the view. A picture of
## the whole route in the corner jumps to where it is clicked.

const CELL := CourseData.CELL
const MOST_ZOOM := 4.0
const LEAST_ZOOM := 0.03
const BACKGROUND := Color(0.06, 0.07, 0.09)
const GRID := Color(1, 1, 1, 0.12)
const SEAM := Color(1, 1, 1, 0.45)
const MARK := Color(1.0, 0.42, 0.08)
const SECOND := Color(0.16, 0.89, 1.0)
## How far one turn of the wheel scrolls, in pixels of the view.
const WHEEL_STEP := 120.0
## The picture of the whole route, in the top right corner.
const OVERVIEW_SIZE := Vector2(170, 220)
const OVERVIEW_MARGIN := 10.0
## Zoomed out further than this, the route is drawn as a guide.
const GUIDE_ZOOM := 0.12

var editor: CourseEditor
## How many pixels of the view a pixel of the course is, and the course
## position at the view's top left.
var zoom := 0.25
var origin := Vector2.ZERO
## Where the mouse is on the course.
var hover := Vector2i.ZERO
## Scrolling follows the route; `along` is how far along it the view is,
## and `offset` where the view's middle is from that point of the route.
var follow := true
var along := 0.0
var offset := Vector2.ZERO

var _look_at := Vector2.INF
var _panning := false
var _space := false
var _in_overview := false
var _font: Font
var _route := PackedVector2Array()
var _lengths := PackedFloat32Array()


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


## The size of the map in pixels of the course: it repeats at these steps.
func period() -> Vector2:
	return Vector2(editor.data.across, editor.data.down) * CELL


## Shows `at` of the course in the middle of the view (once it has a size).
func look_at_course(at: Vector2) -> void:
	if size == Vector2.ZERO:
		_look_at = at
		return
	origin = at - size / zoom / 2.0
	_moved_by_hand()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and size != Vector2.ZERO:
		if _look_at != Vector2.INF:
			look_at_course(_look_at)
			_look_at = Vector2.INF
		else:
			_place_on_route()


# --- following the route -----------------------------------------------------

## The route as a line through the middles of its boxes, and how far along
## it each of them is.
func _update_route() -> void:
	_route.clear()
	_lengths.clear()
	var total := 0.0
	for point in editor.data.waypoints:
		var at := Vector2(point[0], point[1])
		if not _route.is_empty():
			total += _route[-1].distance_to(at)
		_route.append(at)
		_lengths.append(total)


func _can_follow() -> bool:
	return follow and _route.size() >= 2


func _route_point(distance: float) -> Vector2:
	distance = clampf(distance, 0.0, _lengths[-1])
	for index in range(1, _route.size()):
		if _lengths[index] >= distance:
			var span := _lengths[index] - _lengths[index - 1]
			var part := 0.0 if span <= 0.0 else (distance - _lengths[index - 1]) / span
			return _route[index - 1].lerp(_route[index], part)
	return _route[-1]


## How far along the route its point nearest to `at` is.
func _nearest_along(at: Vector2) -> float:
	var best := 0.0
	var best_distance := INF
	for index in range(1, _route.size()):
		var near := Geometry2D.get_closest_point_to_segment(at, _route[index - 1], _route[index])
		var distance := near.distance_squared_to(at)
		if distance < best_distance:
			best_distance = distance
			best = _lengths[index - 1] + _route[index - 1].distance_to(near)
	return best


func _middle() -> Vector2:
	return origin + size / zoom / 2.0


## After the view was moved some other way than along the route: where along
## it the view now is.
func _moved_by_hand() -> void:
	_update_route()
	if _route.size() < 2:
		return
	var middle := _middle()
	along = _nearest_along(middle)
	offset = middle - _route_point(along)


func _place_on_route() -> void:
	_update_route()
	if _can_follow():
		origin = _route_point(along) + offset - size / zoom / 2.0
	queue_redraw()


## Scrolls by `amount` pixels of the view: forward along the route when
## following it (towards the finish), otherwise up.
func scroll(amount: float) -> void:
	_update_route()
	if _can_follow():
		along = clampf(along + amount / zoom, 0.0, _lengths[-1])
		_place_on_route()
	else:
		origin.y -= amount / zoom
		_moved_by_hand()
	queue_redraw()


func scroll_sideways(amount: float) -> void:
	origin.x += amount / zoom
	_moved_by_hand()
	queue_redraw()


## Back to the middle of the road, at the same place along it.
func back_to_road() -> void:
	offset = Vector2.ZERO
	_place_on_route()


func set_follow(on: bool) -> void:
	follow = on
	if on:
		_moved_by_hand()
	queue_redraw()


func zoom_by(factor: float, at: Vector2) -> void:
	var fixed := to_course(at)
	zoom = clampf(zoom * factor, LEAST_ZOOM, MOST_ZOOM)
	origin = fixed - at / zoom
	_moved_by_hand()
	queue_redraw()


# --- input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if button.pressed:
				_wheel(button)
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE or (button.button_index == MOUSE_BUTTON_LEFT and _space):
			_panning = button.pressed
			accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and _overview_rect().has_point(button.position):
			_in_overview = true
			_jump_to(button.position)
			accept_event()
			return
		if _in_overview and not button.pressed:
			_in_overview = false
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
			_moved_by_hand()
		elif _in_overview:
			_jump_to(motion.position)
		else:
			hover = Vector2i(to_course(motion.position).floor())
			editor.view_moved(hover, motion.button_mask, motion)
		queue_redraw()
		accept_event()
		return
	var pan := event as InputEventPanGesture
	if pan != null:
		if pan.ctrl_pressed:
			zoom_by(1.0 - pan.delta.y * 0.05, pan.position)
		else:
			scroll(-pan.delta.y * WHEEL_STEP * 0.25)
			if pan.delta.x != 0.0:
				scroll_sideways(pan.delta.x * WHEEL_STEP * 0.25)
		accept_event()
		return
	var magnify := event as InputEventMagnifyGesture
	if magnify != null:
		zoom_by(magnify.factor, magnify.position)
		accept_event()
		return
	var key := event as InputEventKey
	if key != null and key.keycode == KEY_SPACE:
		_space = key.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if _space else Control.CURSOR_CROSS
		accept_event()
		return
	if key != null and key.pressed:
		match key.keycode:
			KEY_UP: scroll(WHEEL_STEP)
			KEY_DOWN: scroll(-WHEEL_STEP)
			KEY_LEFT: scroll_sideways(-WHEEL_STEP)
			KEY_RIGHT: scroll_sideways(WHEEL_STEP)
			KEY_PAGEUP: scroll(size.y * 0.8)
			KEY_PAGEDOWN: scroll(-size.y * 0.8)
			_: return
		accept_event()


func _wheel(button: InputEventMouseButton) -> void:
	var up := button.button_index == MOUSE_BUTTON_WHEEL_UP
	var down := button.button_index == MOUSE_BUTTON_WHEEL_DOWN
	var amount := WHEEL_STEP * maxf(button.factor, 1.0) if button.factor > 0.0 else WHEEL_STEP
	if button.ctrl_pressed and (up or down):
		zoom_by(1.2 if up else 1.0 / 1.2, button.position)
	elif button.shift_pressed and (up or down):
		scroll_sideways(-amount if up else amount)
	elif up or down:
		scroll(amount if up else -amount)
	else:
		scroll_sideways(-amount if button.button_index == MOUSE_BUTTON_WHEEL_LEFT else amount)


# --- the overview of the route -----------------------------------------------

func _overview_rect() -> Rect2:
	if editor == null or editor.data == null or editor.data.waypoints.size() < 2:
		return Rect2()
	return Rect2(Vector2(size.x - OVERVIEW_SIZE.x - OVERVIEW_MARGIN, OVERVIEW_MARGIN), OVERVIEW_SIZE)


## The route's bounds, and how they fit in the overview: its scale and the
## top left of the route in it.
func _overview_fit() -> Array:
	var bounds := Rect2(_route[0], Vector2.ZERO)
	for at in _route:
		bounds = bounds.expand(at)
	bounds = bounds.grow(CELL)
	var box := _overview_rect().grow(-12.0)
	box.position.y += 14.0
	box.size.y -= 14.0
	var scale := minf(box.size.x / bounds.size.x, box.size.y / bounds.size.y)
	var corner := box.position + (box.size - bounds.size * scale) / 2.0
	return [bounds, scale, corner]


func _jump_to(at: Vector2) -> void:
	_update_route()
	if _route.size() < 2:
		return
	var fit := _overview_fit()
	var bounds: Rect2 = fit[0]
	var target: Vector2 = (at - fit[2]) / fit[1] + bounds.position
	along = _nearest_along(target)
	offset = Vector2.ZERO
	var was := follow
	follow = true
	_place_on_route()
	follow = was


func _draw_overview(data: CourseData) -> void:
	var rect := _overview_rect()
	if rect.size == Vector2.ZERO or _route.size() < 2:
		return
	draw_rect(rect, Color(0.04, 0.05, 0.07, 0.85))
	draw_rect(rect, Color(1, 1, 1, 0.2), false, 1.0)
	_text(rect.position + Vector2(8, 4), "Course: click to go there", Color(1, 1, 1, 0.7), 11)
	var fit := _overview_fit()
	var bounds: Rect2 = fit[0]
	var scale: float = fit[1]
	var corner: Vector2 = fit[2]
	var points := PackedVector2Array()
	for at in _route:
		points.append(corner + (at - bounds.position) * scale)
	draw_polyline(points, Color(SECOND, 0.9), 2.0)
	draw_circle(corner + (Vector2(data.start) - bounds.position) * scale, 4.0, MARK)
	_text(corner + (Vector2(data.start) - bounds.position) * scale + Vector2(6, -6), "Start", MARK, 11)
	draw_circle(points[-1], 3.0, Color.WHITE)
	_text(points[-1] + Vector2(6, -6), "End", Color.WHITE, 11)
	# what the view shows
	var shown := Rect2(corner + (origin - bounds.position) * scale, size / zoom * scale)
	shown = shown.intersection(rect)
	if shown.size != Vector2.ZERO:
		draw_rect(shown, Color(1, 1, 1, 0.12))
		draw_rect(shown, Color(1, 1, 1, 0.8), false, 1.0)


# --- drawing -----------------------------------------------------------------

## The copies of `rect` (of the course) that the view shows, as the map
## repeats both ways.
func copies(rect: Rect2) -> Array[Rect2]:
	var shown: Array[Rect2] = []
	var step := period()
	var top_left := origin
	var bottom_right := to_course(size)
	var first := Vector2i(floori((top_left.x - rect.end.x) / step.x) + 1, floori((top_left.y - rect.end.y) / step.y) + 1)
	var last := Vector2i(floori((bottom_right.x - rect.position.x) / step.x), floori((bottom_right.y - rect.position.y) / step.y))
	for down in range(first.y, last.y + 1):
		for across in range(first.x, last.x + 1):
			shown.append(Rect2(rect.position + Vector2(across, down) * step, rect.size))
	return shown


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var data: CourseData = editor.data
	if data == null:
		return
	_update_route()
	var top_left := origin
	var bottom_right := to_course(size)
	var first := Vector2i((top_left / CELL).floor())
	var last := Vector2i((bottom_right / CELL).floor())
	var tool: int = editor.tool
	var show_codes: bool = editor.show_codes
	var cell_size := Vector2(CELL, CELL) * zoom
	for row in range(first.y, last.y + 1):
		for column in range(first.x, last.x + 1):
			var place := posmod(row, data.down) * data.across + posmod(column, data.across)
			var cell := data.map[place]
			var rect := Rect2(to_view(Vector2(column * CELL, row * CELL)), cell_size)
			var texture: Texture2D = editor.cell_texture(cell)
			if texture != null:
				draw_texture_rect(texture, rect, false)
			else:
				draw_rect(rect, Color(0.2, 0.22, 0.25))
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
	_draw_seams(data, first, last)
	if tool == CourseEditor.Tool.SCENERY or editor.show_scenery:
		_draw_scenery(data)
	if tool == CourseEditor.Tool.ROUTE or editor.show_route:
		_draw_route(data)
	elif zoom < GUIDE_ZOOM and _route.size() >= 2:
		# zoomed out, the map's copies look alike: the road from the start
		# to the finish is the line
		var points := PackedVector2Array()
		for at in _route:
			points.append(to_view(at))
		draw_polyline(points, Color(SECOND, 0.7), 3.0)
	if tool == CourseEditor.Tool.START or editor.show_route:
		_draw_start(data)
	_draw_hover(data)
	_draw_overview(data)


## Dashed lines where the map ends and starts again.
func _draw_seams(data: CourseData, first: Vector2i, last: Vector2i) -> void:
	var dash := 10.0
	for column in range(first.x, last.x + 2):
		if posmod(column, data.across) == 0:
			var x := to_view(Vector2(column * CELL, 0)).x
			draw_dashed_line(Vector2(x, 0), Vector2(x, size.y), SEAM, 2.0, dash)
			if zoom >= GUIDE_ZOOM:
				_text(Vector2(x + 6, size.y - 22), "Edge of the map (it continues on the other side)", SEAM, 11)
	for row in range(first.y, last.y + 2):
		if posmod(row, data.down) == 0:
			var y := to_view(Vector2(0, row * CELL)).y
			draw_dashed_line(Vector2(0, y), Vector2(size.x, y), SEAM, 2.0, dash)
			if zoom >= GUIDE_ZOOM:
				_text(Vector2(8, y + 4), "Edge of the map (it continues on the other side)", SEAM, 11)


func _draw_scenery(data: CourseData) -> void:
	var order: Array = range(data.scenery.size())
	order.sort_custom(func(a: int, b: int) -> bool: return data.scenery[a].y < data.scenery[b].y)
	for index: int in order:
		var thing: Vector3i = data.scenery[index]
		var rect: Rect2 = editor.thing_rect(thing)
		var texture: Texture2D = editor.kind_texture(thing.z)
		var chosen: bool = index == editor.selected_thing
		for moved in copies(rect):
			var view := Rect2(to_view(moved.position), moved.size * zoom)
			if texture != null:
				draw_texture_rect(texture, view, false)
			else:
				draw_rect(view, Color(0.5, 0.8, 0.4, 0.5))
			if chosen:
				draw_rect(view, MARK, false, 2.0)
			var foot := to_view(moved.position + Vector2(thing.x, thing.y) - rect.position)
			draw_circle(foot, 3.0, MARK if chosen else Color(1, 1, 1, 0.7))


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
		# the game's y is 16 bits: past the top of the map it is a large number
		var y: float = to_view(Vector2(0, GameRoutines.wrap16(int(data.progress[index])))).y
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
	var hovered := Vector2i(floori(hover.x / float(CELL)), floori(hover.y / float(CELL)))
	match editor.tool:
		CourseEditor.Tool.CELLS:
			if editor.picking:
				var picked: Rect2i = editor.picked_rect(hovered)
				_outline_cells(Rect2(picked.position * CELL, picked.size * CELL), Color(SECOND, 0.25), SECOND)
				return
			var stamp: Array = editor.stamp_cells()
			var stamp_size := Vector2i(stamp[0].size(), stamp.size())
			# the cells it would put, faint, over the map
			for row in stamp_size.y:
				for column in stamp_size.x:
					var texture: Texture2D = editor.cell_texture(stamp[row][column])
					if texture != null:
						var corner := Vector2((hovered + Vector2i(column, row)) * CELL)
						draw_texture_rect(texture, Rect2(to_view(corner), Vector2(CELL, CELL) * zoom), false,
								Color(1, 1, 1, 0.6))
			# the same places in the other copies of the map are the same places
			var rect := Rect2(Vector2(hovered * CELL), Vector2(stamp_size * CELL))
			for copy in copies(rect):
				var view := Rect2(to_view(copy.position), copy.size * zoom)
				draw_rect(view, MARK if copy.position == rect.position else Color(MARK, 0.5), false, 2.0)
		CourseEditor.Tool.SIGNS:
			var rect := Rect2(Vector2(hovered * CELL), Vector2(CELL, CELL))
			for copy in copies(rect):
				draw_rect(Rect2(to_view(copy.position), copy.size * zoom),
						MARK if copy.position == rect.position else Color(MARK, 0.5), false, 2.0)
		CourseEditor.Tool.GROUND:
			var brush: int = editor.brush
			var corner := Vector2((floori(hover.x / 8.0) - brush / 2) * 8, (floori(hover.y / 8.0) - brush / 2) * 8)
			draw_rect(Rect2(to_view(corner), Vector2(brush * 8, brush * 8) * zoom), MARK, false, 2.0)
			var cell := Vector2(hovered * CELL)
			draw_rect(Rect2(to_view(cell), Vector2(CELL, CELL) * zoom), Color(MARK, 0.5), false, 1.0)


func _outline_cells(rect: Rect2, fill: Color, line: Color) -> void:
	var view := Rect2(to_view(rect.position), rect.size * zoom)
	draw_rect(view, fill)
	draw_rect(view, line, false, 2.0)


func _text(at: Vector2, text: String, colour: Color, font_size: int) -> void:
	draw_string_outline(_font, at + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.8))
	draw_string(_font, at + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
