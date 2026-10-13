extends GameRoutines
## The other cars on the course. They are simpler copies of the player's
## car (car.gd): the same grip, sliding and drawing, but steered along a
## list of waypoints, with no damage and no sound, and with the ground under
## them only looked at while they are near the screen.
##
## Register A6 points at one of the three (RIVALS, SIZE bytes each) and A4
## at the player's car, whose camera and zoom they are drawn with.

const Car := preload("res://game/car.gd")
const Sprite := preload("res://game/sprite_object.gd")
const Angles := preload("res://game/angles.gd")

const RIVALS := 0x10126C
const COUNT := 3
const SIZE := 0xD8

# --- a rival's object --------------------------------------------------------

## 1 while it is in the air after a ramp.
const AIRBORNE := 0x00
## 1 when it is on screen, and so drawn.
const ON_SCREEN := 0x02
## The player's zoom, and what it was when the margins were last worked out.
const ZOOM := 0x04
const ZOOM_BEFORE := 0x06
## SIZE_X and SIZE_Y at the current zoom.
const MARGIN_X := 0x08
const MARGIN_Y := 0x0A
const ACCELERATION := 0x0C
const SPEED := 0x0E
## Drawing order, as for the player's car.
const DEPTH := 0x10
const BODY_DEPTH := 0x12
const SHADOW_DEPTH := 0x14
const WHEELS_DEPTH := 0x16
const SLIDE_SIDE := 0x18
const SLIDE := 0x1A
const SLIDING := 0x1C
const HEIGHT := 0x1E
const HEIGHT_ON_SCREEN := 0x20
const CLIMB := 0x22
const TOUCHED_DOWN := 0x24
const GROUND_KIND := 0x26
const SURFACE := 0x28
const GROUND_KIND_BEFORE := 0x2A
const SURFACE_BEFORE := 0x2C
const GROUND_ANGLE := 0x2E
## What its driver does: 0, STEER_LEFT or STEER_RIGHT, and the pedals.
const STEER := 0x30
const STEER_BEFORE := 0x32
const ACCELERATOR := 0x34
const BRAKE := 0x36
const TURN := 0x38
const GRIP := 0x3A
const GROUND_ACCELERATION := 0x42
const GROUND_BRAKING := 0x44
const GROUND_DRAG := 0x46
const DUST_FRAMES := 0x48
const DUST_SIDE := 0x4A
const PICTURE_DIRECTION := 0x4C
## The body jumps up a pixel every fourth frame.
const SHAKE_COUNTDOWN := 0x4E
const SHAKE_PHASE := 0x50
const WHEELS_COUNTDOWN := 0x54
const WHEELS_PHASE := 0x56
const SIZE_X := 0x58
const SIZE_Y := 0x5A
const TURN_TABLE := 0x5C
const GRIP_TABLES := 0x60
const BODY_PICTURES := 0x64
const SHADOW_PICTURES := 0x68
## Three tables: wheels straight, turned one way and turned the other.
const WHEEL_PICTURES := 0x6C
const TOP_SPEED := 0x78
const LOWEST_SPEED := 0x7A
const GROUND_TABLE := 0x7C
const OWN_SURFACE := 0x80
const OWN_DUST_KIND := 0x82
## Position a frame ago and now (16.16 fixed point, in course pixels).
const X_BEFORE := 0x84
const Y_BEFORE := 0x88
const X := 0x8C
const Y := 0x90
## Where its top left is drawn on screen.
const SCREEN_X := 0x94
const SCREEN_Y := 0x98
## The player's camera.
const CAMERA_X := 0xA4
const CAMERA_Y := 0xA6
const TRAVEL := 0xA8
const FACING := 0xAA
const STATE := 0xAC
const BODY_SPRITE := 0xB4
const SHADOW_SPRITE := 0xB8
const WHEELS_SPRITE := 0xBC
const DUST_KIND := 0xC0
## Spinning, as for the player's car.
const SPIN_RATE := 0xC2
const SPIN_TURNED := 0xC6
const SPIN_END := 0xCA
const SPIN_SIDE := 0xCC
## 1 while it is within about two screens of the camera: only then does
## the ground under it matter.
const NEAR := 0xCE
## The waypoint it is heading for.
const WAYPOINT := 0xD0
## Not 0 while it touches the player's car, and the direction of the
## player's side that it touches (taken for a wall).
const TOUCHING := 0xD2
const TOUCH_ANGLE := 0xD4
## How far down the screen its centre is.
const SCREEN_DEPTH := 0xD6

const WALL := 0
const EDGE := 1
const OPEN := 2
const STEER_LEFT := 1
const STEER_RIGHT := 2
const SURFACE_TAKE_OFF := 6
const SURFACE_SLOW_FIRST := 8
const SURFACE_SLOW_LAST := 13
const SURFACE_RAMP := 17
const REACT_SLOW := 2
const REACT_BOUNCE := 4
const STATE_START := 0
const STATE_DRIVING := 1
const STATE_START_SPIN_AHEAD := 2
const STATE_START_SPIN := 4
const STATE_SPINNING := 5
const STATE_STOPPING := 6
const STATE_STOPPED := 7
const EFFECT_SPARKS := 6

# --- the rest of the game ----------------------------------------------------

## Which rival is being updated (0 to 2).
const CURRENT := 0x1014F4
## What it looks like: which model of car and which of its colours, and
## the course it is on.
const COURSE_OF := 0xAE
const COLOUR := 0xB0
const MODEL := 0xB2
## The looks of the next car set up, of twelve (two bytes each: model and
## colour). A race takes three in a row from a random place.
const NEXT_LOOKS := 0x1014F6
const LOOKS := 0x206F6
const LOOKS_COUNT := 12
const COURSE := 0x101202
const DIFFICULTY := 0x1011F8
const SEED := 0x100430
## What a car is set up from: addresses of its first $2C words, of the
## $16 words from OWN_SURFACE by course, of the six from SIZE_X by model,
## and of the four from TOP_SPEED by difficulty and model.
const FIRST_FIELDS := 0x209EA
const COURSE_FIELDS := 0x209EE
const MODEL_FIELDS := 0x209F2
const SPEED_FIELDS := 0x209F6
const RIVAL_TOP_SPEED := 0x9FF
## The address of the table of the pictures of each model: five addresses.
const MODEL_PICTURES := 0x80000
## By course: which waypoint each of the three starts at, and the
## waypoints (ten bytes each, x and y first).
const FIRST_WAYPOINTS := 0x21048
## The first of a model's palettes of other colours.
const FIRST_COLOUR_PALETTE := 0xF0
## What touching the player's car left for the player's car to react to.
const CARS_TOUCHING := 0x1014F8
const TOUCHING_ANGLE := 0x1014FA
## Is the rival in A6 within reach of the player's car in A4 (D0)? If so,
## where the two touch (D0, D1).
const CARS_WITHIN_REACH := 0x1A962
## Cars higher up than this touch nothing; nor do cars further apart.
const REACH_HEIGHT := 0x1400
const REACH_X := 0x70
const REACH_Y := 0x50
const WHERE_CARS_TOUCH := 0x1A9A6
## By the rival's direction, three points of it; by the player's car's
## direction, a picture of that car in cells.
const TOUCH_POINTS := 0x1AAD6
const CAR_SHAPES := 0x1AC56
const SHAPE_WIDTH := 0x70
const SHAPE_HEIGHT := 0x50
const SHAPE_COLUMNS := 14
const GROUND_CODE := 0x13E74
const ADD_EFFECT := 0x1458C

