extends GameRoutines
## The car: one frame of driving, from the controls to the camera.
##
## Every routine here works on the car object that register A6 points at
## (the player's car is at $101500). The main routine of the normal driving
## state ($DAAC) calls them in the order they appear here.
##
## Field names are what the code here shows them to be used for; fields only
## seen in passing keep their offset as a name.

const Sprite := preload("res://game/sprite_object.gd")
const Random := preload("res://game/random.gd")

# --- the car object ----------------------------------------------------------

## 1 once the car has crossed the finish line: the controls and the camera
## let go of it. How often it crossed.
const FINISHED := 0x00
const FINISH_CROSSINGS := 0x02
## 1 while the car is in the air after a ramp.
const AIRBORNE := 0x04
## 1 when the car is drawn.
const DRAWN := 0x06
## Zoom the speed asks for, the zoom shown (8.8 fixed point, $100 = 1:1),
## and the zoom shown the frame before.
const ZOOM_TARGET := 0x08
const ZOOM := 0x0A
const ZOOM_BEFORE := 0x0C
## SIZE_X and SIZE_Y at the current zoom.
const MARGIN_X := 0x0E
const MARGIN_Y := 0x10
## Change of speed this frame, and the speed (signed, about 1/256 pixel a frame).
const ACCELERATION := 0x12
const SPEED := 0x14
## Drawing order: added to the car's y on screen for all of the car, and
## for the body, the shadow and the wheels on top of that.
const DEPTH := 0x16
const BODY_DEPTH := 0x18
const SHADOW_DEPTH := 0x1A
const WHEELS_DEPTH := 0x1C
## Slide: which way the car faces relative to where it travels (1 or -1),
## how far apart the two are, and whether that is more than an eighth turn.
const SLIDE_SIDE := 0x1E
const SLIDE := 0x20
const SLIDING := 0x22
const FIELD_24 := 0x24
## Height above the ground, the same on screen, and the speed upwards.
const HEIGHT := 0x26
const HEIGHT_ON_SCREEN := 0x28
const CLIMB := 0x2A
## 1 once the car has come down after a jump (0 while it is still up).
const TOUCHED_DOWN := 0x2C
## What the car is on: WALL, EDGE or OPEN ground. The kind a frame ago.
const GROUND_KIND := 0x2E
## Ground under the car, and the frame before.
const SURFACE := 0x30
const GROUND_KIND_BEFORE := 0x32
const SURFACE_BEFORE := 0x34
## The angle of the wall touched, or the direction an edge runs in.
const GROUND_ANGLE := 0x36
## Controls: 0, STEER_LEFT or STEER_RIGHT; the frame before; pedals (0 or 1).
const STEER := 0x38
const STEER_BEFORE := 0x3A
const ACCELERATOR := 0x3C
const BRAKE := 0x3E
## Change of facing this frame.
const TURN := 0x40
## Grip on this ground at this speed, by pedals (none, accelerator, brake, both).
const GRIP := 0x42
## This ground's acceleration, braking and rolling resistance.
const GROUND_ACCELERATION := 0x4A
const GROUND_BRAKING := 0x4C
const GROUND_DRAG := 0x4E
## Frames since the wheels last raised dust, and a flag that flips so the
## dust comes from the left and the right rear wheel in turn.
const DUST_FRAMES := 0x50
const DUST_SIDE := 0x52
## Which of 32 directions the car's picture shows.
const PICTURE_DIRECTION := 0x54
const SIZE_X := 0x60
const SIZE_Y := 0x62
## Rough ground shakes the car: frames until the body next jumps up for a
## frame, and a flag that flips each time it does.
const SHAKE_COUNTDOWN := 0x56
const SHAKE_PHASE := 0x58
## Flips every frame; the shadow is only drawn on every other one, which
## passes for a see-through shadow.
const SHADOW_FLICKER := 0x5A
## The wheels show one of two pictures, swapped every other frame while moving.
const WHEELS_COUNTDOWN := 0x5C
const WHEELS_PHASE := 0x5E
## Pictures by direction: the body, the shadow, and the wheels for each way
## of steering (two pictures for each direction).
const BODY_PICTURES := 0x6C
const SHADOW_PICTURES := 0x70
const WHEEL_PICTURES := 0x74
## The car's tables: turn rate by speed, grip by ground and speed, ground properties.
const TURN_TABLE := 0x64
const GRIP_TABLES := 0x68
const TOP_SPEED := 0x80
const LOWEST_SPEED := 0x82
const ROUGH_SPEED := 0x84
const GROUND_TABLE := 0x86
## Three more stages of damage: scrapes it takes, then TOP_SPEED and
## ROUGH_SPEED from there on (four words each, the first set unused).
const DAMAGE_STAGES := 0x8A
## What the car has under it when it is not on open ground.
const OWN_SURFACE := 0xB2
const OWN_DUST_KIND := 0xB4
const OWN_SHAKE_KIND := 0xB6
## Position a frame ago and now (16.16 fixed point, in course pixels).
const X_BEFORE := 0xB8
const Y_BEFORE := 0xBC
const X := 0xC0
const Y := 0xC4
## Where the car is drawn on screen (16.16), and where it is heading for.
const SCREEN_X := 0xC8
const SCREEN_Y := 0xCC
const SCREEN_X_WANTED := 0xD0
const SCREEN_Y_WANTED := 0xD4
## The course position at the screen's top left.
const CAMERA_X := 0xD8
const CAMERA_Y := 0xDA
## Direction of travel and direction the car faces ($10000 is a full turn).
const TRAVEL := 0xDC
const FACING := 0xDE
const SHAKE_KIND := 0xE0
const ROUGH := 0xE2
const STATE := 0xE4
const SECOND_PLAYER := 0xE8
## The sprite objects the car is drawn with (see sprite_object.gd).
const BODY_SPRITE := 0xEC
const SHADOW_SPRITE := 0xF0
const WHEELS_SPRITE := 0xF4
## The kind of effect the wheels raise on this ground ($FF for none).
const DUST_KIND := 0xF8
## Steering history: the two earlier steering inputs, and for how many
## frames the current and the two before it were held.
const STEER_EARLIER := 0xFA
const STEER_EARLIEST := 0xFC
const STEER_HELD := 0xFE
const STEER_HELD_EARLIER := 0x100
const STEER_HELD_EARLIEST := 0x102
const SPUN := 0x104
const SPUN_FRAMES := 0x106
const SPEED_BEFORE := 0x108
const AIRBORNE_BEFORE := 0x10A
## The ground code under the car, and a frame ago.
const GROUND_CODE := 0x10C
const GROUND_CODE_BEFORE := 0x10E
## The direction the car's picture is turning towards PICTURE_DIRECTION from.
const PICTURE_ANGLE := 0x110
const FIELD_114 := 0x114
const FRAMES_SINCE_KNOCK := 0x116
## The camera position the course was last drawn for.
const CAMERA_X_DRAWN := 0x118
const CAMERA_Y_DRAWN := 0x11A
## 0 steady, 1 gaining speed, 2 losing it.
const SPEED_TREND := 0x11C
## 1 while the car gains speed from nearly standing: the tyres squeal.
## For how many frames it has gained speed. The former a frame ago.
const PULLING_AWAY := 0x11E
const FRAMES_GAINING := 0x120
const PULLING_AWAY_BEFORE := 0x122
const TOUCHED_WALL := 0x124
const SCRAPED_WALL := 0x126
const TOUCHED_WALL_BEFORE := 0x128
const SCRAPED_WALL_BEFORE := 0x12A
## Scraping along walls wears the car down: scrapes left until the next
## stage of damage, and the stage (0 to 4).
const SCRAPES_LEFT := 0x12C
const DAMAGE := 0x12E
const SLOW_GROUND := 0x130
const STARTING := 0x132
const START_FRAMES := 0x134
const FRAMES_SINCE_BOUNCE := 0x136
## How often rough ground shakes the car (frames less one) and how far.
const SHAKE_PERIOD := 0x138
const SHAKE_HEIGHT := 0x13A
## Frames until the tyres may next leave skid marks.
const SKID_COUNTDOWN := 0x13C
## The exhaust backfires after a long pull away: 1 while it does, frames
## until the next bang, and where the list of the waits between them is.
const BACKFIRING := 0x13E
const BACKFIRE_COUNTDOWN := 0x140
const BACKFIRE_WAITS := 0x142
## Spinning: turn a frame, how far it has turned and how far it will (16.16
## and whole, in 32nds of a turn), and which way (1 or -1).
const SPIN_RATE := 0x146
const SPIN_TURNED := 0x14A
const SPIN_END := 0x14E
const SPIN_SIDE := 0x150
## Frames left to drive on after the finish.
const FRAMES_AFTER_FINISH := 0x152
const SPEED_BEFORE_BOUNCE := 0x154

const WALL := 0
const EDGE := 1
const OPEN := 2
const STEER_LEFT := 1
const STEER_RIGHT := 2
## Surfaces that do something to the car (see `ground_effect`).
const SURFACE_TAKE_OFF := 6
const SURFACE_FINISH := 7
const SURFACE_GATE_FIRST := 15
const SURFACE_GATE_SECOND := 16
const SURFACE_RAMP := 17
## What `ground_effect` asks `react` to do.
const REACT_NOT := 0
const REACT_SLOW := 2
const REACT_BOUNCE := 4
const STATE_DRIVING := 1
const STATE_04 := 4
const STATE_SPINNING := 5
const STATE_SPUN := 0xB

