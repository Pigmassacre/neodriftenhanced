class_name Minimap
extends Control
## A map of the course in a race: its road with every way through, where
## the player's car is and has been, and where the other cars are. Drawn
## over the game's picture at the window's own resolution, not in game
## pixels.
##
## The game has no picture of a course as a whole, but it knows for every 8
## by 8 pixels what a car finds there (game/ground.gd). The road is found
## in that: from where the car starts, all the ground that can be reached
## without crossing a wall or the slow ground along the roads, up to the
## finish line. Where the other cars have a route
## (game/rival.gd; not on the practice course), road away from it is a way
## they do not take, and is shown in another colour.
##
## Finding the road takes a moment, so it is done on a worker thread, and
## the map appears when it is there.

const Rival := preload("res://game/rival.gd")
const Car := preload("res://game/car.gd")
const Ground := preload("res://game/ground.gd")
const PLAYER_CAR := 0x101508
const RIVALS_PRESENT := 0x101222
const COURSES := 7
## Where the map is in the picture and how large it may be, in game pixels:
## at the left, between the time taken and the speed. It is as large as
## fits there in the course's own shape, so a course that goes sideways as
## much as up needs the width, and gets more of it in a picture wider than
## the original's: WIDER for each pixel of the picture's margin, up to
## WIDEST.
const PLACE := Rect2(5, 42, 64, 112)
const WIDER := 0.6
const WIDEST := 150.0
const INSET := 4.0
const PANEL := Color(0.02, 0.03, 0.08, 0.45)
const ROAD := Color(1, 1, 1)
const OTHER_WAY := Color(0.45, 0.9, 1.0)
const EDGE := Color(0, 0, 0, 0.6)
const DRIVEN := Color(1.0, 0.78, 0.1)
const PLAYER := Color(1.0, 0.25, 0.2)
const RIVAL := Color(0.35, 0.75, 1.0)
## Frames it takes to appear.
const FADE_FRAMES := 20.0

## What the course has in a place, for finding the road.
enum {NOTHING, ROADWAY, ROADSIDE, FINISH}
## The ground's codes are for CODE pixels each way, CELL_CODES of them
## across one of the course's cells, in blocks of BLOCK_CODES.
const CODE := 8
const CELL_CODES := 32
const BLOCK_CODES := 16
## Codes below FIRST_ROAD_CODE are walls; those from FIRST_OPEN_CODE on are
## open ground of some surface, which is the roadside if it is slow.
const FIRST_ROAD_CODE := 0x20
const FIRST_OPEN_CODE := 0x40
const SLOW_SURFACES: Array[int] = [8, 9, 10, 11, 12, 13]
## How far behind the start the road is followed, and how far past the
## finish line, in codes.
const BEHIND_START := 40
const PAST_FINISH := 6
## How far around the start a piece of road is looked for, in codes.
const START_SEARCH := 24
## Pixels of the map's picture to a game pixel of the map as PLACE has it,
## and how wide the road is drawn at least, in game pixels. A long course
## would have a road too thin to see.
const PICTURE_DETAIL := 3.0
const LEAST_ROAD := 1.5
## What `_turns` has for no turns either way, in each half of a byte.
const TURN_NONE := 8
## Roughly how wide a road is, in course pixels.
const ROAD_WIDTH := 130.0
## Road further than this from the other cars' route is another way, in
## course pixels.
const OFF_ROUTE := 420.0
## The car's trail gets a point every so many course pixels.
const TRAIL_STEP := 48.0

var machine: NeoGeoMachine
## Screen pixels to a game pixel.
var pixel := 4.0
## How far the original's picture is from the left edge of the one shown,
## in game pixels.
var view_margin := 0
## False hides the map whatever the game shows.
var wanted := true
## False shows it at once, not over FADE_FRAMES calls of `refresh`.
var fades := true