## Per course, the waypoints the rivals drive along: x, y, width, height
## of the box that counts as reaching it, and the speed to slow down to
## on the way there. How many there are.
const WAYPOINTS := 0x2101E
const WAYPOINT_SIZE := 10
const WAYPOINT_COUNTS := 0x2103A
## Turn rate while braking, by speed, in 256ths.
const TURN_BRAKING := 0x20676
## Speed kept while sliding, by how wide the slide is.
const SLIDE_SPEED := 0x202F6
const EDGE_ANGLES := 0xCCEE
## Per course, surface and kind of dust for each code of open ground.
const OPEN_GROUND := 0x2070E
## Speed upwards off a ramp, by speed.
const TAKE_OFF_CLIMB := 0xCE66
## The direction a car leaves a wall in, by the wall's angle and its own
## direction (32 of each); bit 7 is set when it keeps its speed.
const BOUNCE := 0x1FEF6
## Frames between puffs of dust and how fast they play, by speed.
const DUST_BY_SPEED := 0x2092A
## Where the rear of the car is, by direction (y, x).
const BEHIND_CAR := 0x209AA
const SHADOW_SIZE_BY_HEIGHT := 0xD370
const SPIN_SIDES := 0xDCC4
const SPIN_LENGTHS := 0xDCE4
const SPIN_RATES := 0xDD24


func routines() -> Dictionary:
	return {
		0xC558: update_all,
		0xC598: update,
		0xC5E0: start_driving,
		0xC5EA: drive,
		0xC66E: start_spin_ahead,
		0xC69E: wait,
		0xC6A4: start_spin,
		0xC71A: spin,
		0xC7A8: stop,
		0xC7B2: stay_stopped,
		0xC814: fly,
		0xC8A8: set_depth,
		0xC8F0: follow_camera,
		0xC904: follow_waypoints,
		0xC9F4: place_on_screen,
		0xCA2E: note_on_screen,
		0xCA58: note_near,
		0x1A962: within_reach,
		0x1A9A6: where_cars_touch,
		0xCE08: func() -> void: m.d0 = with_low16(m.d0, 0),
		0xC34A: set_up_all,
		0xC3A4: set_up,
		0xCA86: func() -> void: _take_pictures(m.a6, low16(m.d0)),
		0xCAA8: look_up_grip,
		0xCAE4: look_up_ground,
		0xCB02: steer,
		0xCBB4: turn,
		0xCC08: sense_ground,
		0xCD2E: ground_effect,
		0xCEA6: react,
		0xCF38: react_spinning,
		0xCFBA: slide,
		0xD080: lose_speed_sliding,
		0xD0AC: accelerate,
		0xD0CC: coast,
		0xD0F8: apply_acceleration,
		0xD102: move,
		0xD142: limit_speed,
		0xD18A: turn_picture,
		0xD1BE: scale_margins,
		0xD1EE: draw_on_ground,
		0xD212: draw_airborne,
		0xD246: draw_body,
		0xD29C: draw_shadow,
		0xD2EA: draw_shadow_airborne,
		0xD3F0: draw_wheels,
		0xD47C: hide_body,
		0xD48A: hide_shadow,
		0xD498: hide_wheels,
		0xD4A6: touch_player,
		0xD4D4: draw_all,
		0xD566: raise_dust_all,
		0xD588: raise_dust,
		0xD63E: throw_sparks,
	}


func scratch() -> Dictionary:
	# Their callers, all here, pass nothing between these in registers but
	# what `ground_effect` returns in D0.
	var free := ["d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a3", "a5", "ccr"]
	var all := {}
	for address: int in routines():
		all[address] = free
	all[0xC558] = ["d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a3", "a4", "a5", "ccr"]
	all[0xCD2E] = ["d0.high", "d1", "d2", "d3", "d6", "d7", "a0", "a1", "a3", "ccr"]
	all[0xD4D4] = ["ccr"]
	all[0x1A962] = ["d0.high", "ccr"]
	for address: int in [0xC34A, 0xC3A4, 0xCA86]:
		all[address] = free + ["a2"]
	all[0xD566] = ["d0", "d1", "d2", "d3", "d7", "a0", "ccr"]
	return all