# --- the rest of the game ----------------------------------------------------

## Checkpoints reached, and gates passed (going back over one takes it off again).
const CHECKPOINTS := 0x101502
const GATES_PASSED := 0x101504
const FRAMES_SINCE_SQUEAL := 0x10167A
const FRAMES_SINCE_SCRAPE_SOUND := 0x10167C
const FRAMES_SINCE_BRAKE_SOUND := 0x10167E
const FRAMES_SINCE_SLIDE_SOUND := 0x101680
## Bit 0 of the first byte stops the clock.
const CLOCK_FLAGS := 0x100000
## How the race ended, read by the code that runs it: 0 when the car made
## it, $FFFF when the time ran out.
const RACE_LOST := 0x101208
const CARS_TOUCHING := 0x1014F8
## What the rest of the game reads about the car: position (or $8000,
## $8000 high in the air), speed, direction of travel, speed smoothed
## (16.16), position on screen, zoom and height on screen.
const CAR_REPORT := 0x10165E
## 1 once the time has run out: the race then ends at the next gate.
const TIME_UP := 0x103332
## Which course is being driven.
const COURSE := 0x101202
## 1 while a recorded demonstration drives; where its next input byte is.
const DEMO_PLAYING := 0x1014FC
const DEMO_INPUT := 0x1014FE
## The joysticks as the BIOS reports them: up, down, left, right, A, B, C, D.
const PLAYER_1_INPUT := 0x10FD96
const PLAYER_2_INPUT := 0x10FD9C

## What the course is drawn from: the camera and zoom of the ground, the
## same for the things on the course (course_objects.gd), the car's position, and for $19F74 the
## checkpoints reached and the car's y.
const GROUND_CAMERA := 0x102534
const GROUND_ZOOM := 0x102538
const OBJECTS_CAMERA := 0x103220
const OBJECTS_ZOOM := 0x103224
const DRAWN_CAR_POSITION := 0x103294
const DRAWN_PROGRESS := 0x10346A
## The course's ground: its map and its tiles, for redrawing all of it.
const GROUND_MAP := 0x101672
const GROUND_TILES := 0x101676
const REDRAW_GROUND := 0x1348E

## The race's clock (race_clock.gd).
const COUNT_DOWN_CLOCK := 0x16A44
const GAIN_TIME := 0x16AA8
const SHOW_CHECKPOINT_SIGN := 0x149BA
const ENGINE_SOUND := 0xFA18
const SLOW_GROUND_SOUND := 0xFC9E
## Puts an effect on the course: x in D0, y in D2, $80 in D1, kind in D3.
const ADD_EFFECT := 0x1458C
const EFFECT_SPARKS := 6
const EFFECT_BACKFIRE := 0xC

# --- tables in the program ROM -----------------------------------------------

## Steering for each joystick direction (low four bits of the input).
const STEER_BY_STICK := 0xE622
## Upward speed off a ramp, by speed.
const TAKE_OFF_CLIMB := 0xE378
const SHAKE_BY_KIND := 0xF2C6
## How much speed a bounce off a wall leaves, by speed: on the ground and in the air.
const BOUNCE_SPEED := 0x22462
const BOUNCE_SPEED_AIRBORNE := 0x224A2
## The direction each kind of edge runs in.
const EDGE_ANGLES := 0xE15E
## Extra turn rate, by speed.
const TURN_BOOST := 0xE7B0
const GRIP_BY_FIELD_24 := 0xE9C2
## Speed kept when sliding, by slide angle.
## Direction after hitting a wall, by wall angle and direction of travel (32 x 32).
const BOUNCE := 0x224E2
const SLIDE_SPEED := 0x228E2
const ZOOM_BY_SPEED := 0x22BE2
## How far ahead of the car the camera looks, by speed.
const LOOK_AHEAD := 0x22CE2
## Screen direction (y, x) for each facing, 256 to a turn.
const LOOK_DIRECTION := 0x22DE2
const TURN_SCALE_OPEN := 0x231E2
const TURN_SCALE_ACROSS_EDGE := 0x23262
## Per course, four bytes for each open ground code: surface, DUST_KIND, SHAKE_KIND, rough.
const OPEN_GROUND := 0x232E2
# Sounds, as asked of the routine at $15256.
const SOUND_BACKFIRE := 0xC0
const SOUND_SQUEAL := 0xD6
const SOUND_LANDING := 0xD7
const SOUND_DAMAGE := 0x185F
const SOUND_KNOCK := 0x1871
const SOUND_SCRAPE := 0xD1
const SOUND_CHECKPOINT := 0x185D
const SOUND_TAKE_OFF := 0x186F
const SOUND_WALL := 0x1870
const REQUEST_SOUND := 0x15256

## The routine for each driving state.
const STATES := 0xDA72
## Which way a spin goes, by direction of travel, and how far it goes and
## how fast, by speed.
const SPIN_SIDES := 0xDCC4
const SPIN_LENGTHS := 0xDCE4
const SPIN_RATES := 0xDD24
## Sound of sliding on each surface (negative for none).
const SLIDE_SOUNDS := 0xF984
## Points around the car, by direction (y, x: bytes).
const AROUND_CAR := 0x26C40
## How often the wheels raise dust, by speed: frames between, and the
## speed the effect plays at (two words each).
const DUST_BY_SPEED := 0x26BC0
## Frames between skid marks by speed, the kind of mark by direction of
## travel, and where the two rear wheels are by the direction of the
## picture (x, y, x, y: words).
const SKID_WAITS := 0x26C80
const SKID_KINDS := 0x26CA0
const REAR_WHEELS := 0x26CE0
## Where the exhaust is, by the direction of the picture (x, y: words).
const EXHAUST_PLACES := 0x26DE0
## Sixteen lists of waits between backfires, each ended by $FFFF.
const BACKFIRE_LISTS := 0x26E60
## Size of the shadow by height above the ground (8.8 fixed point).
const SHADOW_SIZE_BY_HEIGHT := 0xF02A

## Sine, 1024 steps to a turn, 8.8 fixed point.
const SINE := 0x27A3A


func routines() -> Dictionary:
	return {
		0xDAAC: drive,
		0xF3E2: note_speed_trend,
		0xF33A: count_start_frames,
		0xE4A6: zoom_for_speed,
		0xE4FC: zoom_to_normal,
		0xEDC6: scale_margins,
		0xF4DE: margin_at_zoom,
		0xE092: sense_ground,
		0xF360: note_slow_ground,
		0xE19E: ground_effect,
		0xE28C: no_effect,
		0xE326: no_effect,
		0xE292: cross_finish,
		0xE2B0: pass_gate_backwards,
		0xE2C4: pass_gate,
		0xE32C: take_off,
		0xF8E2: scrape_sound,
		0xE3B8: react,
		0xE432: react_keeping_state,
		0xF2FA: note_surface_change,
		0xF2A2: set_shake,
		0xE530: look_up_grip,
		0xE55E: look_up_ground,
		0xE57C: read_controls,
		0xE632: steer,
		0xE770: accelerate,
		0xE7F0: coast,
		0xE826: apply_acceleration,
		0xE830: follow_heading,
		0xE8BA: slide,
		0xEA12: lose_speed_sliding,
		0xEBD4: turn_picture,
		0xEA42: limit_speed,
		0xEAA8: move,
		0xEAE8: aim_camera,
		0xEB44: ease_camera,
		0xEB74: place_on_screen,
		0xEB9E: place_camera,
		0xF30A: speed_after_bounce,
		0xF460: bounce_direction,
		0xD956: update,
		0xDAA2: drive_again,
		0xDBF0: start_spin,
		0xDDA4: spin,
		0xDFC8: fly,
		0xF130: set_depth,
		0xF204: report,
		0xF264: knock,
		0xF326: let_go_of_controls,
		0xF354: start_again,
		0xF386: wear_down,
		0xF40A: note_pulling_away,
		0xF4B4: is_on_screen,
		0xF5C2: note_touched_down,
		0xF5CA: note_in_the_air,
		0xF5D2: dust_at_once,
		0xF5DA: raise_dust,
		0xF696: throw_sparks,
		0xF6EC: leave_skid_marks,
		0xF7D6: start_backfiring,
		0xF80C: backfire,
		0xF884: squeal_pulling_away,
		0xF8DA: count_frames_since_scrape,
		0xF908: squeal_braking,
		0xF94C: slide_sound,
		0xEDF4: show_course,
		0xEEA6: draw_on_ground,
		0xEEBC: draw_airborne,
		0xEEE2: draw_body,
		0xEF44: draw_shadow,
		0xEF9E: draw_shadow_airborne,
		0xF0AA: draw_wheels,
	}


