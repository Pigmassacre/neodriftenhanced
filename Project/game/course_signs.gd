extends GameRoutines
## Signs that come up on screen during a race: the one for a checkpoint
## reached, and those the course asks for where the car drives into a
## marked part of it (the course has a map of sign numbers, one for each
## 256 by 256 pixels).

const Sprite := preload("res://game/sprite_object.gd")
const RaceClock := preload("res://game/race_clock.gd")

## Not 0 while no signs are shown.
const PAUSED := 0x10329A
## The checkpoint sign's sprite object.
const CHECKPOINT_SIGN := 0x10329C
## The map: its width and height in cells, and where its cells are.
const MAP_COLUMNS := 0x10328C
const MAP_ROWS := 0x10328E
const MAP := 0x103290
## Where the car is (set by car.gd).
const CAR_X := 0x103294
const CAR_Y := 0x103296
## The sign number of the last marked cell the car was in.
const LAST_SIGN := 0x103298
## The sign showing: the routine that plays it each frame (0 for none)
## and the one that takes it away. The routines keep more after these.
const SHOWING := 0x10324C
const SHOWING_END := 0x04
## What shows a sign: routines to start it (D0 is 0 after if it could
## not), to take it away and to play it, all with SHOWING in A1.
const SIGN_ROUTINES := 0x2A336

# --- the signs the course asks for ------------------------------------------

## What the sign's routines keep after SHOWING and SHOWING_END: its sprite
## object, how many frames it has played, and which sign it is, from 0.
const SIGN_SPRITE := 0x08
const SIGN_FRAMES := 0x0C
const SIGN_NUMBER := 0x0E
## The address of the table of the signs' pictures: a mark that grows from
## nothing, another that folds away, then the signs themselves. The
## checkpoint sign is among them.
const SIGN_PICTURES := 0x80008
const MARK_PICTURE := 0
const FOLDING_PICTURE := 1
const CHECKPOINT_PICTURE := 0x17
const IN_FRONT := 0x7FFF
const CHECKPOINT_X := 0x20
const CHECKPOINT_Y := 0x40
## A sign plays in five parts, each up to and with this frame: the mark
## grows towards its place, the sign appears, it flashes, it stays, and it
## folds away.
const GROWS_UNTIL := 0x0F
const APPEARS_UNTIL := 0x12
const FLASHES_UNTIL := 0x1A
const STAYS_UNTIL := 0x37
const FOLDS_UNTIL := 0x3F
## For each frame of growing three words: where it is and its zoom. The
## first eight frames are the even entries, the next eight the odd ones.
const GROWING := 0x2A342
const SIGN_X := 0x88
const SIGN_Y := 0x40
## By sign, the sound that goes with it, or 0.
const SIGN_SOUNDS := 0x2A166
const REQUEST_SOUND := 0x15256
## Added to the palettes of its picture: as it appears, and on every other
## frame while it flashes.
const PALETTE_APPEARING := 0xFFFD
const PALETTE_FLASH := 0xFFFE
## Folding away: its zoom down is a sine (a quarter turn in eight frames),
## and it moves down by this many pixels as it goes.
const SINE := 0x27A3A
const FOLD_DROP := 24
const FOLDED_Y := 0x58


func routines() -> Dictionary:
	return {
		0x14652: set_up,
		0x146E2: clear_away,
		0x14752: car_from_registers,
		0x14760: update,
		0x14700: start,
		0x14730: end,
		0x14804: start_sign,
		0x14848: end_sign,
		0x1485C: play_sign,
	}


func scratch() -> Dictionary:
	return {0x14760: ["a0", "ccr"], 0x14700: ["ccr"], 0x14730: ["ccr"], 0x14752: ["ccr"],
			0x14804: ["ccr"], 0x14848: ["ccr"], 0x1485C: ["ccr"]}


## $14760: a frame of the signs.
func update() -> void:
	var saved := [m.d0, m.d2, m.a1, m.a3]
	if u16(PAUSED) == 0:
		var frames := u16(RaceClock.CHECKPOINT_SIGN_FRAMES)
		if frames != 0:
			set16(RaceClock.CHECKPOINT_SIGN_FRAMES, frames - 1)
		m.a0 = u32(CHECKPOINT_SIGN)
		Sprite.show(m, m.a0, frames != 0)
		var columns := u16(MAP_COLUMNS)
		var cell := (u16(CAR_Y) >> 8) % u16(MAP_ROWS) * columns + (u16(CAR_X) >> 8) % columns
		var sign := m.r8(u32(MAP) + wrap16(cell))
		if sign != 0:
			var last := u8(LAST_SIGN)
			set8(LAST_SIGN, sign)
			if sign != last:
				m.a3 = SIGN_ROUTINES
				m.d0 = with_low16(m.d0, sign)
				start()
	m.a1 = SHOWING
	if u32(SHOWING) != 0:
		m.a3 = u32(SHOWING)
		m.call_routine(m.a3)
	m.d0 = saved[0]; m.d2 = saved[1]; m.a1 = saved[2]; m.a3 = saved[3]