func variations() -> Dictionary:
	# No recorded session has a rival on screen, in the air, spinning or
	# touching the player's car.
	var seen := func() -> void:
		var player := m.a4
		set16(player + Car.CAMERA_X, u16(m.a6 + X) - 0xA0)
		set16(player + Car.CAMERA_Y, u16(m.a6 + Y) - 0x70)
		set16(m.a6 + ZOOM_BEFORE, 0)
	var state := func(value: int) -> void:
		seen.call()
		set16(m.a6 + STATE, value)
	var touching := func(x: int, y: int, value: int) -> void:
		seen.call()
		var player := m.a4
		set32(player + Car.X, u32(m.a6 + X) + (x << 16))
		set32(player + Car.Y, u32(m.a6 + Y) + (y << 16))
		set16(m.a6 + STATE, value)
	return {
		0xC598: [
			seen,
			state.bind(STATE_START),
			state.bind(STATE_START_SPIN_AHEAD),
			state.bind(STATE_START_SPIN),
			func() -> void:
				state.call(STATE_SPINNING)
				set32(m.a6 + SPIN_RATE, 0x18000)
				set32(m.a6 + SPIN_TURNED, 0x50000)
				set16(m.a6 + SPIN_END, 0x20)
				set16(m.a6 + SPIN_SIDE, -1),
			func() -> void:
				state.call(STATE_SPINNING)
				set32(m.a6 + SPIN_RATE, 0x18000)
				set32(m.a6 + SPIN_TURNED, 0x50000)
				set16(m.a6 + SPIN_END, 6)
				set16(m.a6 + AIRBORNE, 1)
				set16(m.a6 + HEIGHT, 0x10)
				set16(m.a6 + CLIMB, -0x400),
			state.bind(STATE_STOPPING),
			func() -> void:
				seen.call()
				set16(m.a6 + AIRBORNE, 1)
				set16(m.a6 + HEIGHT, 0x1200)
				set16(m.a6 + CLIMB, 0x100),
			func() -> void:
				seen.call()
				set16(m.a6 + AIRBORNE, 1)
				set16(m.a6 + HEIGHT, 0x10)
				set16(m.a6 + CLIMB, -0x400),
			func() -> void:
				seen.call()
				set16(m.a6 + AIRBORNE, 1)
				set16(m.a6 + HEIGHT, 0x10)
				set16(m.a6 + CLIMB, -0x40),
			touching.bind(0, 0, STATE_DRIVING),
			touching.bind(0x18, 0x10, STATE_DRIVING),
			touching.bind(-0x20, 0x8, STATE_START_SPIN),
			touching.bind(0x10, -0x18, STATE_SPINNING),
			func() -> void:
				seen.call()
				set16(m.a6 + SPEED, 0x900)
				set16(m.a6 + SLIDING, 1)
				set16(m.a6 + TOUCHED_DOWN, 1)
				set16(m.a6 + DUST_FRAMES, 0x100),
			func() -> void:
				seen.call()
				set16(m.a6 + FACING, u16(m.a6 + FACING) + 0x5000),
			func() -> void:
				seen.call()
				set16(m.a6 + SPEED, 0x40)
				set16(m.a6 + FACING, u16(m.a6 + FACING) - 0x1800),
		],
		0xD566: [
			func() -> void:
				for index in COUNT:
					var rival := RIVALS + index * SIZE
					set16(rival + NEAR, 1)
					set16(rival + TOUCHED_DOWN, 1)
					set16(rival + SLIDING, index & 1)
					set16(rival + SURFACE, index)
					set16(rival + DUST_FRAMES, 0x100)
					set16(rival + DUST_KIND, 3),
		],
		0xD4D4: [
			func() -> void:
				for index in COUNT:
					set16(RIVALS + index * SIZE + ON_SCREEN, 1),
		],
		0xCC08: [
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + X, u16(m.a6 + X) + 0x30),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + Y, u16(m.a6 + Y) - 0x30),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + X, u16(m.a6 + X) - 0x50)
				set16(m.a6 + Y, u16(m.a6 + Y) + 0x50),
		],
		0xCD2E: [
			func() -> void:
				set16(m.a6 + GROUND_KIND, OPEN)
				set16(m.a6 + SURFACE, SURFACE_TAKE_OFF)
				set16(m.a6 + SURFACE_BEFORE, SURFACE_RAMP)
				set16(m.a6 + SPEED, 0x8C0),
			func() -> void:
				set16(m.a6 + GROUND_KIND, WALL)
				set16(m.a6 + SPEED, 0x980)
				set16(m.a6 + TOUCHED_DOWN, 1)
				set16(m.a6 + GROUND_ANGLE, u16(m.a6 + TRAVEL) + 0x2000),
			func() -> void:
				set16(m.a6 + GROUND_KIND, WALL)
				set16(m.a6 + SPEED, 0x980)
				set16(m.a6 + GROUND_ANGLE, u16(m.a6 + TRAVEL) - 0x7000),
			func() -> void:
				set16(m.a6 + GROUND_KIND, WALL)
				set16(m.a6 + SPEED, 0x980)
				set16(m.a6 + TOUCHING, 1),
		],
		0xCEA6: [
			func() -> void:
				set16(m.a6 + NEAR, 1)
				m.d0 = with_low16(m.d0, REACT_SLOW),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + TOUCHING, 1)
				m.d0 = with_low16(m.d0, REACT_SLOW),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + GROUND_ANGLE, 0x3000)
				m.d0 = with_low16(m.d0, REACT_BOUNCE),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + GROUND_ANGLE, 0xB800)
				set16(m.a6 + SPEED, -0x200)
				m.d0 = with_low16(m.d0, REACT_BOUNCE),
			func() -> void:
				set16(m.a6 + NEAR, 1)
				set16(m.a6 + GROUND_ANGLE, u16(m.a6 + TRAVEL) + 0x4800)
				set16(m.a6 + TOUCHING, 1)
				m.d0 = with_low16(m.d0, REACT_BOUNCE),
		],
		0xD142: [
			func() -> void:
				set16(m.a6 + SURFACE, SURFACE_SLOW_FIRST)
				set16(m.a6 + SPEED, 0x900),
			func() -> void:
				set16(m.a6 + SURFACE, SURFACE_SLOW_LAST)
				set16(m.a6 + ACCELERATOR, 0)
				set16(m.a6 + SPEED, 0x900),
			func() -> void:
				set16(m.a6 + SURFACE, SURFACE_SLOW_LAST)
				set16(m.a6 + SPEED, -0x900),
		],
	}


## $C558: a frame of all three. A6 is the player's car.
func update_all() -> void:
	m.a5 = 0x108000
	if u16(Car.COURSE) == 0:
		return
	var player := m.a6
	var kept := m.d0
	set16(CARS_TOUCHING, 0)
	set16(TOUCHING_ANGLE, 0)
	m.a4 = player
	for index in COUNT:
		set16(CURRENT, index)
		m.a6 = RIVALS + index * SIZE
		update()
	m.a6 = player
	m.d0 = kept


## $C598
func update() -> void:
	var rival := m.a6
	if u16(rival + AIRBORNE) == 1:
		fly()
	match u16(rival + STATE):
		STATE_START:
			start_driving()
		STATE_DRIVING:
			drive()
		STATE_START_SPIN_AHEAD:
			start_spin_ahead()
		STATE_START_SPIN:
			start_spin()
		STATE_SPINNING:
			spin()
		STATE_STOPPING:
			stop()
		_:
			wait()
	set_depth()


## $C5E0
func start_driving() -> void:
	set16(m.a6 + STATE, STATE_DRIVING)
	drive()


## $C5EA: a frame of driving.
func drive() -> void:
	var rival := m.a6
	follow_camera()
	place_on_screen()
	note_on_screen()
	note_near()
	scale_margins()
	sense_ground()
	ground_effect()
	react()
	if u16(rival + AIRBORNE) == 0:
		look_up_grip()
		look_up_ground()
		steer()
		turn()
		accelerate()
		apply_acceleration()
	slide()
	if u16(rival + AIRBORNE) == 0:
		lose_speed_sliding()
	turn_picture()
	if u16(rival + AIRBORNE) == 0:
		limit_speed()
	move()
	follow_waypoints()
	if u16(rival + AIRBORNE) == 0:
		draw_on_ground()
	else:
		draw_airborne()


## $C66E: starts a spin of twenty 32nds of a turn from the way it faces.
func start_spin_ahead() -> void:
	var rival := m.a6
	var start := _direction(u16(rival + FACING))
	set32(rival + SPIN_TURNED, start << 16)
	set16(rival + SPIN_END, start + 0x280)
	set32(rival + SPIN_RATE, 0x28000)
	set16(rival + STATE, STATE_SPINNING)
	spin()


## $C69E, $C7B2: nothing happens to it.
func wait() -> void:
	m.d0 = with_low16(m.d0, 1)


## $C7B2
func stay_stopped() -> void:
	wait()


## $C6A4: starts a spin after hitting a wall or the player's car. Which way
## round goes by its direction, how long and how fast by its speed (after
## the player's car: by how fast the two close in).
func start_spin() -> void:
	var rival := m.a6
	var player := m.a4
	set16(rival + SPIN_SIDE, rom_s8(SPIN_SIDES + _direction(u16(rival + TRAVEL))))
	var speed := s16(rival + SPEED)
	if u16(rival + TOUCHING) != 0:
		var angle := ((u16(player + Car.TRAVEL) - u16(rival + TRAVEL)) & 0xFFFF) >> 6
		var along := (rom_s16(Car.SINE + ((angle + 0x100) & 0x3FF) * 2) * s16(player + Car.SPEED)) >> 8
		speed = wrap16(along - speed)
	var step := ((Car._magnitude(speed) & 0xFFFF) >> 7) & 0x1F
	var start := _direction(u16(rival + FACING))
	set32(rival + SPIN_TURNED, start << 16)
	set16(rival + SPIN_END, start + rom_u16(SPIN_LENGTHS + step * 2))
	set32(rival + SPIN_RATE, rom_u32(SPIN_RATES + step * 4))
	set16(rival + STATE, STATE_SPINNING)
	spin()