func scratch() -> Dictionary:
	# $DAAC and the other callers pass nothing between these in registers.
	var free := ["d0", "d1", "d2", "d3", "d4", "d6", "d7", "a0", "a5", "ccr"]
	var all := {}
	for address: int in routines():
		all[address] = free
	# these return something in a register
	all[0xDAAC] = ["d0.high", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "a0", "a1", "a2", "a3", "a4", "a5", "ccr"]
	for address: int in [0xE19E, 0xE28C, 0xE326, 0xE292, 0xE2B0, 0xE2C4, 0xE32C]:
		all[address] = ["d0.high", "d1", "d2", "d3", "d7", "a0", "ccr"]
	for address: int in [0xD956, 0xDAA2, 0xDBF0, 0xDDA4]:
		all[address] = all[0xDAAC]
	all[0xF4B4] = ["ccr"]
	all[0xF4DE] = ["ccr"]
	all[0xF30A] = ["ccr"]
	all[0xF460] = ["a0", "ccr"]
	for address: int in [0xEEA6, 0xEEBC, 0xEEE2, 0xEF44, 0xEF9E, 0xF0AA]:
		all[address] = ["d1", "d6", "d7", "ccr"]
	return all


## $D956: one frame of the car. Returns 0 in D0 when the race is over.
func update() -> void:
	var car := m.a6
	set16(car + PULLING_AWAY_BEFORE, u16(car + PULLING_AWAY))
	set16(car + TOUCHED_WALL_BEFORE, u16(car + TOUCHED_WALL))
	set16(car + SCRAPED_WALL_BEFORE, u16(car + SCRAPED_WALL))
	set16(car + TOUCHED_WALL, 0)
	set16(car + SCRAPED_WALL, 0)
	set16(car + FRAMES_SINCE_BOUNCE, u16(car + FRAMES_SINCE_BOUNCE) + 1)
	note_speed_trend()
	set16(car + SPEED_BEFORE, u16(car + SPEED))
	set16(car + AIRBORNE_BEFORE, u16(car + AIRBORNE))
	if u16(car + AIRBORNE) == 1:
		fly()
	if u16(car + FINISHED) == 1:
		# drives on by itself for a while, or until it is out of sight
		var left := s16(car + FRAMES_AFTER_FINISH) - 1
		set16(car + FRAMES_AFTER_FINISH, left)
		if left >= 0:
			is_on_screen()
		if left < 0 or low16(m.d0) == 0:
			set16(RACE_LOST, 0 if u16(TIME_UP) == 0 else 0xFFFF)
			m.d0 = with_low16(m.d0, 0)
			return
	elif u8(CLOCK_FLAGS) & 1 == 0:
		m.call_routine(COUNT_DOWN_CLOCK)
		if m.d0 & 0xFFFF == 0xFFFF:
			set16(RACE_LOST, 0xFFFF)
			m.d0 = with_low16(m.d0, 0)
			return
	note_pulling_away()
	count_start_frames()
	knock()
	m.a0 = m.r32(STATES + wrap16(u16(car + STATE) * 4))
	m.call_routine(m.a0)
	set_depth()
	backfire()
	count_frames_since_scrape()
	squeal_braking()
	slide_sound()
	m.call_routine(ENGINE_SOUND)
	squeal_pulling_away()
	m.call_routine(SLOW_GROUND_SOUND)
	wear_down()
	report()
	m.d0 = with_low16(m.d0, 1)


## $DAA2
func drive_again() -> void:
	set16(m.a6 + STATE, STATE_DRIVING)
	drive()


## $DBF0: the car has faced away from where it travels for too long and
## spins. How far and how fast depends on its speed.
func start_spin() -> void:
	var car := m.a6
	let_go_of_controls()
	set32(car + SPIN_TURNED, 0)
	var travel := ((u16(car + TRAVEL) + 0x400) & 0xFFFF) >> 11
	set16(car + SPIN_SIDE, rom_s8(SPIN_SIDES + travel))
	var by_speed := (((_magnitude(s16(car + SPEED)) & 0xFFFF) >> 7) & 0x1F) * 2
	var facing := ((u16(car + FACING) + 0x400) & 0xFFFF) >> 11
	set16(car + SPIN_TURNED, facing)
	var length := m.r16(SPIN_LENGTHS + by_speed)
	if length != 0:
		start_again()
	set16(car + SPIN_END, facing + length)
	set32(car + SPIN_RATE, m.r32(SPIN_RATES + by_speed * 2))
	set16(car + STATE, STATE_SPINNING)
	spin()


## $DDA4: one frame of spinning.
func spin() -> void:
	var car := m.a6
	if u16(car + FINISHED) == 0:
		zoom_for_speed()
	else:
		zoom_to_normal()
	scale_margins()
	sense_ground()
	note_slow_ground()
	ground_effect()
	react_keeping_state()
	set32(car + SPIN_TURNED, u32(car + SPIN_TURNED) + u32(car + SPIN_RATE))
	if s16(car + SPIN_END) <= s16(car + SPIN_TURNED):
		set16(car + SPUN_FRAMES, 0)
		set16(car + STATE, 0)
		drive_again()
		return
	var direction := u16(car + SPIN_TURNED) & 0x1F
	if u16(car + SPIN_SIDE) == 0xFFFF:
		direction = (0x20 - direction) & 0x1F
	set16(car + PICTURE_DIRECTION, direction)
	if u16(car + FINISHED) == 0:
		if u16(car + AIRBORNE) == 0:
			coast()
			apply_acceleration()
		limit_speed()
	move()
	if u16(car + FINISHED) == 0:
		aim_camera()
		ease_camera()
		place_camera()
	else:
		place_on_screen()
	show_course()
	if u16(car + AIRBORNE) == 0:
		note_surface_change()
		draw_on_ground()
	else:
		draw_airborne()
	m.d0 = with_low16(m.d0, 1)


## $DFC8: one frame in the air. The car falls, and when it comes down hard
## it bounces: only then do the controls get a say, and a strong one.
func fly() -> void:
	var car := m.a6
	note_in_the_air()
	set16(car + STEER, 0)
	set16(car + STEER_BEFORE, 0)
	set16(car + TURN, 0)
	set16(car + CLIMB, u16(car + CLIMB) - 0x20)
	set16(car + HEIGHT, u16(car + HEIGHT) + u16(car + CLIMB))
	if s16(car + HEIGHT) > 0:
		return
	_request_sound(SOUND_LANDING)
	note_touched_down()
	set16(car + CLIMB, -s16(car + CLIMB))
	if s16(car + CLIMB) <= 0x80:
		set16(car + HEIGHT, 0)
		set16(car + HEIGHT_ON_SCREEN, 0)
		set16(car + AIRBORNE, 0)
		return
	dust_at_once()
	read_controls()
	steer()
	set16(car + TURN, u16(car + TURN) << 3)
	look_up_grip()
	look_up_ground()
	accelerate()
	set16(car + ACCELERATION, u16(car + ACCELERATION) << 4)
	apply_acceleration()
	limit_speed()
	var climb := s16(car + CLIMB) >> 1
	if u16(car + STATE) == STATE_SPINNING:
		climb >>= 1
	set16(car + HEIGHT, 0)
	set16(car + CLIMB, climb)


## $F130: how far down the screen the car is decides what is drawn over it.
func set_depth() -> void:
	var car := m.a6
	var depth := u16(car + SCREEN_Y) + u16(car + DEPTH)
	var height := u16(car + HEIGHT_ON_SCREEN)
	set16(u32(car + BODY_SPRITE) + Sprite.DEPTH, depth + u16(car + BODY_DEPTH) + height)
	set16(u32(car + WHEELS_SPRITE) + Sprite.DEPTH, depth + u16(car + WHEELS_DEPTH) + height)
	set16(u32(car + SHADOW_SPRITE) + Sprite.DEPTH, depth + u16(car + SHADOW_DEPTH))


## $F204: leaves what the rest of the game wants to know about the car.
func report() -> void:
	var car := m.a6
	if s16(car + HEIGHT) > 0x1400:
		set16(CAR_REPORT, 0x8000)
		set16(CAR_REPORT + 2, 0x8000)
	else:
		set16(CAR_REPORT, u16(car + X))
		set16(CAR_REPORT + 2, u16(car + Y))
	set16(CAR_REPORT + 4, u16(car + SPEED))
	set16(CAR_REPORT + 6, u16(car + TRAVEL))
	set16(CAR_REPORT + 0xC, u16(car + SCREEN_X))
	set16(CAR_REPORT + 0xE, u16(car + SCREEN_Y))
	set16(CAR_REPORT + 0x10, u16(car + ZOOM))
	set16(CAR_REPORT + 0x12, u16(car + HEIGHT_ON_SCREEN))
	var smoothed := s32(CAR_REPORT + 8)
	set32(CAR_REPORT + 8, smoothed + (wrap32((s16(car + SPEED) << 16) - smoothed) >> 4))


## $F264: another car knocking into this one takes a quarter of its speed.
func knock() -> void:
	var car := m.a6
	set16(car + FRAMES_SINCE_KNOCK, u16(car + FRAMES_SINCE_KNOCK) + 1)
	if u16(car + FRAMES_SINCE_KNOCK) >= 0xA and u16(CARS_TOUCHING) != 0:
		_request_sound(SOUND_KNOCK)
		scrape_sound()
		set16(car + FRAMES_SINCE_KNOCK, 0)
		set16(car + SPEED, ((s16(car + SPEED) * 0xC0) & 0xFFFFFFFF) >> 8)