## The course the map is of (or is being made of), the task making it, and
## what it made: a picture of the road, the course pixels of its top left,
## and the size of the course, at which places repeat.
var _course := -1
var _task := -1
var _made := {}
var _road: ImageTexture
## Course pixels to a pixel of that picture.
var _scale := 32.0
var _origin := Vector2.ZERO
var _period := Vector2(65536, 65536)
## For each place of the ground's codes, 0 or how many times the course's
## size it is from where the map has it: see `_make`.
var _turns := PackedByteArray()
var _codes_across := 1
var _start := Vector2.ZERO
var _finish := Vector2.ZERO
var _has_finish := false
var _trail := PackedVector2Array()
## Where each car was last on the map's plane: the player's, then the others'.
var _cars := PackedVector2Array()
var _shown := 0.0


## Call once a frame; `in_race` is true while the game shows a race's HUD.
func refresh(in_race: bool) -> void:
	if machine == null or not in_race or not wanted:
		_shown = 0.0
		visible = false
		if not in_race:
			# the next race starts a map afresh, on the same course too
			_forget()
		return
	if _course < 0:
		_begin()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_take()
	if _road == null:
		visible = false
		return
	_shown = minf(_shown + 1.0 / FADE_FRAMES, 1.0) if fades else 1.0
	visible = true
	modulate.a = _shown
	queue_redraw()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _forget() -> void:
	if _task >= 0:
		return
	_course = -1
	_road = null
	_trail = PackedVector2Array()


## Starts making the map of the course the game is on, from where the
## player's car is.
func _begin() -> void:
	_course = machine.r16(Car.COURSE)
	if _course < 0 or _course >= COURSES:
		return
	var course := {
		"number": _course,
		"across": machine.r16(Ground.CELLS_ACROSS),
		"down": machine.r16(Ground.CELLS_DOWN),
		"cell_map": machine.r32(Ground.CELL_MAP),
		"cell_blocks": machine.r32(Ground.CELL_BLOCKS),
		"start": _car_place(PLAYER_CAR, Car.X, Car.Y),
		"room": _most_room(),
	}
	if course.across <= 0 or course.down <= 0:
		return
	_made = {}
	_task = WorkerThreadPool.add_task(_make.bind(course))
	if not fades:
		# the same picture every time, for screenshots
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_take()


## The most room the map may take, in game pixels.
func _most_room() -> Vector2:
	return Vector2(minf(PLACE.size.x + view_margin * WIDER, WIDEST), PLACE.size.y)


func _take() -> void:
	if _made.is_empty() or _made.number != _course:
		return
	_road = ImageTexture.create_from_image(_made.image)
	_scale = _made.scale
	_origin = _made.origin
	_period = _made.period
	_turns = _made.turns
	_codes_across = _made.codes_across
	_start = _made.start
	_has_finish = _made.has_finish
	_finish = _made.finish
	_trail = PackedVector2Array([_start])
	_cars = PackedVector2Array([_start, _start, _start, _start])


func _car_place(car: int, x: int, y: int) -> Vector2:
	return Vector2(machine.r16(car + x), machine.r16(car + y))


## A place of the game's on the map's own plane, where a course does not
## repeat as the game's places do: the one nearest to `near`.
static func _unwrapped(place: Vector2, near: Vector2, period: Vector2) -> Vector2:
	var apart := place - near
	return near + Vector2(wrapf(apart.x, -period.x / 2, period.x / 2), wrapf(apart.y, -period.y / 2, period.y / 2))


## The same for a place on the road the map shows, which says itself where
## it is; `near` is for a place off it.
static func _on_road(place: Vector2, near: Vector2, period: Vector2, turns: PackedByteArray,
		codes_across: int) -> Vector2:
	var within := place.posmodv(period)
	var turn := turns[int(within.y / CODE) * codes_across + int(within.x / CODE)]
	if turn == 0:
		return _unwrapped(place, near, period)
	return within + Vector2((turn & 0xF) - TURN_NONE, (turn >> 4) - TURN_NONE) * period