## $C71A: a frame of spinning: the picture turns while the car rolls out.
func spin() -> void:
	var rival := m.a6
	follow_camera()
	place_on_screen()
	note_on_screen()
	note_near()
	scale_margins()
	sense_ground()
	ground_effect()
	react_spinning()
	set32(rival + SPIN_TURNED, u32(rival + SPIN_TURNED) + u32(rival + SPIN_RATE))
	if s16(rival + SPIN_END) <= s16(rival + SPIN_TURNED):
		start_driving()
		return
	var direction := u16(rival + SPIN_TURNED) & 0x1F
	if s16(rival + SPIN_SIDE) == -1:
		direction = (0x20 - direction) & 0x1F
	set16(rival + PICTURE_DIRECTION, direction)
	if u16(rival + AIRBORNE) == 0:
		coast()
		apply_acceleration()
		limit_speed()
	move()
	follow_waypoints()
	if u16(rival + AIRBORNE) == 0:
		draw_on_ground()
	else:
		draw_airborne()


## $C7A8
func stop() -> void:
	set16(m.a6 + STATE, STATE_STOPPED)
	wait()


## $C814: up and down after a ramp. It bounces on landing, each time half as
## high (a quarter while spinning), and for that one frame its wheels grip.
func fly() -> void:
	var rival := m.a6
	set16(rival + TOUCHED_DOWN, 0)
	set16(rival + STEER, 0)
	set16(rival + STEER_BEFORE, 0)
	set16(rival + TURN, 0)
	var climb := wrap16(s16(rival + CLIMB) - 0x20)
	set16(rival + CLIMB, climb)
	var height := wrap16(s16(rival + HEIGHT) + climb)
	set16(rival + HEIGHT, height)
	if height > 0:
		return
	set16(rival + TOUCHED_DOWN, 1)
	climb = wrap16(-climb)
	set16(rival + CLIMB, climb)
	if climb <= 0x80:
		set16(rival + HEIGHT, 0)
		set16(rival + HEIGHT_ON_SCREEN, 0)
		set16(rival + AIRBORNE, 0)
		return
	# dust at once
	set16(rival + DUST_FRAMES, 0x7FF0)
	steer()
	turn()
	look_up_grip()
	look_up_ground()
	accelerate()
	set16(rival + ACCELERATION, u16(rival + ACCELERATION) << 4)
	apply_acceleration()
	limit_speed()
	climb >>= 1
	if u16(rival + STATE) == STATE_SPINNING:
		climb >>= 1
	set16(rival + HEIGHT, 0)
	set16(rival + CLIMB, climb)


## $C8A8: how far down the screen it is decides what is drawn over it.
func set_depth() -> void:
	var rival := m.a6
	if u16(rival + ON_SCREEN) == 0:
		return
	var depth := u16(rival + SCREEN_DEPTH) + u16(rival + DEPTH) + u16(rival + HEIGHT_ON_SCREEN)
	set16(u32(rival + BODY_SPRITE) + Sprite.DEPTH, depth + u16(rival + BODY_DEPTH))
	set16(u32(rival + WHEELS_SPRITE) + Sprite.DEPTH, depth + u16(rival + WHEELS_DEPTH))
	set16(u32(rival + SHADOW_SPRITE) + Sprite.DEPTH, depth + u16(rival + SHADOW_DEPTH))


## $C8F0: takes over the player's zoom and camera.
func follow_camera() -> void:
	var rival := m.a6
	var player := m.a4
	set16(rival + ZOOM, u16(player + Car.ZOOM))
	set16(rival + CAMERA_X, u16(player + Car.CAMERA_X))
	set16(rival + CAMERA_Y, u16(player + Car.CAMERA_Y))


## $C904: when it reaches the waypoint it is heading for, it heads for the
## next (the list goes round the course). The first time, it is put on the
## first one. Should it find itself two waypoints back, it heads for the
## one before again.
func follow_waypoints() -> void:
	var rival := m.a6
	m.a5 = 0x108000
	var course := u16(Car.COURSE)
	var waypoints := rom_u32(WAYPOINTS + wrap16(course * 4))
	var heading_for := u16(rival + WAYPOINT)
	if heading_for == 0:
		set16(rival + X, rom_u16(waypoints))
		set16(rival + Y, rom_u16(waypoints + 2))
		set16(rival + WAYPOINT, 1)
		set16(rival + SPEED, 0xA)
		return
	var waypoint := waypoints + wrap16(heading_for * WAYPOINT_SIZE)
	if _is_at(rival, waypoint):
		heading_for = (heading_for + 1) & 0xFFFF
		if rom_u16(WAYPOINT_COUNTS + wrap16(course * 2)) <= heading_for:
			heading_for = 0
		set16(rival + WAYPOINT, heading_for)
	elif heading_for > 1 and _is_at(rival, waypoint - 2 * WAYPOINT_SIZE):
		set16(rival + WAYPOINT, heading_for - 1)


func _is_at(rival: int, waypoint: int) -> bool:
	var width := rom_u16(waypoint + 4)
	var height := rom_u16(waypoint + 6)
	var x := (u16(rival + X) - rom_u16(waypoint) + (width >> 1)) & 0xFFFF
	var y := (u16(rival + Y) - rom_u16(waypoint + 2) + (height >> 1)) & 0xFFFF
	return x < width and y < height


## $C9F4: where on screen it is, through the player's camera.
func place_on_screen() -> void:
	var rival := m.a6
	var zoom := s16(rival + ZOOM)
	var x := (wrap16(u16(rival + X) - u16(rival + CAMERA_X)) * zoom) >> 8
	var y := (wrap16(u16(rival + Y) - u16(rival + CAMERA_Y)) * zoom) >> 8
	set16(rival + SCREEN_DEPTH, y)
	set16(rival + SCREEN_X, x - u16(rival + SIZE_X) + u16(rival + MARGIN_X))
	set16(rival + SCREEN_Y, y - u16(rival + SIZE_Y) + u16(rival + MARGIN_Y))


## $CA2E: is any of it on the 320 by 224 screen, or what more of it is drawn?
func note_on_screen() -> void:
	var rival := m.a6
	var x := (u16(rival + SCREEN_X) + 0x60 + m.view_margin) & 0xFFFF
	var y := (u16(rival + SCREEN_Y) + 0x40) & 0xFFFF
	set16(rival + ON_SCREEN, 1 if x <= 0x1A0 + m.view_margin * 2 and y <= 0x140 else 0)


## $CA58: is it within 800 pixels across and 384 down of the camera?
func note_near() -> void:
	var rival := m.a6
	var x := (u16(rival + X) - u16(rival + CAMERA_X) + 0x31F) & 0xFFFF
	var y := (u16(rival + Y) - u16(rival + CAMERA_Y) + 0x17F) & 0xFFFF
	set16(rival + NEAR, 1 if x <= 0x640 and y <= 0x300 else 0)