## $F326
func let_go_of_controls() -> void:
	var car := m.a6
	set16(car + STEER, 0)
	set16(car + ACCELERATOR, 0)
	set16(car + BRAKE, 0)


## $F354
func start_again() -> void:
	var car := m.a6
	set16(car + START_FRAMES, 0)
	set16(car + STARTING, 1)


## $F386: every so many frames of scraping along a wall damage the car,
## which lowers its top speed. After the fourth time it takes no more.
func wear_down() -> void:
	var car := m.a6
	if u16(car + SCRAPED_WALL_BEFORE) == 1 or u16(car + SCRAPED_WALL) != 1:
		return
	set16(car + SCRAPES_LEFT, u16(car + SCRAPES_LEFT) - 1)
	if s16(car + SCRAPES_LEFT) > 0:
		return
	set16(car + DAMAGE, u16(car + DAMAGE) + 1)
	if s16(car + DAMAGE) >= 4:
		set16(car + SCRAPES_LEFT, 0x7FFF)
		return
	var stage := car + DAMAGE_STAGES + wrap16(u16(car + DAMAGE) << 3)
	set16(car + SCRAPES_LEFT, u16(stage))
	set16(car + TOP_SPEED, u16(stage + 2))
	set16(car + ROUGH_SPEED, u16(stage + 4))
	_request_sound(SOUND_DAMAGE)


## $F40A: gaining speed from below $400 is pulling away, with squealing
## tyres; after a second and a half of it the exhaust backfires.
func note_pulling_away() -> void:
	var car := m.a6
	if u16(car + SPEED_TREND) != 1:
		set16(car + FRAMES_GAINING, 0)
		set16(car + PULLING_AWAY, 0)
		return
	var speed := s16(car + SPEED)
	if speed <= 0:
		return
	set16(car + FRAMES_GAINING, u16(car + FRAMES_GAINING) + 1)
	if u16(car + PULLING_AWAY) == 1:
		if s16(car + FRAMES_GAINING) > 0x5A:
			start_backfiring()
			set16(car + PULLING_AWAY, 0)
	elif speed < 0x400:
		set16(car + PULLING_AWAY, 1)


## $F4B4: D0 is 1 while the car is in sight.
func is_on_screen() -> void:
	var car := m.a6
	var x := s16(car + SCREEN_X)
	var y := s16(car + SCREEN_Y)
	var seen := x >= -0x40 and x <= 0x17F and y >= -0x40 and y <= 0x140
	m.d0 = with_low16(m.d0, 1 if seen else 0)


## $F5C2
func note_touched_down() -> void:
	set16(m.a6 + TOUCHED_DOWN, 1)


## $F5CA
func note_in_the_air() -> void:
	set16(m.a6 + TOUCHED_DOWN, 0)


## $F5D2
func dust_at_once() -> void:
	set16(m.a6 + DUST_FRAMES, 0x7FF0)


## $F5DA: dust, spray or whatever the ground gives, from behind the rear
## wheels: on anything but tarmac, and on tarmac when pulling away or sliding.
func raise_dust() -> void:
	var car := m.a6
	if u16(car + TOUCHED_DOWN) == 0:
		return
	if u16(car + SURFACE) == 0 and u16(car + PULLING_AWAY) == 0 and u16(car + SLIDING) != 1:
		return
	set16(car + DUST_FRAMES, u16(car + DUST_FRAMES) + 1)
	var by_speed := DUST_BY_SPEED + ((u16(car + SPEED) >> 5) & 0x7C)
	m.a0 = DUST_BY_SPEED
	m.d0 = with_low16(m.d0, (u16(car + SPEED) >> 5) & 0x7C)
	m.d1 = with_low16(m.d1, m.r16(by_speed))
	if m.r16(by_speed) > u16(car + DUST_FRAMES):
		return
	set16(car + DUST_FRAMES, 0)
	m.d1 = with_low16(m.d1, m.r16(by_speed + 2))
	m.d3 = with_low16(m.d3, u16(car + DUST_KIND) & 0xFF)
	if u16(car + DUST_KIND) & 0xFF == 0xFF:
		return
	var direction := (((u16(car + TRAVEL) + 0x400) & 0xFFFF) >> 11) + 0x11
	set16(car + DUST_SIDE, ~u16(car + DUST_SIDE))
	if u16(car + DUST_SIDE) != 0:
		direction -= 3
	var place := AROUND_CAR + (direction & 0x1F) * 2
	var x := rom_s8(place + 1)
	var y := rom_s8(place)
	if u16(car + SLIDING) == 1:
		x >>= 1
		y >>= 1
	var zoom := s16(car + ZOOM)
	x = wrap32(x * zoom) >> 8
	y = wrap32(y * zoom) >> 8
	m.a0 = AROUND_CAR
	m.d0 = (x & 0xFFFF0000) | ((x + u16(car + X)) & 0xFFFF)
	m.d2 = (y & 0xFFFF0000) | ((y + u16(car + Y)) & 0xFFFF)
	m.call_routine(ADD_EFFECT)


## $F6EC: skid marks under both rear wheels while sliding or pulling away
## fast, on tarmac and on the surface numbered 2.
func leave_skid_marks() -> void:
	var car := m.a6
	set16(car + SKID_COUNTDOWN, u16(car + SKID_COUNTDOWN) - 1)
	if s16(car + SKID_COUNTDOWN) > 0:
		return
	set16(car + SKID_COUNTDOWN, u16(car + SKID_COUNTDOWN) + 1)
	# The original leaves the answer to whatever register D7 holds when the
	# car is pulling away at less than $200.
	var marks := low16(m.d7) == 1
	if u16(car + SLIDING) == 1:
		marks = true
	elif u16(car + PULLING_AWAY) == 1:
		if s16(car + SPEED) >= 0x200:
			marks = true
	else:
		marks = false
	var surface := u16(car + SURFACE)
	if surface != 0 and surface != 2:
		marks = false
	if not marks:
		return
	var wait := m.r8(SKID_WAITS + (((_magnitude(s16(car + SPEED)) & 0xFFFF) >> 7) & 0x1F))
	set16(car + SKID_COUNTDOWN, wait)
	var kind := m.r16(SKID_KINDS + ((u16(car + TRAVEL) >> 11) & 0x1F) * 2)
	if surface == 2:
		kind += 0x20
	var wheels := REAR_WHEELS + wrap16(u16(car + PICTURE_DIRECTION) << 3)
	m.a0 = REAR_WHEELS
	m.d1 = 0
	m.d3 = with_low16(m.d3, kind)
	m.d7 = with_low16(m.d7, u16(car + PICTURE_DIRECTION) << 3)
	m.d0 = with_low16(m.d0, u16(car + X) + m.r16(wheels))
	m.d2 = with_low16(m.d2, u16(car + Y) + m.r16(wheels + 2))
	m.call_routine(ADD_EFFECT)
	m.d0 = with_low16(m.d0, u16(car + X) + m.r16(wheels + 4))
	m.d2 = with_low16(m.d2, u16(car + Y) + m.r16(wheels + 6))
	m.call_routine(ADD_EFFECT)


## $F696: sparks where the car touches a wall.
func throw_sparks() -> void:
	var car := m.a6
	if u16(car + TOUCHED_DOWN) == 0:
		return
	var place := AROUND_CAR + (((u16(car + TRAVEL) + 0x400) & 0xFFFF) >> 11) * 2
	var zoom := s16(car + ZOOM)
	var x := wrap32(rom_s8(place + 1) * zoom) >> 8
	var y := wrap32(rom_s8(place) * zoom) >> 8
	m.a0 = AROUND_CAR
	m.d0 = (x & 0xFFFF0000) | ((x + u16(car + X)) & 0xFFFF)
	m.d2 = (y & 0xFFFF0000) | ((y + u16(car + Y)) & 0xFFFF)
	m.d1 = with_low16(m.d1, 0x80)
	m.d3 = with_low16(m.d3, EFFECT_SPARKS)
	m.call_routine(ADD_EFFECT)


## $F7D6: picks one of sixteen rhythms of backfiring.
func start_backfiring() -> void:
	var car := m.a6
	if u16(car + BACKFIRING) == 1:
		return
	set16(car + BACKFIRING, 1)
	var pick := Random.advance(m) & 0xF
	m.a0 = BACKFIRE_LISTS
	m.d0 = with_low16(m.d0, pick * 4)
	set32(car + BACKFIRE_WAITS, m.r32(BACKFIRE_LISTS + pick * 4))
	set16(car + BACKFIRE_COUNTDOWN, 0)