## $14700: shows sign D0 with the routines at A3, in place of any other.
func start() -> void:
	var saved := [m.d0, m.a1, m.a3]
	var sign_routines := m.a3
	end()
	m.a1 = SHOWING
	set32(SHOWING, m.r32(sign_routines + 8))
	set32(SHOWING + SHOWING_END, m.r32(sign_routines + 4))
	m.a3 = m.r32(sign_routines)
	m.call_routine(m.a3)
	if low16(m.d0) == 0:
		set32(SHOWING, 0)
	m.d0 = saved[0]; m.a1 = saved[1]; m.a3 = saved[2]


## $14730: takes away the sign that is showing.
func end() -> void:
	if u32(SHOWING) == 0:
		return
	var saved := [m.a1, m.a3]
	m.a1 = SHOWING
	m.a3 = u32(SHOWING + SHOWING_END)
	m.call_routine(m.a3)
	set32(SHOWING, 0)
	m.a1 = saved[0]; m.a3 = saved[1]


## $14652: sets up the signs of a course. A4 is its map of signs (cells
## across, cells down, then a byte for each cell), D0 and D2 where the car
## is. Changes no register.
func set_up() -> void:
	set32(SHOWING, 0)
	set16(MAP_COLUMNS, m.r16(m.a4))
	set16(MAP_ROWS, m.r16(m.a4 + 2))
	set32(MAP, m.a4 + 4)
	set16(CAR_X, m.d0)
	set16(CAR_Y, m.d2)
	set8(LAST_SIGN, 0)
	set16(PAUSED, 0)
	var sprite := Sprite.take_record(m)
	set32(CHECKPOINT_SIGN, sprite)
	if sprite != 0:
		set16(sprite + Sprite.DEPTH, IN_FRONT)
		Sprite.place(m, sprite, CHECKPOINT_X, CHECKPOINT_Y)
		Sprite.picture(m, sprite, _picture(CHECKPOINT_PICTURE))
		Sprite.show(m, sprite, false)
	set16(RaceClock.CHECKPOINT_SIGN_FRAMES, 0)


## $146E2: takes all signs away. Changes no register.
func clear_away() -> void:
	Sprite.free_record(m, u32(CHECKPOINT_SIGN))
	end()


## $14752: where the car is, in D0 and D2.
func car_from_registers() -> void:
	set16(CAR_X, m.d0)
	set16(CAR_Y, m.d2)


func _picture(number: int) -> int:
	return m.r32(m.r32(SIGN_PICTURES) + number * 4)


## $14804: starts sign D0 (from 1). Leaves 1 in D0, or 0 if nothing is
## free to draw it with.
func start_sign() -> void:
	var showing := m.a1
	var sprite := Sprite.take_record(m)
	set32(showing + SIGN_SPRITE, sprite)
	if sprite == 0:
		m.d0 = with_low16(m.d0, 0)
		return
	set16(showing + SIGN_NUMBER, m.d0 - 1)
	Sprite.picture(m, sprite, _picture(MARK_PICTURE))
	set16(sprite + Sprite.DEPTH, IN_FRONT)
	set16(showing + SIGN_FRAMES, 0)
	m.d0 = 1


## $14848
func end_sign() -> void:
	Sprite.free_record(m, u32(m.a1 + SIGN_SPRITE))


## $1485C: a frame of the sign.
func play_sign() -> void:
	var showing := m.a1
	var sprite := u32(showing + SIGN_SPRITE)
	var frames := u16(showing + SIGN_FRAMES)
	var number := u16(showing + SIGN_NUMBER)
	if frames <= GROWS_UNTIL:
		var entry := (frames * 2 if frames < 8 else (frames - 8) * 2 + 1) * 6
		m.d1 = with_low16(m.d1, entry)
		Sprite.place(m, sprite, m.r16(GROWING + entry), m.r16(GROWING + entry + 2))
		var zoom := m.r16(GROWING + entry + 4)
		Sprite.zoom(m, sprite, zoom, zoom)
	elif frames <= APPEARS_UNTIL:
		if frames == GROWS_UNTIL + 1:
			var sound := m.r16(SIGN_SOUNDS + wrap16(number * 2))
			if sound != 0:
				var saved := m.d0
				m.d0 = with_low16(m.d0, sound)
				m.call_routine(REQUEST_SOUND)
				m.d0 = saved
		Sprite.picture(m, sprite, m.r32(m.r32(SIGN_PICTURES) + wrap16(number * 4)))
		Sprite.place(m, sprite, SIGN_X, SIGN_Y)
		Sprite.zoom(m, sprite, 0x100, 0x100)
		set16(sprite + Sprite.PALETTE, PALETTE_APPEARING)
	elif frames <= FLASHES_UNTIL:
		set16(sprite + Sprite.PALETTE, PALETTE_FLASH if frames & 1 else 0)
	elif frames <= STAYS_UNTIL:
		pass
	elif frames <= FOLDS_UNTIL:
		Sprite.picture(m, sprite, _picture(FOLDING_PICTURE))
		var down := rom_s16(SINE + ((FOLDS_UNTIL + 1 - frames) << 6))
		Sprite.zoom(m, sprite, 0x100, down)
		Sprite.place(m, sprite, SIGN_X, (wrap16(down * -FOLD_DROP) >> 8) + FOLDED_Y)
	else:
		end()
	set16(showing + SIGN_FRAMES, frames + 1)