## $CAA8: its grip on the ground it is on at its speed.
func look_up_grip() -> void:
	var rival := m.a6
	var surface := u16(rival + (SURFACE if u16(rival + NEAR) != 0 else OWN_SURFACE))
	var table := m.r32(u32(rival + GRIP_TABLES) + wrap16(surface * 4))
	var entry := table + (((Car._magnitude(s16(rival + SPEED)) & 0xFFFF) >> 5) & 0xFFF8)
	set32(rival + GRIP, m.r32(entry))
	set32(rival + GRIP + 4, m.r32(entry + 4))


## $CAE4: acceleration, braking and drag on new ground.
func look_up_ground() -> void:
	var rival := m.a6
	var surface := u16(rival + SURFACE)
	if surface == u16(rival + SURFACE_BEFORE):
		return
	var entry := u32(rival + GROUND_TABLE) + wrap16(surface << 3)
	set32(rival + GROUND_ACCELERATION, m.r32(entry))
	set16(rival + GROUND_DRAG, m.r16(entry + 4))


## $CB02: its driver steers towards the waypoint (more coarsely once close
## to it), and brakes while faster than the waypoint asks for.
func steer() -> void:
	var rival := m.a6
	var waypoint := rom_u32(WAYPOINTS + wrap16(u16(Car.COURSE) * 4)) + wrap16(u16(rival + WAYPOINT) * WAYPOINT_SIZE)
	var x := wrap16(rom_u16(waypoint) - u16(rival + X))
	var y := wrap16(rom_u16(waypoint + 2) - u16(rival + Y))
	var off := Angles.towards(m, x, y) - (((u16(rival + FACING) + 0x80) & 0xFFFF) >> 8)
	var across := absi(x)
	var down := absi(y)
	if across * across + down * down < 0x3000:
		off = (off + 8) & 0xF0
	else:
		off = (off + 2) & 0xFC
	if off & 0x80:
		set16(rival + STEER, STEER_LEFT)
	elif off == 0:
		set16(rival + STEER, 0)
	else:
		set16(rival + STEER, STEER_RIGHT)
	var brakes := s16(rival + SPEED) > rom_s16(waypoint + 8)
	set16(rival + ACCELERATOR, 0 if brakes else 1)
	set16(rival + BRAKE, 1 if brakes else 0)


## $CBB4: how far the steering turns it this frame.
func turn() -> void:
	var rival := m.a6
	var rate := 0
	if u16(rival + STEER) != 0:
		var step := ((Car._magnitude(s16(rival + SPEED)) & 0xFFFF) >> 3) & 0xFFFE
		rate = m.r16(u32(rival + TURN_TABLE) + wrap16(step))
		if u16(rival + BRAKE) == 1:
			rate = ((rate * rom_u16(TURN_BRAKING + ((step >> 2) & 0xFFFE)) + 0x50) >> 8) & 0xFFFF
		if u16(rival + STEER) != STEER_RIGHT:
			rate = -rate
	set16(rival + TURN, rate)


## $CC08: what the course has where it is: a wall, an edge or open ground.
## Far from the screen it is taken to be on plain road. The player's car
## counts as a wall.
func sense_ground() -> void:
	var rival := m.a6
	set16(rival + SURFACE_BEFORE, u16(rival + SURFACE))
	if u16(rival + NEAR) == 0:
		set16(rival + SURFACE, 0)
		set16(rival + GROUND_ANGLE, 0)
		set16(rival + GROUND_KIND, OPEN)
		return
	m.d0 = with_low16(m.d0, u16(rival + X))
	m.d2 = with_low16(m.d2, u16(rival + Y))
	m.call_routine(GROUND_CODE)
	var code := m.d0 & 0x7F
	if u16(rival + WAYPOINT) == 1 and code == 0xE:
		code = 0x7F
	touch_player()
	if u16(rival + TOUCHING) != 0:
		code = s16(rival + TOUCH_ANGLE)
	if code <= 0x1F:
		set16(rival + GROUND_KIND_BEFORE, u16(rival + GROUND_KIND))
		set16(rival + GROUND_ANGLE, ((code & 0xFFFF) >> 5) | (code << 11))
		set16(rival + GROUND_KIND, WALL)
		set16(rival + SURFACE, u16(rival + OWN_SURFACE))
		set16(rival + DUST_KIND, u16(rival + OWN_DUST_KIND))
	elif code <= 0x3F:
		set16(rival + GROUND_ANGLE, rom_u16(EDGE_ANGLES + (code - 0x20) * 2))
		set16(rival + GROUND_KIND, EDGE)
		set16(rival + SURFACE, u16(rival + OWN_SURFACE))
		set16(rival + DUST_KIND, u16(rival + OWN_DUST_KIND))
	else:
		var entry := rom_u32(OPEN_GROUND + wrap16(u16(Car.COURSE) * 4)) + (code - 0x40) * 2
		set16(rival + SURFACE, rom_s8(entry))
		set16(rival + GROUND_ANGLE, 0)
		set16(rival + GROUND_KIND, OPEN)
		set16(rival + DUST_KIND, rom_s8(entry + 1))


## $CD2E: what the ground does to it, as a reaction for `react` in D0: a
## ramp throws it into the air, a wall makes it bounce, with sparks when it
## is hit at speed and at an angle.
func ground_effect() -> void:
	var rival := m.a6
	var reaction := 0
	if u16(rival + GROUND_KIND) != WALL:
		if u16(rival + SURFACE) == SURFACE_TAKE_OFF and u16(rival + SURFACE_BEFORE) == SURFACE_RAMP:
			var step := ((Car._magnitude(s16(rival + SPEED)) & 0xFFFF) >> 7) & 0x7F
			set16(rival + CLIMB, rom_u16(TAKE_OFF_CLIMB + step * 2))
			set16(rival + HEIGHT, 0)
			set16(rival + AIRBORNE, 1)
			set16(rival + STEER, 0)
			set16(rival + STEER_BEFORE, 0)
	else:
		reaction = REACT_BOUNCE
		if u16(rival + TOUCHING) == 0 and s16(rival + SPEED) > 0x8FF:
			var apart := Car._angle_between(s16(rival + GROUND_ANGLE), s16(rival + TRAVEL))
			if apart.x <= 0x6660:
				throw_sparks()
	m.d0 = with_low16(m.d0, reaction)


## $CEA6: reacts to the ground as D0 says, if it is near the screen.
func react() -> void:
	var rival := m.a6
	if u16(rival + NEAR) == 0:
		return
	match low16(m.d0):
		REACT_SLOW:
			_slow_down(rival)
		REACT_BOUNCE:
			if not _bounce(rival):
				_slow_down(rival)
			set16(rival + STATE, STATE_START_SPIN)


## $CF38: the same while spinning, which then just goes on.
func react_spinning() -> void:
	var rival := m.a6
	match low16(m.d0):
		REACT_SLOW:
			_slow_down(rival)
		REACT_BOUNCE:
			if not _bounce(rival):
				_slow_down(rival)


## Takes away four tenths of its speed (half against the player's car).
func _slow_down(rival: int) -> void:
	var speed := s16(rival + SPEED)
	if speed >= 0:
		set16(rival + SPEED, ((0x80 if u16(rival + TOUCHING) != 0 else 0x9A) * speed) >> 8)