## $F80C: the next bang when it is due, with a flame at the exhaust.
func backfire() -> void:
	var car := m.a6
	if u16(car + BACKFIRING) != 1:
		return
	set16(car + BACKFIRE_COUNTDOWN, u16(car + BACKFIRE_COUNTDOWN) - 1)
	if s16(car + BACKFIRE_COUNTDOWN) > 0:
		return
	var waits := u32(car + BACKFIRE_WAITS)
	if m.r16(waits) == 0xFFFF:
		set16(car + BACKFIRING, 0)
		return
	set16(car + BACKFIRE_COUNTDOWN, m.r16(waits))
	set32(car + BACKFIRE_WAITS, waits + 2)
	_request_sound(SOUND_BACKFIRE)
	var place := EXHAUST_PLACES + wrap16(u16(car + PICTURE_DIRECTION) * 4)
	var up := u16(car + HEIGHT) >> 8
	m.a0 = EXHAUST_PLACES
	m.d0 = with_low16(m.d0, m.r16(place) + u16(car + X))
	m.d1 = with_low16(m.d1, 0x80)
	m.d2 = with_low16(m.d2, m.r16(place + 2) + u16(car + Y) - up)
	m.d3 = with_low16(m.d3, EFFECT_BACKFIRE)
	m.d7 = with_low16(m.d7, up)
	m.call_routine(ADD_EFFECT)


## $F884
func squeal_pulling_away() -> void:
	set16(FRAMES_SINCE_SQUEAL, u16(FRAMES_SINCE_SQUEAL) + 1)
	if u16(m.a6 + PULLING_AWAY) == 1 and u16(FRAMES_SINCE_SQUEAL) > 5:
		set16(FRAMES_SINCE_SQUEAL, 0)
		_request_sound(SOUND_SQUEAL)


## $F8DA
func count_frames_since_scrape() -> void:
	set16(FRAMES_SINCE_SCRAPE_SOUND, u16(FRAMES_SINCE_SCRAPE_SOUND) + 1)


## $F908: braking hard without sliding squeals too.
func squeal_braking() -> void:
	var car := m.a6
	set16(FRAMES_SINCE_BRAKE_SOUND, u16(FRAMES_SINCE_BRAKE_SOUND) + 1)
	if (u16(car + BRAKE) == 1 and u16(car + SLIDING) != 1 and s16(car + SPEED) >= 0x400
			and u16(FRAMES_SINCE_BRAKE_SOUND) > 5):
		set16(FRAMES_SINCE_BRAKE_SOUND, 0)
		_request_sound(SOUND_SQUEAL)


## $F94C: sliding sounds different on each surface.
func slide_sound() -> void:
	var car := m.a6
	set16(FRAMES_SINCE_SLIDE_SOUND, u16(FRAMES_SINCE_SLIDE_SOUND) + 1)
	if u16(car + SLIDING) == 1 and u16(FRAMES_SINCE_SLIDE_SOUND) > 5:
		set16(FRAMES_SINCE_SLIDE_SOUND, 0)
		var sound := rom_s16(SLIDE_SOUNDS + wrap16(u16(car + SURFACE) * 2))
		if sound >= 0:
			_request_sound(sound)


## $DAAC: one frame of the normal driving state. Returns 1 in D0.
func drive() -> void:
	var car := m.a6
	if u16(car + SPUN) == 1:
		set16(car + SPUN_FRAMES, u16(car + SPUN_FRAMES) + 1)
		if s16(car + SPUN_FRAMES) >= 0xE:
			set16(car + STATE, STATE_SPUN)
	else:
		set16(car + SPUN_FRAMES, 0)
	if u16(car + FINISHED) == 0:
		zoom_for_speed()
	else:
		zoom_to_normal()
	scale_margins()
	sense_ground()
	note_slow_ground()
	ground_effect()
	react()
	if u16(car + AIRBORNE) == 0:
		look_up_grip()
		look_up_ground()
	if u16(car + FINISHED) == 0 and u16(car + AIRBORNE) == 0:
		read_controls()
		steer()
	if u16(car + AIRBORNE) == 0:
		accelerate()
	if u16(car + FINISHED) == 0:
		if (u16(car + ACCELERATOR) | u16(car + BRAKE)) == 0 and u16(car + AIRBORNE) == 0:
			coast()
		if u16(car + AIRBORNE) == 0:
			apply_acceleration()
	if u16(car + AIRBORNE) == 0:
		follow_heading()
	slide()
	if u16(car + AIRBORNE) == 0:
		lose_speed_sliding()
	turn_picture()
	limit_speed()
	move()
	if u16(car + FINISHED) == 0:
		aim_camera()
		ease_camera()
		place_camera()
	else:
		place_on_screen()
	show_course()
	if u16(car + AIRBORNE) == 0:
		note_surface_change()
		draw_on_ground()
	else:
		draw_airborne()
	m.d0 = with_low16(m.d0, 1)


## $F3E2
func note_speed_trend() -> void:
	var car := m.a6
	var speed := s16(car + SPEED)
	var before := s16(car + SPEED_BEFORE)
	set16(car + SPEED_TREND, 2 if speed < before else (1 if speed > before else 0))


## $F33A
func count_start_frames() -> void:
	var car := m.a6
	var frames := u16(car + START_FRAMES) + 1
	set16(car + START_FRAMES, frames)
	set16(car + STARTING, 1 if (frames & 0xFFFF) <= 0x14 else 0)


## $E4A6: the faster the car goes, the further out the view zooms.
func zoom_for_speed() -> void:
	var car := m.a6
	var spare := wrap16(s16(car + TOP_SPEED) - _magnitude(s16(car + SPEED)))
	var step := (maxi(spare, 0) >> 4) & 0xFF
	_zoom_towards(car, rom_u8(ZOOM_BY_SPEED + step) + 1)


## $E4FC
func zoom_to_normal() -> void:
	_zoom_towards(m.a6, 0x100)


## Moves the zoom an eighth of the way to `target`, and at least one step.
func _zoom_towards(car: int, target: int) -> void:
	set16(car + ZOOM_TARGET, target)
	var before := s16(car + ZOOM_BEFORE)
	var zoom := wrap16((wrap16(target - before) >> 3) + before)
	if zoom == before and zoom != target:
		zoom = wrap16(before + (1 if wrap16(zoom - target) < 0 else -1))
	set16(car + ZOOM, zoom)


## $EDC6
func scale_margins() -> void:
	var car := m.a6
	var zoom := u16(car + ZOOM)
	if zoom == u16(car + ZOOM_BEFORE):
		return
	set16(car + ZOOM_BEFORE, zoom)
	set16(car + MARGIN_X, _margin_at_zoom(zoom, s16(car + SIZE_X)))
	set16(car + MARGIN_Y, _margin_at_zoom(zoom, s16(car + SIZE_Y)))


## $F4DE: zoom in D0 and size in D2 give a margin in D1.
func margin_at_zoom() -> void:
	var product := (wrap16(0x100 - m.d0) * low16(m.d2)) & 0xFFFFFFFF
	m.d1 = (product & 0xFFFF0000) | ((product & 0xFFFF) >> 8)


## The part of `size` that zooming out to `zoom` takes away.
static func _margin_at_zoom(zoom: int, size: int) -> int:
	return ((wrap16(0x100 - zoom) * size) & 0xFFFF) >> 8


## $E092: looks up what the course has where the car is.
func sense_ground() -> void:
	var car := m.a6
	set16(car + GROUND_CODE_BEFORE, u16(car + GROUND_CODE))
	set16(car + SURFACE_BEFORE, u16(car + SURFACE))
	m.d0 = with_low16(m.d0, u16(car + X))
	m.d2 = with_low16(m.d2, u16(car + Y))
	m.call_routine(0x13E74)
	var code := m.d0 & 0x7F
	set16(car + GROUND_CODE, code)
	if code < 0x20:
		# a wall, at one of 32 angles
		set16(car + GROUND_KIND_BEFORE, u16(car + GROUND_KIND))
		set16(car + GROUND_ANGLE, code << 11)
		set16(car + GROUND_KIND, WALL)
		set16(car + SURFACE, u16(car + OWN_SURFACE))
		set16(car + TOUCHED_WALL, 1)
	elif code < 0x40:
		set16(car + GROUND_ANGLE, rom_u16(EDGE_ANGLES + (code - 0x20) * 2))
		set16(car + GROUND_KIND, EDGE)
		set16(car + SURFACE, u16(car + OWN_SURFACE))
		set16(car + DUST_KIND, u16(car + OWN_DUST_KIND))
		set16(car + SHAKE_KIND, u16(car + OWN_SHAKE_KIND))
		set16(car + ROUGH, 0)
	else:
		var entry := rom_u32(OPEN_GROUND + wrap16(u16(COURSE) * 4)) + (code - 0x40) * 4
		set16(car + SURFACE, rom_s8(entry))
		set16(car + GROUND_ANGLE, 0)
		set16(car + GROUND_KIND, OPEN)
		set16(car + DUST_KIND, rom_s8(entry + 1))
		set16(car + SHAKE_KIND, rom_s8(entry + 2))
		set16(car + ROUGH, rom_s8(entry + 3))


## $F360
func note_slow_ground() -> void:
	var car := m.a6
	var surface := s16(car + SURFACE)
	set16(car + SLOW_GROUND, 1 if u16(car + AIRBORNE) != 1 and surface >= 8 and surface <= 13 else 0)


