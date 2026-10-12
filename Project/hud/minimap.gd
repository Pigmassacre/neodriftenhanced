class_name Minimap
extends Control
## A map of the course in a race: the route, where the player's car is on
## it and where the other cars are. Drawn over the game's picture at the
## window's own resolution, not in game pixels.
##
## The game has no map of a course as a whole. The route is the list of
## waypoints the other cars are steered along (game/rival.gd), which the
## practice course does not have: it gets no map.

const Rival := preload("res://game/rival.gd")
const Car := preload("res://game/car.gd")
const PLAYER_CAR := 0x101508
const RIVALS_PRESENT := 0x101222
## Where the map is in the picture and how large, in game pixels: at the
## left, between the time taken and the speed.
const PLACE := Rect2(5, 42, 50, 112)
const INSET := 5.0
const PANEL := Color(0.02, 0.03, 0.08, 0.45)
const ROUTE := Color(1, 1, 1, 0.9)
const ROUTE_EDGE := Color(0, 0, 0, 0.55)
const DRIVEN := Color(1.0, 0.78, 0.1)
const PLAYER := Color(1.0, 0.25, 0.2)
const RIVAL := Color(0.35, 0.75, 1.0)
## Frames it takes to appear.
const FADE_FRAMES := 20.0

var machine: NeoGeoMachine
## Screen pixels to a game pixel.
var pixel := 4.0
## False hides the map whatever the game shows.
var wanted := true
## False shows it at once, not over FADE_FRAMES calls of `refresh`.
var fades := true

## The route of the course it was made for, in course pixels, and for each
## of its points the place the game has it at (which wraps at 65536).
var _course := -1
var _route := PackedVector2Array()
var _places := PackedVector2Array()
var _bounds := Rect2()
var _shown := 0.0


## Call once a frame; `in_race` is true while the game shows a race's HUD.
func refresh(in_race: bool) -> void:
	var course := machine.ram.decode_u16(Car.COURSE & 0xFFFF) if machine != null else -1
	if not in_race or not wanted:
		_shown = 0.0
	else:
		if course != _course:
			_load_route(course)
		_shown = minf(_shown + 1.0 / FADE_FRAMES, 1.0) if fades else 1.0
	visible = _shown > 0.0 and _route.size() > 1
	if visible:
		modulate.a = _shown
		queue_redraw()


func _load_route(course: int) -> void:
	_course = course
	_route = PackedVector2Array()
	_places = PackedVector2Array()
	var rom: PackedByteArray = machine.rom
	var count := rom.decode_u16(Rival.WAYPOINT_COUNTS + course * 2)
	var waypoints: int = machine.r32(Rival.WAYPOINTS + course * 4)
	if course <= 0 or course > 6 or count < 2:
		return
	var at := Vector2.ZERO
	for index in count:
		var place := Vector2(rom.decode_u16(waypoints + index * Rival.WAYPOINT_SIZE),
				rom.decode_u16(waypoints + index * Rival.WAYPOINT_SIZE + 2))
		at = place if index == 0 else at + _apart(_places[-1], place)
		_places.append(place)
		_route.append(at)
	_bounds = Rect2(_route[0], Vector2.ZERO)
	for point in _route:
		_bounds = _bounds.expand(point)


## From one place of the game's to another, the short way round.
func _apart(from: Vector2, to: Vector2) -> Vector2:
	return Vector2(wrapf(to.x - from.x, -32768, 32768), wrapf(to.y - from.y, -32768, 32768))


## Where on the route's own plane a car at `place` is, and the waypoint
## nearest to it.
func _on_route(place: Vector2) -> Array:
	var nearest := 0
	var least := INF
	for index in _places.size():
		var distance := _apart(_places[index], place).length_squared()
		if distance < least:
			least = distance
			nearest = index
	return [_route[nearest] + _apart(_places[nearest], place), nearest]


func _car_place(car: int, x: int, y: int) -> Vector2:
	var ram := machine.ram
	return Vector2(ram.decode_u16((car + x) & 0xFFFF), ram.decode_u16((car + y) & 0xFFFF))


func _draw() -> void:
	if _route.size() < 2:
		return
	var box := Rect2(PLACE.position * pixel, PLACE.size * pixel)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.set_corner_radius_all(int(3 * pixel))
	panel.anti_aliasing = true
	draw_style_box(panel, box)
	var room := box.grow(-INSET * pixel)
	var size := _bounds.size.max(Vector2.ONE)
	var fit := minf(room.size.x / size.x, room.size.y / size.y)
	var origin := room.get_center() - (_bounds.position + size * 0.5) * fit
	var line := PackedVector2Array()
	for point in _route:
		line.append(origin + point * fit)
	var width := maxf(pixel * 0.9, 1.5)
	draw_polyline(line, ROUTE_EDGE, width + pixel * 0.8, true)
	draw_polyline(line, ROUTE, width, true)
	var player: Array = _on_route(_car_place(PLAYER_CAR, Car.X, Car.Y))
	# what has been driven: up to the waypoint behind the car, then the car
	var driven := line.slice(0, maxi(player[1], 1))
	var player_at: Vector2 = origin + player[0] * fit
	driven.append(player_at)
	if driven.size() >= 2:
		draw_polyline(driven, DRIVEN, width, true)
	# the start and the finish
	draw_circle(line[0], width * 0.9, ROUTE, true, -1.0, true)
	draw_circle(line[-1], width * 0.9, ROUTE, true, -1.0, true)
	if machine.ram.decode_u16(RIVALS_PRESENT & 0xFFFF) != 0:
		for index in Rival.COUNT:
			var rival := Rival.RIVALS + index * Rival.SIZE
			var at: Vector2 = origin + _on_route(_car_place(rival, Rival.X, Rival.Y))[0] * fit
			draw_circle(at, pixel * 1.6, ROUTE_EDGE, true, -1.0, true)
			draw_circle(at, pixel * 1.1, RIVAL, true, -1.0, true)
	draw_circle(player_at, pixel * 2.0, Color.WHITE, true, -1.0, true)
	draw_circle(player_at, pixel * 1.4, PLAYER, true, -1.0, true)