## Turns it the way it leaves the wall. True if it keeps its speed.
func _bounce(rival: int) -> bool:
	var entry := rom_u8(BOUNCE + _direction(u16(rival + GROUND_ANGLE)) * 32 + _direction(u16(rival + TRAVEL)))
	var direction := entry & 0x1F
	if s16(rival + SPEED) < 0:
		direction = (direction + 0x10) & 0x1F
	set16(rival + TRAVEL, direction << 11)
	set16(rival + FACING, direction << 11)
	return entry & 0x80 != 0


## $CFBA: turns it, then pulls its direction of travel towards the way it
## faces as far as the grip allows.
func slide() -> void:
	var rival := m.a6
	var facing := wrap16(s16(rival + FACING) + s16(rival + TURN))
	set16(rival + FACING, facing)
	var apart := Car._angle_between(facing, s16(rival + TRAVEL))
	var angle := apart.x & 0xFFFF
	var side := apart.y
	set16(rival + SLIDING, 1 if angle > 0x2000 else 0)
	if angle > 0x4000:
		angle = 0x4000
		set16(rival + TRAVEL, facing - 0x4000 + (0x8000 if side < 0 else 0))
	set16(rival + SLIDE_SIDE, side)
	set16(rival + SLIDE, angle)
	if angle < 0x40:
		set16(rival + TRAVEL, facing)
		return
	var pedals := (u16(rival + BRAKE) << 1) | u16(rival + ACCELERATOR)
	var grip := u16(rival + GRIP + wrap16(pedals * 2))
	if u16(rival + GROUND_KIND) == EDGE:
		grip = (grip * 3) & 0xFFFF
	var pull := wrap16((grip * angle + 0x8000) >> 16)
	set16(rival + TRAVEL, s16(rival + TRAVEL) + side * pull)


## $D080: sliding at speed costs some of it.
func lose_speed_sliding() -> void:
	var rival := m.a6
	var speed := s16(rival + SPEED)
	if Car._magnitude(speed) > 0x800:
		var kept := rom_s16(SLIDE_SPEED + (u16(rival + SLIDE) >> 6) * 2)
		set16(rival + SPEED, (kept * speed) >> 8)


## $D0AC
func accelerate() -> void:
	var rival := m.a6
	var change := 0
	if u16(rival + ACCELERATOR) == 1:
		change += u16(rival + GROUND_ACCELERATION)
	if u16(rival + BRAKE) == 1:
		change -= u16(rival + GROUND_BRAKING)
	set16(rival + ACCELERATION, change)


## $D0CC: without pedals it rolls to a stop.
func coast() -> void:
	var rival := m.a6
	var speed := s16(rival + SPEED)
	var drag := u16(rival + GROUND_DRAG)
	if ((speed + drag) & 0xFFFF) <= ((drag * 2) & 0xFFFF):
		set16(rival + ACCELERATION, -speed)
	else:
		set16(rival + ACCELERATION, drag if speed < 0 else -drag)


## $D0F8
func apply_acceleration() -> void:
	var rival := m.a6
	set16(rival + SPEED, s16(rival + SPEED) + s16(rival + ACCELERATION))


## $D102: moves it along its direction of travel.
func move() -> void:
	var rival := m.a6
	set32(rival + X_BEFORE, u32(rival + X))
	set32(rival + Y_BEFORE, u32(rival + Y))
	var angle := u16(rival + TRAVEL) >> 6
	var speed := s16(rival + SPEED)
	set32(rival + X, u32(rival + X) + rom_s16(Car.SINE + ((angle + 0x100) & 0x3FF) * 2) * speed)
	set32(rival + Y, u32(rival + Y) + rom_s16(Car.SINE + angle * 2) * speed)


## $D142: keeps the speed within what the car and the ground allow.
func limit_speed() -> void:
	var rival := m.a6
	var speed := s16(rival + SPEED)
	var surface := s16(rival + SURFACE)
	if surface >= SURFACE_SLOW_FIRST and surface <= SURFACE_SLOW_LAST:
		if speed > 0x6FF:
			if u16(rival + ACCELERATOR) == 1:
				speed = wrap16(speed - u16(rival + GROUND_BRAKING))
			speed = wrap16(speed - 0x12)
	elif speed > s16(rival + TOP_SPEED):
		set16(rival + SPEED, s16(rival + TOP_SPEED))
		return
	set16(rival + SPEED, maxi(speed, s16(rival + LOWEST_SPEED)))


## $D18A: its picture shows the way it faces, leaning into a slide.
func turn_picture() -> void:
	var rival := m.a6
	if u16(rival + ON_SCREEN) == 0:
		return
	var lean := u16(rival + SLIDE)
	var shown := u16(rival + FACING) + (lean if s16(rival + SLIDE_SIDE) >= 0 else -lean)
	set16(rival + PICTURE_DIRECTION, _direction(shown))


## $D1BE: the margins follow the zoom.
func scale_margins() -> void:
	var rival := m.a6
	var zoom := s16(rival + ZOOM)
	if zoom == s16(rival + ZOOM_BEFORE):
		return
	set16(rival + ZOOM_BEFORE, zoom)
	set16(rival + MARGIN_X, Car._margin_at_zoom(zoom, s16(rival + SIZE_X)))
	set16(rival + MARGIN_Y, Car._margin_at_zoom(zoom, s16(rival + SIZE_Y)))


## $D1EE
func draw_on_ground() -> void:
	if u16(m.a6 + ON_SCREEN) == 1:
		draw_body()
		draw_shadow()
		draw_wheels()
	else:
		hide_body()
		hide_shadow()
		hide_wheels()


## $D212
func draw_airborne() -> void:
	var rival := m.a6
	set16(rival + HEIGHT_ON_SCREEN, wrap32(u16(rival + ZOOM) * u16(rival + HEIGHT)) >> 16)
	if u16(rival + ON_SCREEN) == 1:
		draw_body()
		draw_shadow_airborne()
		draw_wheels()
	else:
		hide_body()
		hide_shadow()
		hide_wheels()


## $D246
func draw_body() -> void:
	var rival := m.a6
	var sprite := u32(rival + BODY_SPRITE)
	var zoom := u16(rival + ZOOM)
	Sprite.show(m, sprite, true)
	Sprite.zoom(m, sprite, zoom, zoom)
	Sprite.picture(m, sprite, m.r32(u32(rival + BODY_PICTURES) + wrap16(u16(rival + PICTURE_DIRECTION) * 4)))
	var y := u16(rival + SCREEN_Y) - u16(rival + HEIGHT_ON_SCREEN)
	var countdown := s16(rival + SHAKE_COUNTDOWN) - 1
	if countdown < 0:
		set16(rival + SHAKE_PHASE, ~u16(rival + SHAKE_PHASE))
		countdown = 3
		y -= 1
	set16(rival + SHAKE_COUNTDOWN, countdown)
	Sprite.place(m, sprite, u16(rival + SCREEN_X), y)