## $E19E: what the ground under the car does to it. Returns in D0 what
## `react` is to do about it.
func ground_effect() -> void:
	var car := m.a6
	if u16(car + GROUND_KIND) != WALL:
		match s16(car + SURFACE):
			SURFACE_TAKE_OFF:
				take_off()
			SURFACE_FINISH:
				cross_finish()
			SURFACE_GATE_FIRST:
				pass_gate_backwards()
			SURFACE_GATE_SECOND:
				pass_gate()
			_:
				no_effect()
		return
	scrape_sound()
	if s16(car + SPEED) > 0x8FF \
			and _angle_between(s16(car + GROUND_ANGLE), s16(car + TRAVEL)).x <= 0x6660:
		set16(car + SCRAPED_WALL, 1)
		_request_sound(SOUND_WALL)
		throw_sparks()
	m.d0 = with_low16(m.d0, REACT_BOUNCE)


## $E28C, $E326
func no_effect() -> void:
	m.d0 = with_low16(m.d0, REACT_NOT)


## $E292
func cross_finish() -> void:
	_finish(m.a6)
	m.d0 = with_low16(m.d0, REACT_NOT)


func _finish(car: int) -> void:
	if u16(car + FINISH_CROSSINGS) == 0:
		set16(car + FRAMES_AFTER_FINISH, 0xB4)
	set16(car + FINISH_CROSSINGS, u16(car + FINISH_CROSSINGS) + 1)
	set16(car + FINISHED, 1)


## $E2B0: a gate is two strips of ground. Reaching the first from the second
## is driving the wrong way through it.
func pass_gate_backwards() -> void:
	if u16(m.a6 + SURFACE_BEFORE) == SURFACE_GATE_SECOND:
		set16(GATES_PASSED, u16(GATES_PASSED) - 1)
	m.d0 = with_low16(m.d0, REACT_NOT)


## $E2C4: through a gate the right way. A gate not passed before is a
## checkpoint reached.
func pass_gate() -> void:
	var car := m.a6
	if u16(car + SURFACE_BEFORE) == SURFACE_GATE_FIRST:
		if u16(TIME_UP) == 1:
			_finish(car)
		else:
			if u16(GATES_PASSED) == u16(CHECKPOINTS):
				_request_sound(SOUND_CHECKPOINT)
				m.call_routine(SHOW_CHECKPOINT_SIGN)
				set16(CHECKPOINTS, u16(CHECKPOINTS) + 1)
				m.call_routine(GAIN_TIME)
			set16(GATES_PASSED, u16(GATES_PASSED) + 1)
	m.d0 = with_low16(m.d0, REACT_NOT)


## $E32C: off the end of a ramp, into the air.
func take_off() -> void:
	var car := m.a6
	if u16(car + SURFACE_BEFORE) == SURFACE_RAMP:
		_request_sound(SOUND_TAKE_OFF)
		var by_speed := ((_magnitude(s16(car + SPEED)) & 0xFFFF) >> 7) & 0x7F
		set16(car + CLIMB, rom_u16(TAKE_OFF_CLIMB + by_speed * 2))
		set16(car + HEIGHT, 0)
		set16(car + AIRBORNE, 1)
		set16(car + STEER, 0)
		set16(car + STEER_BEFORE, 0)
	m.d0 = with_low16(m.d0, REACT_NOT)


## $F8E2: the sound of scraping along a wall, at most every eleventh frame.
func scrape_sound() -> void:
	if u16(FRAMES_SINCE_SCRAPE_SOUND) > 0xA:
		set16(FRAMES_SINCE_SCRAPE_SOUND, 0)
		_request_sound(SOUND_SCRAPE)


func _request_sound(sound: int) -> void:
	m.d0 = with_low16(m.d0, sound)
	m.call_routine(REQUEST_SOUND)


## $E3B8: does what `ground_effect` asked for in D0.
func react() -> void:
	var car := m.a6
	match m.d0 & 0xFFFF:
		REACT_SLOW:
			set16(car + SPEED, (0x66 * s16(car + SPEED)) >> 8)
		REACT_BOUNCE:
			_bounce(car)
			set16(car + STATE, STATE_04)


## $E432: the same for the driving state at $DDA4, which stays in its state.
func react_keeping_state() -> void:
	if (m.d0 & 0xFFFF) == REACT_BOUNCE:
		_bounce(m.a6)


## Turns the car away from the wall it touches; the first bounce in a while
## also costs speed.
func _bounce(car: int) -> void:
	m.d0 = with_low16(m.d0, u16(car + GROUND_ANGLE))
	m.d1 = with_low16(m.d1, u16(car + TRAVEL))
	bounce_direction()
	set16(car + TRAVEL, m.d0)
	set16(car + FACING, m.d0)
	if (m.d1 & 0xFFFF) == 0:
		m.a0 = BOUNCE_SPEED_AIRBORNE if u16(car + AIRBORNE) == 1 else BOUNCE_SPEED
		speed_after_bounce()
		set16(car + SPEED_BEFORE_BOUNCE, u16(car + SPEED))
		set16(car + SPEED, m.d0)


## $F2FA
func note_surface_change() -> void:
	var car := m.a6
	if u16(car + SURFACE) != u16(car + SURFACE_BEFORE):
		set_shake()


## $F2A2
func set_shake() -> void:
	var car := m.a6
	var index := s16(car + SHAKE_KIND)
	if index == 0xD:
		index = s16(car + OWN_SHAKE_KIND)
	set16(car + SHAKE_PERIOD, rom_u16(SHAKE_BY_KIND + wrap16(index * 4)))
	set16(car + SHAKE_HEIGHT, rom_u16(SHAKE_BY_KIND + 2 + wrap16(index * 4)))
	set16(car + SHAKE_COUNTDOWN, 0)


## $E530
func look_up_grip() -> void:
	var car := m.a6
	var table := m.r32(u32(car + GRIP_TABLES) + wrap16(u16(car + SURFACE) * 4))
	var entry := table + wrap16((_magnitude(s16(car + SPEED)) & 0xFFFF) >> 5 & 0xFFF8)
	set32(car + GRIP, m.r32(entry))
	set32(car + GRIP + 4, m.r32(entry + 4))


## $E55E
func look_up_ground() -> void:
	var car := m.a6
	var surface := u16(car + SURFACE)
	if surface == u16(car + SURFACE_BEFORE):
		return
	var entry := u32(car + GROUND_TABLE) + wrap16(surface << 3)
	set32(car + GROUND_ACCELERATION, m.r32(entry))
	set16(car + GROUND_DRAG, m.r16(entry + 4))


## $E57C: this frame's steering and pedals, from the joystick or from a
## recorded demonstration.
func read_controls() -> void:
	var car := m.a6
	if u16(car + STARTING) == 1:
		return
	if u16(DEMO_PLAYING) == 1:
		var next := u32(DEMO_INPUT)
		var recorded := m.r8(next)
		if recorded & 0x80:
			# the recording has ended
			recorded = 0
		else:
			next += 1
		set32(DEMO_INPUT, next)
		set16(car + ACCELERATOR, (recorded >> 5) & 1)
		set16(car + BRAKE, (recorded >> 4) & 1)
		set16(car + STEER, recorded & 0xF)
		return
	var stick := u8(PLAYER_1_INPUT if u16(car + SECOND_PLAYER) == 0 else PLAYER_2_INPUT)
	set16(car + ACCELERATOR, (stick >> 4) & 1)
	set16(car + BRAKE, (stick >> 5) & 1)
	set16(car + STEER, rom_u8(STEER_BY_STICK + (stick & 0xF)))


## $E632: how far the steering turns the car this frame.
func steer() -> void:
	var car := m.a6
	var steering := u16(car + STEER)
	if steering == u16(car + STEER_BEFORE):
		set16(car + STEER_HELD, u16(car + STEER_HELD) + 1)
	else:
		set16(car + STEER_EARLIEST, u16(car + STEER_EARLIER))
		set16(car + STEER_EARLIER, u16(car + STEER_BEFORE))
		set16(car + STEER_HELD_EARLIEST, u16(car + STEER_HELD_EARLIER))
		set16(car + STEER_HELD_EARLIER, u16(car + STEER_HELD))
		set16(car + STEER_HELD, 0)
	set16(car + STEER_BEFORE, steering)
	var speed := s16(car + SPEED)
	var ground := u16(car + GROUND_KIND)
	var turn := 0
	if steering != 0:
		var by_speed := ((_magnitude(speed) & 0xFFFF) >> 3) & 0xFFFE
		turn = m.r16(u32(car + TURN_TABLE) + wrap16(by_speed))
		var scale := -1
		if ground == OPEN:
			scale = rom_u16(TURN_SCALE_OPEN + ((by_speed >> 2) & 0xFFFE))
		elif ground == EDGE:
			var off := _angle_between(s16(car + GROUND_ANGLE), s16(car + TRAVEL))
			if (off.x & 0xFFFF) >= 0x1000:
				scale = rom_u16(TURN_SCALE_ACROSS_EDGE + ((by_speed >> 2) & 0xFFFE))
		if scale >= 0:
			turn = (turn * scale + 0x80) >> 8
		if steering != STEER_RIGHT:
			turn = -turn
	# Flicking the stick to the other side and back turns twice as fast.
	if ground != EDGE and u16(car + STEER_HELD_EARLIEST) > 0x14 and u16(car + STEER_EARLIER) == 0 \
			and u16(car + STEER_HELD_EARLIER) <= 0x10 and s16(car + STEER_HELD) >= 9:
		if wrap16(steering + u16(car + STEER_EARLIEST)) == 3 and s16(car + STEER_HELD) < 0xF:
			turn *= 2
	if speed < 0:
		turn = -turn
	set16(car + TURN, turn)