## Finds the cars on the map: by the road under them, or else from where
## they last were. Call after every frame of the game, drawn or not.
func follow() -> void:
	if _road == null:
		return
	_cars[0] = _on_road(_car_place(PLAYER_CAR, Car.X, Car.Y), _cars[0], _period, _turns, _codes_across)
	for index in Rival.COUNT:
		var rival := Rival.RIVALS + index * Rival.SIZE
		_cars[index + 1] = _on_road(_car_place(rival, Rival.X, Rival.Y), _cars[index + 1], _period,
				_turns, _codes_across)
	if _trail.is_empty() or _cars[0].distance_to(_trail[-1]) >= TRAIL_STEP:
		_trail.append(_cars[0])


# --- finding the road (on a worker thread; reads the cartridge only) ---------

func _make(course: Dictionary) -> void:
	var across: int = course.across * CELL_CODES
	var down: int = course.down * CELL_CODES
	var kinds := _kinds_of_course(course, across, down)
	var start := Vector2i(course.start / CODE)
	start = _nearest_road(kinds, across, down, Vector2i(posmod(start.x, across), posmod(start.y, down)))
	# every place of road reached, on a plane where the course does not
	# repeat: as its place in `kinds` and its x and y on that plane
	var reached := PackedInt32Array([start.y * across + start.x])
	var xs := PackedInt32Array([start.x])
	var ys := PackedInt32Array([start.y])
	var seen := PackedByteArray()
	seen.resize(across * down)
	seen[reached[0]] = 1
	# a long course goes round the ground more than once across: for each
	# place reached, how many times round it was by then, each way
	var turns := PackedByteArray()
	turns.resize(across * down)
	var finish_y := -0x7FFFFFFF
	var finish_sum := Vector2.ZERO
	var finish_count := 0
	var next := 0
	while next < reached.size():
		var x := xs[next]
		var y := ys[next]
		var kind := kinds[reached[next]]
		turns[reached[next]] = (floori(float(x) / across) + TURN_NONE) | ((floori(float(y) / down) + TURN_NONE) << 4)
		next += 1
		if kind == FINISH:
			# the first met is the course's own: the road goes on past it,
			# to more of the same
			if finish_count == 0:
				finish_y = y
			if absi(y - finish_y) <= PAST_FINISH:
				finish_sum += Vector2(x, y)
				finish_count += 1
			continue
		# not cornerwise: the roadside may be a line one code thick
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var beside_y := y + step.y
			# courses run up the plane: nothing of one is behind its start
			if beside_y > start.y + BEHIND_START:
				continue
			var place := posmod(beside_y, down) * across + posmod(x + step.x, across)
			if seen[place] == 0 and kinds[place] >= ROADWAY and kinds[place] != ROADSIDE:
				seen[place] = 1
				reached.append(place)
				xs.append(x + step.x)
				ys.append(beside_y)
	# the roadway of it, up to the finish line, as a picture
	var top := finish_y - PAST_FINISH
	var bounds := Rect2i(start, Vector2i.ONE)
	for index in reached.size():
		if ys[index] >= top and kinds[reached[index]] != ROADSIDE:
			bounds = bounds.expand(Vector2i(xs[index], ys[index]))
	# a picture PICTURE_DETAIL times as fine as the map is in game pixels
	var most: Vector2 = course.room
	var room := (most - Vector2.ONE * INSET * 2) * PICTURE_DETAIL
	var scale := maxf(maxf(bounds.size.x * CODE / room.x, bounds.size.y * CODE / room.y), CODE)
	var widen := maxi(ceili((LEAST_ROAD * PICTURE_DETAIL - ROAD_WIDTH / scale) / 2), 0)
	var margin := widen + 1
	var size := Vector2i((Vector2(bounds.size) * CODE / scale).ceil()) + Vector2i.ONE * (margin * 2 + 1)
	var origin := Vector2(bounds.position * CODE) - Vector2.ONE * margin * scale
	var cover := PackedByteArray()
	cover.resize(size.x * size.y)
	for index in reached.size():
		if ys[index] >= top:
			var at := Vector2i((Vector2(xs[index], ys[index]) * CODE - origin) / scale)
			cover[at.y * size.x + at.x] = 1
	var period := Vector2(across, down) * CODE
	var route := _rivals_route(course.number, Vector2(start * CODE), period, turns, across)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(margin, size.y - margin):
		for x in range(margin, size.x - margin):
			if cover[y * size.x + x] == 0:
				continue
			var colour := ROAD
			if route.size() > 1:
				var at := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * scale
				if _distance_to_route(route, at) > OFF_ROUTE:
					colour = OTHER_WAY
			for beside_y in range(y - widen, y + widen + 1):
				for beside_x in range(x - widen, x + widen + 1):
					# the road's own colour wins over another way's beside it
					if colour == ROAD or image.get_pixel(beside_x, beside_y).a == 0.0:
						image.set_pixel(beside_x, beside_y, colour)
	_made = {
		"number": course.number,
		"image": image,
		"scale": scale,
		"origin": origin,
		"period": period,
		"turns": turns,
		"codes_across": across,
		"start": Vector2(start * CODE),
		"has_finish": finish_count > 0,
		"finish": finish_sum / maxf(finish_count, 1.0) * CODE,
	}