## $D29C: the shadow, on the frames on which the player's car has none.
func draw_shadow() -> void:
	var rival := m.a6
	var sprite := u32(rival + SHADOW_SPRITE)
	var zoom := u16(rival + ZOOM)
	Sprite.zoom(m, sprite, zoom, zoom)
	var shown := u16(m.a4 + Car.SHADOW_FLICKER) == 0
	if shown or m.steady_shadows:
		Sprite.picture(m, sprite, m.r32(u32(rival + SHADOW_PICTURES) + wrap16(u16(rival + PICTURE_DIRECTION) * 4)))
		Sprite.place(m, sprite, u16(rival + SCREEN_X), u16(rival + SCREEN_Y))
	Sprite.show(m, sprite, shown)


## $D2EA: the shadow of the car in the air, smaller the higher the car is.
func draw_shadow_airborne() -> void:
	var rival := m.a6
	var sprite := u32(rival + SHADOW_SPRITE)
	var size := rom_u16(SHADOW_SIZE_BY_HEIGHT + ((u16(rival + HEIGHT) >> 8) & 0xFFFE))
	var zoom := ((u16(rival + ZOOM) * size) >> 8) & 0xFFFF
	Sprite.zoom(m, sprite, zoom, zoom)
	var shown := u16(m.a4 + Car.SHADOW_FLICKER) == 0
	if shown or m.steady_shadows:
		Sprite.picture(m, sprite, m.r32(u32(rival + SHADOW_PICTURES) + wrap16(u16(rival + PICTURE_DIRECTION) * 4)))
		var x := u16(rival + SCREEN_X) - u16(rival + MARGIN_X) + Car._margin_at_zoom(wrap16(zoom), s16(rival + SIZE_X))
		var y := u16(rival + SCREEN_Y) - u16(rival + MARGIN_Y) + Car._margin_at_zoom(wrap16(zoom), s16(rival + SIZE_Y))
		Sprite.place(m, sprite, x, y)
	Sprite.show(m, sprite, shown)


## $D3F0: the wheels, turned the way the car slides.
func draw_wheels() -> void:
	var rival := m.a6
	var sprite := u32(rival + WHEELS_SPRITE)
	var zoom := u16(rival + ZOOM)
	Sprite.show(m, sprite, true)
	Sprite.zoom(m, sprite, zoom, zoom)
	if u16(rival + SPEED) != 0:
		var countdown := s16(rival + WHEELS_COUNTDOWN) - 1
		if countdown < 0:
			set16(rival + WHEELS_PHASE, ~u16(rival + WHEELS_PHASE))
			countdown = 1
		set16(rival + WHEELS_COUNTDOWN, countdown)
	var off := (u16(rival + TRAVEL) - u16(rival + FACING) + 0x200) & 0xFC00
	var turned := 0 if off == 0 else (8 if off & 0x8000 else 4)
	var index := wrap16(u16(rival + PICTURE_DIRECTION) << 3)
	if u16(rival + WHEELS_PHASE) != 0:
		index = wrap16(index + 4)
	Sprite.picture(m, sprite, m.r32(u32(rival + WHEEL_PICTURES + turned) + index))
	var y := u16(rival + SCREEN_Y) - u16(rival + HEIGHT_ON_SCREEN)
	if s16(rival + HEIGHT) > 0x800:
		y += 2
	Sprite.place(m, sprite, u16(rival + SCREEN_X), y)


## $D47C
func hide_body() -> void:
	Sprite.show(m, u32(m.a6 + BODY_SPRITE), false)


## $D48A
func hide_shadow() -> void:
	Sprite.show(m, u32(m.a6 + SHADOW_SPRITE), false)


## $D498
func hide_wheels() -> void:
	Sprite.show(m, u32(m.a6 + WHEELS_SPRITE), false)


## $1A9A6: where the rival in A6 touches the player's car in A4. Three
## points of the rival, which depend on its angle, are looked up in a
## picture of the player's car at its angle: 14 by 10 cells of 8 pixels,
## each the angle of the car's side there or negative where the car is
## not. The first of the points that is on the car gives D0 (the angle)
## and D1 (4, 1 or 2: which point); D1 is 0 when none is.
func where_cars_touch() -> void:
	var rival := m.a6
	var player := m.a4
	var dx := (u16(rival + X) - u16(player + Car.X)) & 0xFFFF
	var dy := (u16(rival + Y) - u16(player + Car.Y)) & 0xFFFF
	var points := TOUCH_POINTS + wrap16(u16(rival + PICTURE_DIRECTION) * 12)
	var places: Array[int] = []
	for index: int in [2, 0, 1]:
		var x := (rom_u16(points + index * 4) + dx) & 0xFFFF
		var y := (rom_u16(points + index * 4 + 2) + dy) & 0xFFFF
		places.append((x << 16) | y)
	m.d0 = places[0]
	var shape := rom_u32(CAR_SHAPES + wrap16(u16(player + Car.PICTURE_DIRECTION) * 4))
	var found := 0
	for index in 3:
		var place := places[index]
		if (place >> 16) >= SHAPE_WIDTH or (place & 0xFFFF) >= SHAPE_HEIGHT:
			continue
		var row := (place >> 3) & 0x1FFF
		var cell := (((place >> 19) & 0xFFFF) + row * SHAPE_COLUMNS) & 0xFFFF
		if index == 0:
			m.d0 = (row << 16) | cell
		m.d0 = (m.d0 & 0xFFFFFF00) | rom_u8(shape + cell)
		if m.d0 & 0x80 == 0:
			found = [4, 1, 2][index]
			break
	m.d1 = found


## $D4A6: notes whether it touches the player's car, and tells that car.
func touch_player() -> void:
	var rival := m.a6
	m.a5 = 0x108000
	m.call_routine(CARS_WITHIN_REACH)
	if low16(m.d0) == 0:
		set16(rival + TOUCHING, 0)
		return
	m.call_routine(WHERE_CARS_TOUCH)
	var angle := m.d0 & 0xFF
	if angle >= 0x80:
		angle -= 0x100
	set16(rival + TOUCHING, m.d1)
	set16(rival + TOUCH_ANGLE, angle)
	if low16(m.d1) != 0:
		set16(CARS_TOUCHING, m.d1)
		set16(TOUCHING_ANGLE, angle)


## $D4D4: draws all three where they are, without moving them. A6 is the
## player's car.
func draw_all() -> void:
	if u16(Car.COURSE) == 0:
		return
	var saved := [m.d0, m.d1, m.d2, m.d7, m.a0, m.a3, m.a4, m.a6]
	m.a4 = m.a6
	for index in COUNT:
		set16(CURRENT, index)
		m.a6 = RIVALS + index * SIZE
		draw_on_ground()
	m.d0 = saved[0]; m.d1 = saved[1]; m.d2 = saved[2]; m.d7 = saved[3]
	m.a0 = saved[4]; m.a3 = saved[5]; m.a4 = saved[6]; m.a6 = saved[7]


## $D566
func raise_dust_all() -> void:
	var saved := m.a6
	for index in COUNT:
		m.a6 = RIVALS + index * SIZE
		raise_dust()
	m.a6 = saved