## $E770: the pedals' effect on speed.
func accelerate() -> void:
	var car := m.a6
	var change := 0
	if u16(car + ACCELERATOR) == 1:
		var power := u16(car + GROUND_ACCELERATION)
		var by_speed := ((_magnitude(s16(car + SPEED)) & 0xFFFF) >> 7) & 0x7F
		change = ((power * rom_u16(TURN_BOOST + by_speed * 2)) >> 16) + power
	if u16(car + BRAKE) == 1:
		change -= u16(car + GROUND_BRAKING)
	set16(car + ACCELERATION, change)


## $E7F0: with no pedal pressed the car rolls to a stop.
func coast() -> void:
	var car := m.a6
	var speed := s16(car + SPEED)
	var drag := s16(car + GROUND_DRAG)
	var reach := drag >> 1 if u16(car + STATE) == STATE_SPINNING else drag
	if ((speed + reach) & 0xFFFF) <= ((reach * 2) & 0xFFFF):
		set16(car + ACCELERATION, -speed)
	else:
		set16(car + ACCELERATION, -drag if speed >= 0 else drag)


## $E826
func apply_acceleration() -> void:
	var car := m.a6
	set16(car + SPEED, s16(car + SPEED) + s16(car + ACCELERATION))


## $E830: without steering input, a car on an edge turns to face the way
## the edge runs, an eighth of the difference a frame.
func follow_heading() -> void:
	var car := m.a6
	if u16(car + STEER) != 0 or u16(car + GROUND_KIND) != EDGE or u16(car + SPEED) == 0:
		return
	var off := _angle_between(s16(car + GROUND_ANGLE), s16(car + FACING))
	var angle := off.x & 0xFFFF
	if angle < 0x40:
		set16(car + FACING, u16(car + GROUND_ANGLE))
		return
	var step := 8 if angle <= 8 else angle >> 3
	set16(car + FACING, u16(car + FACING) + off.y * step)


## $E8BA: turns the car, then pulls its direction of travel towards the way
## it faces as far as the grip allows. What is left between the two is the slide.
func slide() -> void:
	var car := m.a6
	set16(car + SPUN, 0)
	var facing := wrap16(s16(car + FACING) + s16(car + TURN))
	set16(car + FACING, facing)
	var apart := _angle_between(facing, s16(car + TRAVEL))
	var angle := apart.x & 0xFFFF
	var side := apart.y
	set16(car + SLIDING, 1 if angle > 0x2000 else 0)
	if angle > 0x2AAA:
		set16(car + FIELD_114, 1)
	if angle > 0x4000:
		# never more than a quarter turn sideways
		set16(car + SPUN, 1)
		angle = 0x4000
		set16(car + TRAVEL, facing - 0x4000 + (0x8000 if side < 0 else 0))
	set16(car + SLIDE_SIDE, side)
	set16(car + SLIDE, angle)
	if angle < 0x40:
		set16(car + TRAVEL, facing)
		return
	var pedals := (u16(car + BRAKE) << 1) | u16(car + ACCELERATOR)
	var grip := u16(car + GRIP + wrap16(pedals * 2))
	if u16(car + GROUND_KIND) == EDGE:
		grip = (grip * 3) & 0xFFFF
	var step := mini(u16(car + FIELD_24) >> 6, 0x17)
	grip = ((grip * rom_u16(GRIP_BY_FIELD_24 + step * 2) + 0x8000) >> 16) & 0xFFFF
	var pull := wrap16((grip * angle + 0x8000) >> 16)
	set16(car + TRAVEL, s16(car + TRAVEL) + side * pull)


## $EA12: a car sliding at speed loses some of it.
func lose_speed_sliding() -> void:
	var car := m.a6
	var speed := s16(car + SPEED)
	if _magnitude(speed) > 0x800:
		var kept := rom_s16(SLIDE_SPEED + (u16(car + SLIDE) >> 6) * 2)
		set16(car + SPEED, (kept * speed) >> 8)


## $EBD4: the car's picture turns towards the way the car faces, a quarter
## of the difference a frame; in a wide slide it leans further into it.
func turn_picture() -> void:
	var car := m.a6
	var shown := s16(car + FACING)
	var angle := u16(car + SLIDE)
	if angle > 0x9C4:
		var lean := ((angle >> 1) + (angle >> 2)) & 0xFFFF
		shown = wrap16(shown + (lean if u16(car + SLIDE_SIDE) == 1 else -lean))
	var apart := _angle_between(shown, s16(car + PICTURE_ANGLE))
	var step := (apart.x & 0xFFFF) >> 2
	if step == 0:
		set16(car + PICTURE_ANGLE, shown)
	else:
		set16(car + PICTURE_ANGLE, s16(car + PICTURE_ANGLE) + apart.y * step)
	set16(car + PICTURE_DIRECTION, ((u16(car + PICTURE_ANGLE) + 0x400) & 0xFFFF) >> 11)


## $EA42: keeps the speed within what the car and the ground allow.
func limit_speed() -> void:
	var car := m.a6
	var speed := s16(car + SPEED)
	if u16(car + SLOW_GROUND) == 1:
		if speed > 0x6FF:
			if u16(car + ACCELERATOR) == 1:
				speed = wrap16(speed - u16(car + GROUND_BRAKING))
			speed = wrap16(speed - 0x12)
	elif u16(car + ROUGH) == 1:
		var allowed := s16(car + ROUGH_SPEED)
		if u16(car + AIRBORNE) != 1 and speed > allowed:
			speed = wrap16(speed - 0xD8)
			if speed <= allowed:
				speed = allowed
	elif speed > s16(car + TOP_SPEED):
		set16(car + SPEED, s16(car + TOP_SPEED))
		return
	set16(car + SPEED, maxi(speed, s16(car + LOWEST_SPEED)))


## $EAA8: moves the car along its direction of travel.
func move() -> void:
	var car := m.a6
	set32(car + X_BEFORE, u32(car + X))
	set32(car + Y_BEFORE, u32(car + Y))
	var angle := u16(car + TRAVEL) >> 6
	var speed := s16(car + SPEED)
	set32(car + X, u32(car + X) + rom_s16(SINE + ((angle + 0x100) & 0x3FF) * 2) * speed)
	set32(car + Y, u32(car + Y) + rom_s16(SINE + angle * 2) * speed)


## $EAE8: the car is drawn off centre so that more of the road ahead shows,
## the more the faster it goes.
func aim_camera() -> void:
	var car := m.a6
	var facing := u16(car + FACING)
	var speed := s16(car + SPEED)
	if speed < 0:
		speed = wrap16(-speed)
		facing = (facing + 0x8000) & 0xFFFF
	var reach := wrap16(rom_u8(LOOK_AHEAD + (((speed & 0xFFFF) >> 4) & 0xFF)) << 8)
	var direction := LOOK_DIRECTION + ((((facing >> 6) + 0x200) & 0x3FF) >> 2) * 4
	set32(car + SCREEN_X_WANTED, rom_s16(direction + 2) * reach + 0xA00000)
	set32(car + SCREEN_Y_WANTED, rom_s16(direction) * reach + 0x800000)


## $EB44: the car's place on screen moves a sixteenth of the way there a frame.
func ease_camera() -> void:
	var car := m.a6
	set32(car + SCREEN_X, u32(car + SCREEN_X) + (wrap32(s32(car + SCREEN_X_WANTED) - s32(car + SCREEN_X)) >> 4))
	set32(car + SCREEN_Y, u32(car + SCREEN_Y) + (wrap32(s32(car + SCREEN_Y_WANTED) - s32(car + SCREEN_Y)) >> 4))


## $EB74: a car the camera does not follow is drawn where the camera sees it.
func place_on_screen() -> void:
	var car := m.a6
	var zoom := s16(car + ZOOM)
	set16(car + SCREEN_X, (wrap16(u16(car + X) - u16(car + CAMERA_X)) * zoom) >> 8)
	set16(car + SCREEN_Y, (wrap16(u16(car + Y) - u16(car + CAMERA_Y)) * zoom) >> 8)


## $EB9E: puts the camera where the car appears at its place on screen.
func place_camera() -> void:
	var car := m.a6
	var zoom := s16(car + ZOOM)
	set16(car + CAMERA_X, u16(car + X) - divide16(s16(car + SCREEN_X) << 8, zoom))
	set16(car + CAMERA_Y, u16(car + Y) - divide16(s16(car + SCREEN_Y) << 8, zoom))


## $F30A: the speed left after hitting a wall, in D0. A0 is a table of how
## much is kept, by speed.
func speed_after_bounce() -> void:
	var car := m.a6
	var speed := s16(car + SPEED)
	var by_speed := ((_magnitude(speed) & 0xFFFF) >> 7) & 0x1F
	m.d0 = ((rom_s16(m.a0 + by_speed * 2) * speed) >> 8) & 0xFFFFFFFF


