extends GameRoutines
## "How to play", shown before a game: a script drives a car while a
## picture of the joystick or of a button shows what is being done, with a
## caption. Button A skips it.

const Car := preload("res://game/car.gd")
const Sprite := preload("res://game/sprite_object.gd")
const Palettes := preload("res://game/palettes.gd")
const Joystick := preload("res://game/joystick.gd")

const CAR := 0x101508
const PLAYER := 0x1011FC
const COURSE := 0x101202
## The sprite objects: two halves of the backdrop and the heading; what is
## pressed; and the caption.
const SPRITES := 0x10116A
const CONTROL_SPRITE := 0x101176
const CAPTION_SPRITE := 0x10117A
## The script: which step it is at and was at, what kind that is, and the
## frames left of it. Each step is a kind and a count of frames; the list
## ends with $FFFF.
const STEP_BEFORE := 0x10117E
const KIND := 0x101180
const STEP := 0x101182
const DRIVEN := 0x101184
const FRAMES := 0x101186
const SCRIPT := 0x666A
enum {RELEASE_BUTTON, PRESS_BUTTON, STICK_CENTRE, STICK_LEFT, STICK_RIGHT, SHOW_FIRST, SHOW_SECOND, SHOW_THIRD}
## By kind: how fast the car turns (16.16 of 32 directions a frame) and
## what is added to its speed a frame.
const DRIVING := 0x65CA
## Which way the car faces (16.16, of 32), and how far the backdrop has
## moved.
const FACING := 0x101188
const BACKDROP_X := 0x10118C
const FACING_RIGHT := 0
const FACING_UP := 0x18
const FIRST_SPEED := 0x325
const DRAG := 7
const TOP_SPEED := 0x1200
const TOP_SPEED_BACK := -0x800
## How far the stick leans (-3 to 3) and for how many frames it has; how
## far the button is in (0 to 15); and where the picture of either is.
const LEAN := 0x101190
const LEAN_FRAMES := 0x101192
const FRAMES_A_LEAN := 4
const PRESSED := 0x101194
const FULLY_PRESSED := 15
const CONTROL_X := 0x101196
const CONTROL_Y := 0xC0
## By lean, eight bytes: the picture, x and y.
const STICKS := 0x682A
## By how far the button is in, how tall its picture is (in eighths).
const BUTTON_HEIGHTS := 0x6920
## By kind, the picture shown for the three last kinds, and for every
## kind the caption (eight bytes: picture, x, y).
const SHOWN_PICTURES := 0x6970
const CAPTIONS := 0x64B4
## The address of the pictures of the backdrop and the heading.
const PICTURES := 0x6AB0
const FIRST_PALETTE := 0x40
const PALETTE_COUNT := 6
const COLOURS := 0x6990
const CLEAR_TEXT := 0xA26
const CLEAR_SPRITES := 0x120E0
const BUILD_SPRITES := 0x1229E
const LOAD_COLOURS := 0x1690E


func routines() -> Dictionary:
	return {
		0x620C: set_up,
		0x6314: start_script,
		0x633A: set_up_car,
		0x6388: set_up_control,
		0x63F4: set_up_caption,
		0x641A: update,
		0x646E: free_sprites,
		0x6486: show_caption,
		0x64F4: drive,
		0x65EA: func() -> void: set16(DRIVEN, u16(DRIVEN) | (m.d0 & 0xFFFF)),
		0x65F2: func() -> void: set16(DRIVEN, 0),
		0x65FC: func() -> void: m.d0 = with_low16(m.d0, 1 if _next_step() else 0),
		0x66A8: show_control,
		0x6706: centre_stick,
		0x6768: lean_stick.bind(-1),
		0x67A8: lean_stick.bind(1),
		0x67E6: show_stick,
		0x6842: release_button,
		0x68B8: press_button,
		0x6940: show_picture,
	}


func scratch() -> Dictionary:
	var free := ["d0", "d1", "d2", "d3", "d4", "d6", "d7", "a0", "a1", "a3", "a5", "ccr"]
	var table := {}
	for address: int in routines():
		table[address] = free
	table[0x620C] = ["d0.high", "d7", "ccr"]
	table[0x641A] = ["d0.high", "d6", "d7", "ccr"]
	table[0x65FC] = ["d0.high", "d1", "a0", "ccr"]
	return table


func _picture(which: int) -> int:
	return m.r32(m.r32(PICTURES) + which)


