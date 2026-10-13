class_name RaceHud
extends Control
## What a race shows on top of the course, drawn anew at the window's own
## resolution instead of in the original's pixel art: the time taken, the
## time left, the speed, how far it is to the next checkpoint, the stage
## and the warning on slow ground. The values are the game's own
## (game/hud.gd, game/race_clock.gd); while this is shown, the original's
## HUD is left out of the picture (NeoGeoVideo.own_hud).

const Hud := preload("res://game/hud.gd")
const RaceClock := preload("res://game/race_clock.gd")
const TEXT := Color(0.96, 0.97, 1.0)
const FAINT := Color(0.96, 0.97, 1.0, 0.7)
const EDGE := Color(0.02, 0.03, 0.08, 0.85)
const PANEL := Color(0.02, 0.03, 0.08, 0.45)
const SPEED := Color(1.0, 0.8, 0.15)
const TIME_LEFT := Color(0.45, 0.8, 1.0)
const WARNING := Color(1.0, 0.25, 0.2)
const DONE := Color(1.0, 0.8, 0.15)
## Seconds left from which the time left is shown as a warning.
const FEW_SECONDS := 10
## Sizes and places in game pixels: how far in from the picture's edges,
## the sizes of large, medium and small text, and the checkpoint bar's
## top, height and width.
const INSET := 8.0
const LARGE := 26.0
const MEDIUM := 13.0
const SMALL := 8.0
const BAR_TOP := 62.0
const BAR_HEIGHT := 92.0
const BAR_WIDTH := 5.0
## Frames it takes to appear.
const FADE_FRAMES := 20.0
## What the game shows in place of a digit that is not there.
const NO_DIGIT := 0x3A

var machine: NeoGeoMachine
## Screen pixels to a game pixel.
var pixel := 4.0
## False hides it whatever the game shows.
var wanted := true
## False shows it at once, not over FADE_FRAMES calls of `refresh`.
var fades := true

var _shown := 0.0
var _font: FontVariation
var _frames := 0


func _init() -> void:
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 1.0
	_font.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Call once a frame; `in_race` is true while the game shows a race's HUD.
func refresh(in_race: bool) -> void:
	_frames += 1
	if not in_race or not wanted:
		_shown = 0.0
	else:
		_shown = minf(_shown + 1.0 / FADE_FRAMES, 1.0) if fades else 1.0
	visible = _shown > 0.0
	if visible:
		modulate.a = _shown
		queue_redraw()


func _signed16(value: int) -> int:
	return value - 0x10000 if value >= 0x8000 else value


func _signed32(value: int) -> int:
	return value - 0x100000000 if value >= 0x80000000 else value


## Text with its left end, right end (`align` 1) or middle (0.5) at `at`,
## which is on its baseline; all in game pixels. Returns its width.
func _text(text: String, at: Vector2, size: float, colour: Color, align := 0.0) -> float:
	var points := maxi(roundi(size * pixel), 1)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
	var place := Vector2(at.x * pixel - width * align, at.y * pixel).round()
	draw_string_outline(_font, place, text, HORIZONTAL_ALIGNMENT_LEFT, -1, points,
			maxi(roundi(size * pixel * 0.22), 2), EDGE)
	draw_string(_font, place, text, HORIZONTAL_ALIGNMENT_LEFT, -1, points, colour)
	return width / pixel


func _draw() -> void:
	if machine == null:
		return
	var across := size.x / pixel
	var down := size.y / pixel
	_draw_time_taken()
	_draw_time_left(across)
	_draw_speed(down)
	_draw_progress(across)
	_draw_stage(across, down)
	if machine.r16(Hud.SLOW_SIGN) != 0:
		_text("Speed down", Vector2(across / 2, down - INSET - 6), MEDIUM, WARNING, 0.5)


func _draw_time_taken() -> void:
	var frames: int = ((machine.r32(RaceClock.TIME_TAKEN) + 0x8000) & 0xFFFFFFFF) >> 16
	_text("TOTAL", Vector2(INSET, INSET + SMALL), SMALL, FAINT)
	_text("%d'%02d\"%02d" % [frames / Hud.FRAMES_PER_MINUTE,
			frames % Hud.FRAMES_PER_MINUTE / Hud.FRAMES_PER_SECOND,
			frames % Hud.FRAMES_PER_SECOND * 100 / Hud.FRAMES_PER_SECOND],
			Vector2(INSET, INSET + SMALL + MEDIUM + 1), MEDIUM, TEXT)