## What the course has in each of its codes' places, row after row.
func _kinds_of_course(course: Dictionary, across: int, down: int) -> PackedByteArray:
	# every block the course is made of, unpacked
	var blocks := {}
	var cells: int = course.across * course.down
	var block_of_cell := PackedInt32Array()
	block_of_cell.resize(cells * 4)
	for cell in cells:
		var number: int = machine.r16(course.cell_map + cell * 2)
		var parts: int = machine.r32(course.cell_blocks + number * 4)
		for part in 4:
			var packed: int = machine.r32(parts + part * 4)
			block_of_cell[cell * 4 + part] = packed
			if not blocks.has(packed):
				blocks[packed] = _unpacked(packed)
	var surfaces: int = machine.r32(Car.OPEN_GROUND + course.number * 4)
	var kind_of_code := PackedByteArray()
	kind_of_code.resize(0x80)
	for code in range(FIRST_ROAD_CODE, 0x80):
		kind_of_code[code] = ROADWAY
		if code >= FIRST_OPEN_CODE:
			var surface: int = machine.r8(surfaces + (code - FIRST_OPEN_CODE) * 4)
			if surface in SLOW_SURFACES:
				kind_of_code[code] = ROADSIDE
			elif surface == Car.SURFACE_FINISH:
				kind_of_code[code] = FINISH
	for packed: int in blocks:
		var codes: PackedByteArray = blocks[packed]
		for index in codes.size():
			codes[index] = kind_of_code[codes[index] & 0x7F]
		blocks[packed] = codes
	var kinds := PackedByteArray()
	kinds.resize(across * down)
	var filled := 0
	for row in course.down:
		for part_row in 2:
			for line in BLOCK_CODES:
				for column in course.across:
					for part_column in 2:
						var packed := block_of_cell[(row * course.across + column) * 4 + part_row * 2 + part_column]
						var codes: PackedByteArray = blocks[packed]
						for index in BLOCK_CODES:
							kinds[filled + index] = codes[line * BLOCK_CODES + index]
						filled += BLOCK_CODES
	return kinds


## The codes of a packed block (see game/ground.gd).
func _unpacked(packed: int) -> PackedByteArray:
	var codes := PackedByteArray()
	while codes.size() < BLOCK_CODES * BLOCK_CODES:
		var byte: int = machine.r8(packed)
		packed += 1
		if byte < 0x80:
			codes.append(byte)
		elif byte == Ground.PACKED_END:
			break
		else:
			var code: int = machine.r8(packed)
			packed += 1
			for count in byte & 0x7F:
				codes.append(code)
	codes.resize(BLOCK_CODES * BLOCK_CODES)
	return codes