## $620C
func set_up() -> void:
	var saved := [m.d1, m.d2, m.d3, m.d4, m.d5, m.d6, m.a0, m.a1, m.a2, m.a3, m.a4, m.a5, m.a6]
	m.call_routine(CLEAR_TEXT)
	m.call_routine(CLEAR_SPRITES)
	set16(Car.MACHINE, 0)
	set16(COURSE, 0)
	set16(Car.CHOSEN_CAR, 0)
	m.d0 = with_low16(m.d0, 0x12)
	m.call_routine(LOAD_COLOURS)
	(sibling(Palettes) as Palettes).queue(FIRST_PALETTE, PALETTE_COUNT, COLOURS, 0x100)
	for index in 3:
		set32(SPRITES + index * 4, Sprite.take_record(m))
	for half in 2:
		Sprite.place(m, u32(SPRITES + half * 4), half * 0x100, 0)
		Sprite.picture(m, u32(SPRITES + half * 4), _picture(8))
	Sprite.place(m, u32(SPRITES + 8), 0x30, 0x20)
	Sprite.picture(m, u32(SPRITES + 8), _picture(0xC))
	set16(DRIVEN, 0)
	start_script()
	m.call_routine(BUILD_SPRITES)
	set_up_control()
	set_up_caption()
	m.a6 = CAR
	set_up_car()
	m.d1 = saved[0]; m.d2 = saved[1]; m.d3 = saved[2]; m.d4 = saved[3]; m.d5 = saved[4]; m.d6 = saved[5]
	m.a0 = saved[6]; m.a1 = saved[7]; m.a2 = saved[8]; m.a3 = saved[9]; m.a4 = saved[10]; m.a5 = saved[11]
	m.a6 = saved[12]
	m.d0 = with_low16(m.d0, 0)


## $6314
func start_script() -> void:
	set16(KIND, m.r16(SCRIPT))
	set16(FRAMES, m.r16(SCRIPT + 2))
	set16(STEP, 0)
	set16(STEP_BEFORE, 0)


## $633A: the car in A6, in the middle of the screen and facing up.
func set_up_car() -> void:
	var car := sibling(Car) as Car
	car.set_up()
	set16(m.a6 + Car.ZOOM_TARGET, 0x100)
	set16(m.a6 + Car.ZOOM, 0x100)
	set16(m.a6 + Car.ZOOM_BEFORE, 0x100)
	car.set_depth()
	set32(m.a6 + Car.SCREEN_X, 0xA0 << 16)
	set16(BACKDROP_X, 0)
	set32(m.a6 + Car.SCREEN_Y, 0x100 << 16)
	set32(FACING, FACING_UP << 16)
	set16(m.a6 + Car.PICTURE_DIRECTION, FACING_UP)
	set16(m.a6 + Car.SPEED, FIRST_SPEED)


## $6388
func set_up_control() -> void:
	set16(LEAN, 0)
	set16(LEAN_FRAMES, 0)
	set16(PRESSED, 0)
	var sprite := Sprite.take_record(m)
	set32(CONTROL_SPRITE, sprite)
	Sprite.show(m, sprite, false)
	Sprite.zoom(m, sprite, 0x100, m.r16(BUTTON_HEIGHTS) << 3)
	set16(CONTROL_X, 0xE8)
	Sprite.place(m, sprite, 0xE8, CONTROL_Y)
	set16(sprite + Sprite.DEPTH, 1)


## $63F4
func set_up_caption() -> void:
	var sprite := Sprite.take_record(m)
	set32(CAPTION_SPRITE, sprite)
	Sprite.place(m, sprite, 0x10, 0xC0)
	set16(sprite + Sprite.DEPTH, 1)


## $641A: a frame of it. Leaves 0 in D0 when it is over.
func update() -> void:
	var saved := [m.d1, m.d2, m.d3, m.d4, m.d5, m.a0, m.a1, m.a2, m.a3, m.a4, m.a5, m.a6]
	var going_on := false
	if not (sibling(Joystick) as Joystick).pressed(u16(PLAYER), Joystick.BUTTON_A):
		m.a6 = CAR
		drive()
		show_control()
		show_caption()
		m.call_routine(BUILD_SPRITES)
		going_on = _next_step()
	if not going_on:
		free_sprites()
	m.d1 = saved[0]; m.d2 = saved[1]; m.d3 = saved[2]; m.d4 = saved[3]; m.d5 = saved[4]
	m.a0 = saved[5]; m.a1 = saved[6]; m.a2 = saved[7]; m.a3 = saved[8]; m.a4 = saved[9]; m.a5 = saved[10]
	m.a6 = saved[11]
	m.d0 = with_low16(m.d0, 1 if going_on else 0)


## $646E
func free_sprites() -> void:
	for index in 3:
		Sprite.free_record(m, u32(SPRITES + index * 4))


## $6486
func show_caption() -> void:
	var entry := CAPTIONS + wrap16(u16(KIND) << 3)
	var sprite := u32(CAPTION_SPRITE)
	Sprite.picture(m, sprite, m.r32(entry))
	Sprite.place(m, sprite, m.r16(entry + 4), m.r16(entry + 6))