func _draw_time_left(across: float) -> void:
	var left := _signed32(machine.r32(RaceClock.TIME_LEFT))
	var frames := ((absi(left) + 0x8000) & 0xFFFFFFFF) >> 16
	var seconds := frames / Hud.FRAMES_PER_SECOND
	var colour := TIME_LEFT
	if left < 0x8000:
		colour = WARNING
	elif seconds < FEW_SECONDS and _frames & 0x10:
		colour = TEXT
	var right := across - INSET
	var base := INSET + LARGE
	_text("TIME", Vector2(right, INSET + SMALL), SMALL, FAINT, 1.0)
	var hundredths := ".%02d" % (frames % Hud.FRAMES_PER_SECOND * 100 / Hud.FRAMES_PER_SECOND)
	var width := _text(hundredths, Vector2(right, base), MEDIUM, colour, 1.0)
	_text(("-%d" if left < 0 else "%d") % seconds, Vector2(right - width, base), LARGE, colour, 1.0)


func _draw_speed(down: float) -> void:
	var digits := ""
	for index in 3:
		var digit: int = machine.r8(Hud.SPEED_DIGITS + index)
		if digit != NO_DIGIT:
			digits += char(digit)
	var base := down - INSET - 4
	# the room of three digits, so that the unit stays where it is
	var room := _font.get_string_size("000", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(LARGE * pixel)).x / pixel
	_text(digits, Vector2(INSET + room, base), LARGE, SPEED, 1.0)
	_text("km/h", Vector2(INSET + room + 3, base), SMALL, SPEED)


func _draw_stage(across: float, down: float) -> void:
	var course: int = machine.r16(RaceClock.COURSE)
	_text("PRACTICE" if course == 0 else "STAGE %d" % course,
			Vector2(across - INSET, down - INSET - 4), MEDIUM, TEXT, 1.0)


## A bar that fills from the bottom as the car nears the next checkpoint
## (by the sums of game/hud.gd's show_progress), with which one that is
## above it.
func _draw_progress(across: float) -> void:
	var reached: int = machine.r16(Hud.CHECKPOINTS_REACHED)
	var count: int = machine.r16(Hud.CHECKPOINT_COUNT)
	# how far the car has come since the last checkpoint, of the stretch
	var gone := _signed16(machine.r16(Hud.CHECKPOINT_Y + reached * 2)) - _signed16(machine.r16(Hud.CAR_Y))
	var stretch: int = machine.r16(Hud.STRETCH_LENGTH + reached * 2)
	var part := 0.0
	if gone >= 0:
		gone &= 0xFFFF
		part = 1.0
		if gone <= _signed16(stretch):
			part = clampf(gone / maxf(stretch, 1.0), 0.0, 1.0)
	var middle := across - INSET - 7
	var label := "GOAL" if reached >= count else "CP %d" % (reached + 1)
	_text(label, Vector2(middle, BAR_TOP - 4), SMALL, DONE, 0.5)
	var track := Rect2((middle - BAR_WIDTH / 2) * pixel, BAR_TOP * pixel, BAR_WIDTH * pixel, BAR_HEIGHT * pixel)
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = EDGE
	box.set_border_width_all(maxi(roundi(pixel * 0.5), 1))
	box.set_corner_radius_all(roundi(BAR_WIDTH * pixel / 2))
	box.anti_aliasing = true
	draw_style_box(box, track)
	var inner := track.grow(-pixel)
	var filled := inner.size.y * part
	if filled >= inner.size.x:
		var fill := StyleBoxFlat.new()
		fill.bg_color = DONE
		fill.set_corner_radius_all(roundi(inner.size.x / 2))
		fill.anti_aliasing = true
		draw_style_box(fill, Rect2(inner.position.x, inner.end.y - filled, inner.size.x, filled))
	var marker := Vector2(track.get_center().x, inner.end.y - filled)
	draw_circle(marker, BAR_WIDTH * pixel * 0.9, EDGE, true, -1.0, true)
	draw_circle(marker, BAR_WIDTH * pixel * 0.65, TEXT, true, -1.0, true)