func _nearest_road(kinds: PackedByteArray, across: int, down: int, from: Vector2i) -> Vector2i:
	for reach in START_SEARCH:
		for y in range(-reach, reach + 1):
			for x in range(-reach, reach + 1):
				if maxi(absi(x), absi(y)) == reach \
						and kinds[posmod(from.y + y, down) * across + posmod(from.x + x, across)] == ROADWAY:
					return from + Vector2i(x, y)
	return from


## The other cars' route on the map's plane, from near the start on, or
## nothing where they have none.
func _rivals_route(course: int, start: Vector2, period: Vector2, turns: PackedByteArray,
		codes_across: int) -> PackedVector2Array:
	var route := PackedVector2Array()
	var count: int = machine.r16(Rival.WAYPOINT_COUNTS + course * 2)
	var waypoints: int = machine.r32(Rival.WAYPOINTS + course * 4)
	if course <= 0 or count < 2:
		return route
	var last := start
	for index in count:
		var place := Vector2(machine.r16(waypoints + index * Rival.WAYPOINT_SIZE),
				machine.r16(waypoints + index * Rival.WAYPOINT_SIZE + 2))
		last = _on_road(place, last, period, turns, codes_across)
		route.append(last)
	return route


func _distance_to_route(route: PackedVector2Array, at: Vector2) -> float:
	var least := INF
	for index in route.size() - 1:
		var nearest := Geometry2D.get_closest_point_to_segment(at, route[index], route[index + 1])
		least = minf(least, at.distance_squared_to(nearest))
	return sqrt(least)


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	if _road == null:
		return
	# as large as the room allows, and a panel no larger than the map
	var most := (_most_room() - Vector2.ONE * INSET * 2) * pixel
	var size := Vector2(_road.get_size()) * _scale
	var fit := minf(most.x / size.x, most.y / size.y)
	var box := Rect2(PLACE.position * pixel, size * fit + Vector2.ONE * INSET * 2 * pixel)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(int(3 * pixel))
	panel.anti_aliasing = true
	draw_style_box(panel, box)
	var room := box.grow(-INSET * pixel)
	var corner := room.position
	var place := Rect2(corner, size * fit)
	var on_screen := func(at: Vector2) -> Vector2: return corner + (at - _origin) * fit
	var width := maxf(pixel * 0.7, 1.5)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_texture_rect(_road, Rect2(place.position + offset * width * 0.6, place.size), false, EDGE)
	draw_texture_rect(_road, place, false)
	if _trail.size() >= 2:
		var driven := PackedVector2Array()
		for at in _trail:
			driven.append(on_screen.call(at))
		draw_polyline(driven, DRIVEN, width, true)
	if _has_finish:
		_draw_finish(on_screen.call(_finish), pixel * 1.5)
	if machine.r16(RIVALS_PRESENT) != 0:
		for index in Rival.COUNT:
			var at: Vector2 = on_screen.call(_cars[index + 1])
			if room.grow(pixel * 2).has_point(at):
				draw_circle(at, pixel * 1.6, EDGE, true, -1.0, true)
				draw_circle(at, pixel * 1.1, RIVAL, true, -1.0, true)
	var player_at: Vector2 = on_screen.call(_cars[0])
	draw_circle(player_at, pixel * 2.0, Color.WHITE, true, -1.0, true)
	draw_circle(player_at, pixel * 1.4, PLAYER, true, -1.0, true)


## A chequered square where the finish line is.
func _draw_finish(at: Vector2, half: float) -> void:
	draw_rect(Rect2(at - Vector2.ONE * half * 1.25, Vector2.ONE * half * 2.5), EDGE)
	for index in 4:
		var corner := at + Vector2((index & 1) - 1, (index >> 1) - 1) * half
		draw_rect(Rect2(corner, Vector2.ONE * half), Color.WHITE if index in [0, 3] else Color.BLACK)