## $64F4: the car in A6 turns and speeds up as this kind of step says.
## Facing right it stays where it is and the backdrop moves; facing up it
## moves itself.
func drive() -> void:
	var car := m.a6
	var entry := DRIVING + wrap16(u16(KIND) * 4)
	var facing := (u32(FACING) + wrap16(m.r16(entry))) & 0x1FFFFF
	set32(FACING, facing)
	set16(car + Car.PICTURE_DIRECTION, facing >> 16)
	var speed := wrap16(u16(car + Car.SPEED) + m.r16(entry + 2))
	if speed > 0:
		speed -= DRAG
		speed = 0 if speed <= 0 else mini(speed, TOP_SPEED)
	elif speed < 0:
		speed += DRAG
		speed = 0 if speed >= 0 else maxi(speed, TOP_SPEED_BACK)
	set16(car + Car.SPEED, speed)
	var moved := speed >> 8
	if facing >> 16 == FACING_RIGHT:
		var x := (u16(BACKDROP_X) - moved) & 0x1FF
		set16(BACKDROP_X, x)
		Sprite.place(m, u32(SPRITES), x, 0)
		Sprite.place(m, u32(SPRITES + 4), (x + 0x100) & 0x1FF, 0)
	elif facing >> 16 == FACING_UP:
		set16(car + Car.SCREEN_Y, u16(car + Car.SCREEN_Y) - moved)
	(sibling(Car) as Car).draw_on_ground()
	set16(DRIVEN, u16(DRIVEN) | 1)


## $65FC: a frame of the script passes. Returns false at its end.
func _next_step() -> bool:
	if u16(FRAMES) == 0 or u16(DRIVEN) != 1:
		set16(STEP_BEFORE, u16(STEP))
		set16(DRIVEN, 0)
		set16(STEP, u16(STEP) + 1)
		var entry := SCRIPT + wrap16(u16(STEP) * 4)
		set16(KIND, m.r16(entry))
		if m.r16(entry) == 0xFFFF:
			return false
		set16(FRAMES, m.r16(entry + 2))
	set16(FRAMES, u16(FRAMES) - 1)
	return true


## $66A8: the picture of the control this kind of step uses.
func show_control() -> void:
	match u16(KIND):
		RELEASE_BUTTON: release_button()
		PRESS_BUTTON: press_button()
		STICK_CENTRE: centre_stick()
		STICK_LEFT: lean_stick(-1)
		STICK_RIGHT: lean_stick(1)
		SHOW_FIRST, SHOW_SECOND, SHOW_THIRD: show_picture()


## $6706: the stick comes back upright, a step every four frames.
func centre_stick() -> void:
	var lean := s16(LEAN)
	if lean == 0:
		if u16(LEAN_FRAMES) == 0:
			show_stick()
			set16(LEAN_FRAMES, 1)
	elif s16(LEAN_FRAMES) < FRAMES_A_LEAN:
		set16(LEAN_FRAMES, u16(LEAN_FRAMES) + 1)
	else:
		set16(LEAN_FRAMES, 0)
		set16(LEAN, lean + (1 if lean < 0 else -1))
		show_stick()


## $6768 and $67A8: the stick leans further to one side.
func lean_stick(side: int) -> void:
	var lean := s16(LEAN)
	if side < 0 and lean < -2:
		return
	if side > 0 and u16(LEAN) > 2:
		return
	var frames := s16(LEAN_FRAMES)
	if frames != 0 and frames >= FRAMES_A_LEAN:
		set16(LEAN_FRAMES, 0)
		set16(LEAN, lean + side)
		return
	if frames == 0:
		show_stick()
	set16(LEAN_FRAMES, frames + 1)


## $67E6
func show_stick() -> void:
	var entry := STICKS + wrap16(u16(LEAN) << 3)
	var sprite := u32(CONTROL_SPRITE)
	Sprite.picture(m, sprite, m.r32(entry))
	set16(CONTROL_X, m.r16(entry + 4))
	Sprite.place(m, sprite, m.r16(entry + 4), m.r16(entry + 6))


## The button's picture as tall as it is far in.
func _show_button(pressed: int) -> void:
	var sprite := u32(CONTROL_SPRITE)
	if pressed == 1:
		Sprite.show(m, sprite, true)
	var height := m.r16(BUTTON_HEIGHTS + wrap16(pressed * 2))
	Sprite.zoom(m, sprite, 0x100, height << 3)
	Sprite.place(m, sprite, u16(CONTROL_X), CONTROL_Y - height)


## $68B8
func press_button() -> void:
	var pressed := u16(PRESSED)
	if pressed >= FULLY_PRESSED:
		set16(PRESSED, FULLY_PRESSED)
		return
	_show_button(pressed)
	set16(PRESSED, pressed + 1)


## $6842
func release_button() -> void:
	var pressed := s16(PRESSED)
	if pressed <= 0:
		set16(PRESSED, 0)
		Sprite.show(m, u32(CONTROL_SPRITE), false)
		return
	_show_button(pressed)
	set16(PRESSED, pressed - 1)


## $6940
func show_picture() -> void:
	var sprite := u32(CONTROL_SPRITE)
	Sprite.picture(m, sprite, m.r32(SHOWN_PICTURES + wrap16(u16(KIND) * 4)))
	set16(CONTROL_X, 0x98)
	Sprite.place(m, sprite, 0x98, 0xA0)