## $D588: dust behind the rear wheels, left and right in turn, the more
## often the faster it goes: always on loose ground, on the road only in a
## wide slide.
func raise_dust() -> void:
	var rival := m.a6
	if u16(rival + NEAR) == 0 or u16(rival + TOUCHED_DOWN) == 0:
		return
	if u16(rival + SURFACE) == 0 and u16(rival + SLIDING) != 1:
		return
	var frames := (u16(rival + DUST_FRAMES) + 1) & 0xFFFF
	set16(rival + DUST_FRAMES, frames)
	var entry := DUST_BY_SPEED + ((u16(rival + SPEED) >> 5) & 0x7C)
	if rom_u16(entry) > frames:
		return
	set16(rival + DUST_FRAMES, 0)
	var kind := u16(rival + DUST_KIND) & 0xFF
	if kind == 0xFF:
		return
	var side := ~u16(rival + DUST_SIDE) & 0xFFFF
	set16(rival + DUST_SIDE, side)
	var direction := (_direction(u16(rival + TRAVEL)) + (0x11 if side == 0 else 0xE)) & 0x1F
	var x := rom_s8(BEHIND_CAR + direction * 2 + 1)
	var y := rom_s8(BEHIND_CAR + direction * 2)
	if u16(rival + SLIDING) == 1:
		x >>= 1
		y >>= 1
	_add_effect(rival, x, y, rom_u16(entry + 2), kind)


## $D63E: sparks behind it.
func throw_sparks() -> void:
	var rival := m.a6
	if u16(rival + TOUCHED_DOWN) == 0:
		return
	var direction := _direction(u16(rival + TRAVEL))
	_add_effect(rival, rom_s8(BEHIND_CAR + direction * 2 + 1), rom_s8(BEHIND_CAR + direction * 2), 0x80, EFFECT_SPARKS)


## Adds an effect at `x`, `y` from the car at 1:1, playing at `speed`.
func _add_effect(rival: int, x: int, y: int, speed: int, kind: int) -> void:
	var zoom := s16(rival + ZOOM)
	m.d0 = with_low16(m.d0, ((x * zoom) >> 8) + u16(rival + X))
	m.d2 = with_low16(m.d2, ((y * zoom) >> 8) + u16(rival + Y))
	m.d1 = with_low16(m.d1, speed)
	m.d3 = with_low16(m.d3, kind)
	m.call_routine(ADD_EFFECT)


## Which of 32 directions an angle is nearest to.
static func _direction(angle: int) -> int:
	return ((angle + 0x400) & 0xFFFF) >> 11


## $C34A: sets up the three other cars of a course. The practice course
## has none.
func set_up_all() -> void:
	if u16(COURSE) == 0:
		return
	var saved := m.a6
	m.a5 = 0x108000
	m.d0 = (u16(SEED) & 0xFF) / LOOKS_COUNT << 16 | (u16(SEED) & 0xFF) % LOOKS_COUNT
	set16(NEXT_LOOKS, (u16(SEED) & 0xFF) % LOOKS_COUNT)
	for index in COUNT:
		set16(CURRENT, index)
		m.a6 = RIVALS + index * SIZE
		m.d7 = with_low16(m.d7, COUNT - 1 - index)
		set_up()
		set16(NEXT_LOOKS, (u16(NEXT_LOOKS) + 1) % LOOKS_COUNT)
	m.d7 = with_low16(m.d7, 0xFFFF)
	m.a6 = saved


## $C3A4: sets up the car in A6, the one numbered CURRENT.
func set_up() -> void:
	var rival := m.a6
	var course := u16(COURSE)
	var looks := LOOKS + u16(NEXT_LOOKS) * 2
	var model := m.r8(looks)
	_copy_words(m.r32(FIRST_FIELDS), rival, 0x2C)
	_copy_words(m.r32(m.r32(COURSE_FIELDS) + course * 4), rival + OWN_SURFACE, 0x16)
	_copy_words(m.r32(m.r32(MODEL_FIELDS) + model * 4), rival + SIZE_X, 6)
	_take_pictures(rival, model)
	_copy_words(m.r32(m.r32(m.r32(SPEED_FIELDS) + u16(DIFFICULTY) * 4) + model * 4), rival + TOP_SPEED, 4)
	set16(rival + TOP_SPEED, RIVAL_TOP_SPEED)
	set16(rival + STATE, STATE_START)
	set16(rival + COURSE_OF, course)
	set16(rival + COLOUR, m.r8(looks + 1))
	set16(rival + MODEL, model)
	set16(rival + DUST_KIND, u16(rival + OWN_DUST_KIND))
	look_up_grip()
	look_up_ground()
	var waypoint := m.r8(m.r32(FIRST_WAYPOINTS + course * 4) + u16(CURRENT))
	set16(rival + WAYPOINT, waypoint)
	var entry := m.r32(WAYPOINTS + course * 4) + waypoint * WAYPOINT_SIZE
	set16(rival + X, m.r16(entry))
	set16(rival + Y, m.r16(entry + 2))
	var facing := Angles.towards(m, wrap16(m.r16(entry + WAYPOINT_SIZE) - m.r16(entry)),
			wrap16(m.r16(entry + WAYPOINT_SIZE + 2) - m.r16(entry + 2))) << 8
	set16(rival + TRAVEL, facing)
	set16(rival + FACING, facing)
	# each a little in front of the one before
	set16(rival + DEPTH, u16(rival + DEPTH) + u16(CURRENT) * 4)
	var body := Sprite.take_record(m)
	set32(rival + BODY_SPRITE, body)
	set16(body + Sprite.DEPTH, u16(rival + BODY_DEPTH) + u16(rival + DEPTH))
	set16(body + Sprite.PALETTE, (model * 4 + FIRST_COLOUR_PALETTE + u16(rival + COLOUR)) | 0xFF00)
	var wheels := Sprite.take_record(m)
	set32(rival + WHEELS_SPRITE, wheels)
	set16(wheels + Sprite.DEPTH, u16(rival + WHEELS_DEPTH) + u16(rival + DEPTH))
	var shadow := Sprite.take_record(m)
	set32(rival + SHADOW_SPRITE, shadow)
	set16(shadow + Sprite.DEPTH, u16(rival + SHADOW_DEPTH) + u16(rival + DEPTH))
	scale_margins()
	draw_on_ground()


func _copy_words(from: int, to: int, count: int) -> void:
	for index in count:
		set16(to + index * 2, m.r16(from + index * 2))


## $CA86: the pictures of a model of car.
func _take_pictures(rival: int, model: int) -> void:
	var pictures := m.r32(m.r32(MODEL_PICTURES) + wrap16(model * 4))
	for index in 5:
		set32(rival + BODY_PICTURES + index * 4, m.r32(pictures + index * 4))


## $1A962: leaves 1 in D0 if the car in A6 and the player's car in A4 are
## both low enough and near enough to touch, else 0.
func within_reach() -> void:
	var rival := m.a6
	var car := m.a4
	var near := s16(car + Car.HEIGHT) <= REACH_HEIGHT and s16(rival + HEIGHT) <= REACH_HEIGHT \
			and ((u16(rival + X) - u16(car + Car.X) + REACH_X) & 0xFFFF) < REACH_X * 2 \
			and ((u16(rival + Y) - u16(car + Car.Y) + REACH_Y) & 0xFFFF) < REACH_Y * 2
	m.d0 = with_low16(m.d0, 1 if near else 0)