## $F460: a wall's angle in D0 and the direction of travel in D1 give the
## direction to bounce off in, in D0. D1 is 1 if the last bounce was less
## than 16 frames ago.
func bounce_direction() -> void:
	var car := m.a6
	var wall := ((m.d0 + 0x400) & 0xFFFF) >> 11
	var travel := ((m.d1 + 0x400) & 0xFFFF) >> 11
	if s16(car + SPEED) < 0:
		wall = (wall + 0x10) & 0x1F
	m.d0 = with_low16(m.d0, (rom_u8(BOUNCE + (wall << 5) + travel) & 0x1F) << 11)
	if u16(car + FRAMES_SINCE_BOUNCE) < 0x10:
		m.d1 = with_low16(m.d1, 1)
	else:
		set16(car + FRAMES_SINCE_BOUNCE, 0)
		m.d1 = with_low16(m.d1, 0)


## $EDF4: tells the course's drawing where the camera and the car are.
func show_course() -> void:
	var car := m.a6
	var camera_x := u16(car + CAMERA_X)
	var camera_y := u16(car + CAMERA_Y)
	var zoom := u16(car + ZOOM)
	set16(GROUND_ZOOM, zoom)
	set16(GROUND_ZOOM + 2, zoom)
	set16(OBJECTS_ZOOM, zoom)
	set16(OBJECTS_ZOOM + 2, zoom)
	if (_magnitude(wrap16(u16(car + CAMERA_X_DRAWN) - camera_x)) > 0x80
			or _magnitude(wrap16(u16(car + CAMERA_Y_DRAWN) - camera_y)) > 0x80):
		# The camera jumped: scrolling the ground there would not do.
		m.d0 = with_low16(m.d0, camera_x)
		m.d1 = with_low16(m.d1, camera_y)
		m.d2 = with_low16(m.d2, zoom)
		m.d3 = with_low16(m.d3, zoom)
		m.a4 = u32(GROUND_MAP)
		m.a5 = u32(GROUND_TILES)
		m.call_routine(REDRAW_GROUND)
	else:
		set16(GROUND_CAMERA, camera_x)
		set16(GROUND_CAMERA + 2, camera_y)
	set16(OBJECTS_CAMERA, camera_x)
	set16(OBJECTS_CAMERA + 2, camera_y)
	set16(DRAWN_CAR_POSITION, u16(car + X))
	set16(DRAWN_CAR_POSITION + 2, u16(car + Y))
	set16(DRAWN_PROGRESS, u16(CHECKPOINTS))
	set16(DRAWN_PROGRESS + 2, u16(car + Y))
	set16(car + CAMERA_X_DRAWN, camera_x)
	set16(car + CAMERA_Y_DRAWN, camera_y)


## $EEA6: draws the car on the ground.
func draw_on_ground() -> void:
	var car := m.a6
	if u16(car + DRAWN) != 1:
		return
	draw_body()
	draw_shadow()
	draw_wheels()


## $EEBC: draws the car in the air, its shadow under it.
func draw_airborne() -> void:
	var car := m.a6
	var height := (u16(car + ZOOM) * u16(car + HEIGHT)) >> 16
	set16(car + HEIGHT_ON_SCREEN, height)
	m.d0 = height
	if u16(car + DRAWN) != 1:
		return
	draw_body()
	draw_shadow_airborne()
	draw_wheels()


## $EEE2
func draw_body() -> void:
	var car := m.a6
	var sprite := u32(car + BODY_SPRITE)
	var zoom := u16(car + ZOOM)
	Sprite.zoom(m, sprite, zoom, zoom)
	var picture := m.r32(u32(car + BODY_PICTURES) + wrap16(u16(car + PICTURE_DIRECTION) * 4))
	Sprite.picture(m, sprite, picture)
	var x := u16(car + SCREEN_X) - u16(car + SIZE_X) + u16(car + MARGIN_X)
	var y := u16(car + SCREEN_Y) - u16(car + SIZE_Y) + u16(car + MARGIN_Y) - u16(car + HEIGHT_ON_SCREEN)
	var countdown := s16(car + SHAKE_COUNTDOWN) - 1
	if countdown < 0:
		set16(car + SHAKE_PHASE, ~u16(car + SHAKE_PHASE))
		countdown = u16(car + SHAKE_PERIOD)
		y -= u16(car + SHAKE_HEIGHT)
	set16(car + SHAKE_COUNTDOWN, countdown)
	Sprite.place(m, sprite, x, y)
	_leave_drawn(sprite, picture, x, y)


## $EF44: the shadow, on every other frame.
func draw_shadow() -> void:
	var car := m.a6
	var sprite := u32(car + SHADOW_SPRITE)
	var zoom := u16(car + ZOOM)
	Sprite.zoom(m, sprite, zoom, zoom)
	m.a0 = sprite
	m.d2 = with_low16(m.d2, zoom)
	var flicker := ~u16(car + SHADOW_FLICKER) & 0xFFFF
	set16(car + SHADOW_FLICKER, flicker)
	m.d0 = 1 if flicker != 0 else 0
	Sprite.show(m, sprite, flicker != 0)
	if flicker != 0:
		_place_shadow(sprite, u16(car + MARGIN_X), u16(car + MARGIN_Y))


## $EF9E: the shadow of the car in the air, smaller the higher the car is.
func draw_shadow_airborne() -> void:
	var car := m.a6
	var sprite := u32(car + SHADOW_SPRITE)
	var size := m.r16(SHADOW_SIZE_BY_HEIGHT + ((u16(car + HEIGHT) >> 8) & 0xFFFE))
	var zoom := (u16(car + ZOOM) * size) >> 8
	var margin_x := _margin_at_zoom(zoom, s16(car + SIZE_X))
	var margin_y := _margin_at_zoom(zoom, s16(car + SIZE_Y))
	Sprite.zoom(m, sprite, zoom, zoom)
	m.a0 = sprite
	m.a1 = SHADOW_SIZE_BY_HEIGHT
	m.d2 = with_low16(m.d2, zoom)
	var flicker := ~u16(car + SHADOW_FLICKER) & 0xFFFF
	set16(car + SHADOW_FLICKER, flicker)
	m.d0 = 1 if flicker != 0 else 0
	Sprite.show(m, sprite, flicker != 0)
	if flicker != 0:
		_place_shadow(sprite, margin_x, margin_y)


func _place_shadow(sprite: int, margin_x: int, margin_y: int) -> void:
	var car := m.a6
	var picture := m.r32(u32(car + SHADOW_PICTURES) + wrap16(u16(car + PICTURE_DIRECTION) * 4))
	Sprite.picture(m, sprite, picture)
	var x := u16(car + SCREEN_X) - u16(car + SIZE_X) + margin_x
	var y := u16(car + SCREEN_Y) - u16(car + SIZE_Y) + margin_y
	Sprite.place(m, sprite, x, y)
	m.a3 = picture
	m.d2 = with_low16(m.d2, y)


## $F0AA: the wheels, turned the way the car is steered.
func draw_wheels() -> void:
	var car := m.a6
	var sprite := u32(car + WHEELS_SPRITE)
	var zoom := u16(car + ZOOM)
	Sprite.zoom(m, sprite, zoom, zoom)
	if u16(car + SPEED) != 0:
		var countdown := s16(car + WHEELS_COUNTDOWN) - 1
		if countdown < 0:
			set16(car + WHEELS_PHASE, ~u16(car + WHEELS_PHASE))
			countdown = 1
		set16(car + WHEELS_COUNTDOWN, countdown)
	var pictures := u32(car + WHEEL_PICTURES + wrap16(u16(car + STEER) * 4))
	var index := wrap16(u16(car + PICTURE_DIRECTION) << 3)
	if u16(car + WHEELS_PHASE) != 0:
		index = wrap16(index + 4)
	var picture := m.r32(pictures + index)
	Sprite.picture(m, sprite, picture)
	var x := u16(car + SCREEN_X) - u16(car + SIZE_X) + u16(car + MARGIN_X)
	var y := u16(car + SCREEN_Y) - u16(car + SIZE_Y) + u16(car + MARGIN_Y) - u16(car + HEIGHT_ON_SCREEN)
	if s16(car + HEIGHT) > 0x800:
		y += 2
	Sprite.place(m, sprite, x, y)
	_leave_drawn(sprite, picture, x, y)


## Leaves in the registers what the original does after drawing a part.
func _leave_drawn(sprite: int, picture: int, x: int, y: int) -> void:
	m.a0 = sprite
	m.a3 = picture
	m.d0 = with_low16(m.d0, x)
	m.d2 = with_low16(m.d2, y)


## A speed without its sign, as the game takes it (16 bits).
static func _magnitude(speed: int) -> int:
	return wrap16(-speed) if speed < 0 else speed


## The angle from `from` to `to` the short way round: x is how far (0 to
## $8000), y is 1 if that is towards larger angles and -1 if towards smaller.
static func _angle_between(to: int, from: int) -> Vector2i:
	var apart := to - from
	var side := 1
	if apart < 0:
		side = -1
		apart = -apart
	if apart > 0x8000:
		side = -side
		apart = (0x10000 - apart) & 0x7FFF
	return Vector2i(apart, side)
