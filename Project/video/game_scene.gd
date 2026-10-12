class_name GameScene
extends RefCounted
## What the game wants drawn, taken from its own records at the moments it
## hands them to the video hardware: the ground under the camera and the
## list of things on it ("sprite objects", see game/sprite_object.gd).
##
## The original turns these into hardware sprites: 32 of them scroll the
## ground ($1348E-$13E12) and up to 128 show the objects ($1229E). That
## limits the picture to the hardware's 320 pixels and to 128 columns of
## objects. NeoGeoVideo draws from this instead, at any width.

## The records of the things to draw: 64 of $16 bytes.
const OBJECTS := 0x1B20
const OBJECT_COUNT := 64
const OBJECT_SIZE := 0x16
## A record's fields (as in game/sprite_object.gd), and one more: a palette
## to use for every tile instead of the picture's own, when not 0.
const SHOWN := 0x00
const DEPTH := 0x02
const X := 0x04
const Y := 0x06
const ZOOM_X := 0x08
const ZOOM_Y := 0x0A
const COLUMNS := 0x0C
const ROWS := 0x0E
const PICTURE_BODY := 0x10
const PALETTE := 0x14
## The hardware has 128 sprites for objects, one for each column.
const HARDWARE_COLUMNS := 128
## By sixteenths of the zoom across, for each column of an object how much
## its width changes from the column before (in the high byte).
const COLUMN_WIDTH_STEPS := 0x292E2
## Below this zoom across a column is at most one pixel wide and some are
## left out.
const SMALLEST_COLUMN_ZOOM := 0x10

## The ground: 1 while it is drawn, where the camera is and the zoom
## (8.8 fixed point), and the course's map: how many blocks of 16 by 16
## tiles it is across and down, the address of the block number of each
## place, how many blocks there are and the address of their addresses.
const GROUND_ON := 0x2530
const GROUND_CAMERA := 0x2534
const GROUND_ZOOM := 0x2538
const MAP_ACROSS := 0x253C
const MAP_DOWN := 0x253E
const MAP_PLACES := 0x2540
const BLOCK_COUNT := 0x2544
const BLOCKS := 0x2546

## Where the game hands its records to the hardware.
const BUILD_SPRITES := 0x1229E
const SPRITES_TAKEN := 0x12198
const CLEAR_SPRITES := 0x120E0
const SCROLL_GROUND := 0x13546
const GROUND_TAKEN := 0x1366A
const GROUND_OFF := 0x133FA
const REDRAW_GROUND := 0x1348E
## Where the ground was when the original last scrolled it, and what it
## kept for its two sets of sprite positions.
const GROUND_DRAWN := 0x254A
const GROUND_PENDING := 0x2532
const GROUND_POSITIONS := 0x25D2

## Colours the game has set wait in a ring of entries of $24 bytes (where
## in palette memory, then 16 colours) for the vertical blank ($11F3E): the
## ring, its end, and where the address of the next entry to take is kept.
const COLOUR_RING := 0x1700
const COLOUR_RING_END := 0x1B14
const COLOUR_RING_NEXT := 0x1B18
const COLOUR_ENTRY := 0x24

## Bit 7 is set while the game, not the system ROM, has the screen.
const SYSTEM_MODE := 0xFD80

## Tiles in the texture row of a strip, and bytes for each.
const STRIP_TILES := 32
const STRIP_BYTES := STRIP_TILES * 4
## Numbers kept for each strip in `strips`: x, top line, rows, the hardware's
## shrink across (0-15) and down (0-255).
const STRIP_FIELDS := 5

var machine: NeoGeoMachine
## With this the picture changes when the hardware's would: at the vertical
## blank after the game has built it. Without, as soon as it is built, a
## frame earlier.
var hardware_timing := false
## Leaves out what the hardware has no sprites for.
var hardware_limits := false

## The objects to draw, a column ("strip") at a time, in drawing order, and
## the tiles of each: four bytes a tile as the picture has them (tile number,
## flips and palette), STRIP_TILES tiles a strip.
var strips := PackedInt32Array()
var strip_tiles := PackedByteArray()
## True while the ground is drawn, and from where.
var ground_on := false
var camera := Vector2i.ZERO
var zoom := Vector2i(0x100, 0x100)
var map_across := 0
var map_down := 0
var map_places := 0
var block_count := 0
var blocks := 0

var _pending_strips := PackedInt32Array()
var _pending_tiles := PackedByteArray()
var _pending_ground: Array = []
var _blank := PackedByteArray()


func _init(for_machine: NeoGeoMachine) -> void:
	machine = for_machine
	_blank.resize(STRIP_BYTES)
	machine.hook_block(BUILD_SPRITES, _build_sprites)
	machine.hook_block(SPRITES_TAKEN, _take_sprites)
	machine.hook_block(CLEAR_SPRITES, _clear_sprites)
	machine.hook_block(SCROLL_GROUND, _scroll_ground)
	machine.hook_block(GROUND_TAKEN, _take_ground)
	machine.hook_block(GROUND_OFF, _ground_off)


## Takes the original's drawing code out of the game: what made hardware
## sprites of the records ($1229E) and what kept the ground's 32 sprites
## drawn and scrolled ($1348E, $13546). From then on only this scene has
## the game's picture, video RAM does not, and the game no longer spends
## a third of its time on it.
func replace_hardware_drawing() -> void:
	hardware_timing = false
	hardware_limits = false
	machine.replace_routine(BUILD_SPRITES, _build_sprites_only)
	machine.replace_routine(SCROLL_GROUND, _scroll_ground_only)
	machine.replace_routine(REDRAW_GROUND, _redraw_ground_only)
	# what the original had drawn so far would stay in video RAM for good
	for sprite in range(0x20, 0x140):
		machine.vram[0x8200 + sprite] = 0


## True while the game draws through its records, so that they say all
## there is to draw but the text.
func in_use() -> bool:
	return (machine.ram[SYSTEM_MODE ^ 1] & 0x80) != 0


## The colours the game has set that the hardware does not have yet, by
## number. A picture shown as soon as it is built needs them, as they were
## set along with it.
func colours_to_come() -> Dictionary:
	var colours := {}
	if hardware_timing:
		return colours
	var ram := machine.ram
	var entry := _long(COLOUR_RING_NEXT) & 0xFFFF
	for count in (COLOUR_RING_END - COLOUR_RING) / COLOUR_ENTRY:
		if entry < COLOUR_RING or entry >= COLOUR_RING_END:
			break
		var to := _long(entry)
		if to == 0:
			break
		var first := (to >> 1) & 0xFFF
		for index in 16:
			colours[(first + index) & 0xFFF] = ram.decode_u16(entry + 4 + index * 2)
		entry += COLOUR_ENTRY
		if entry == COLOUR_RING_END:
			entry = COLOUR_RING
	return colours


func _build_sprites() -> void:
	_gather()
	if not hardware_timing:
		_take_sprites()


func _take_sprites() -> void:
	strips = _pending_strips
	strip_tiles = _pending_tiles


func _clear_sprites() -> void:
	_pending_strips = PackedInt32Array()
	_pending_tiles = PackedByteArray()
	_take_sprites()


func _scroll_ground() -> void:
	var ram := machine.ram
	if ram.decode_u16(GROUND_ON) == 0:
		return
	_pending_ground = [
		Vector2i(ram.decode_u16(GROUND_CAMERA), ram.decode_u16(GROUND_CAMERA + 2)),
		Vector2i(ram.decode_u16(GROUND_ZOOM), ram.decode_u16(GROUND_ZOOM + 2)),
		ram.decode_u16(MAP_ACROSS), ram.decode_u16(MAP_DOWN), _long(MAP_PLACES),
		ram.decode_u16(BLOCK_COUNT), _long(BLOCKS),
	]
	if not hardware_timing:
		_take_ground()


func _take_ground() -> void:
	if _pending_ground.is_empty():
		return
	ground_on = true
	camera = _pending_ground[0]
	zoom = _pending_ground[1]
	map_across = _pending_ground[2]
	map_down = _pending_ground[3]
	map_places = _pending_ground[4]
	block_count = _pending_ground[5]
	blocks = _pending_ground[6]


func _ground_off() -> void:
	ground_on = false
	_pending_ground = []


## $1229E without the hardware. The original leaves interrupts allowed.
func _build_sprites_only() -> void:
	_gather()
	_take_sprites()
	machine.set_sr(machine.get_sr() & 0xF8FF)


## $13546 without the hardware.
func _scroll_ground_only() -> void:
	var ram := machine.ram
	if ram.decode_u16(GROUND_ON) == 0:
		return
	ram.encode_u16(GROUND_DRAWN, ram.decode_u16(GROUND_CAMERA))
	ram.encode_u16(GROUND_DRAWN + 2, ram.decode_u16(GROUND_CAMERA + 2))
	_scroll_ground()
	machine.set_sr(machine.get_sr() & 0xF8FF)


## $1348E without the hardware: starts drawing the ground of the map in A4
## and A5, with the camera at D0, D1 and the zoom D2, D3.
func _redraw_ground_only() -> void:
	var ram := machine.ram
	ram.encode_u16(GROUND_ON, 1)
	ram.encode_u16(GROUND_PENDING, 0)
	_set_long(GROUND_POSITIONS, 0x1025DA)
	_set_long(GROUND_POSITIONS + 4, 0x1026DC)
	ram.encode_u16(MAP_ACROSS, machine.r16(machine.a4))
	ram.encode_u16(MAP_DOWN, machine.r16(machine.a4 + 2))
	_set_long(MAP_PLACES, machine.a4 + 4)
	ram.encode_u16(BLOCK_COUNT, machine.r16(machine.a5))
	_set_long(BLOCKS, machine.a5 + 2)
	for at: int in [GROUND_DRAWN, GROUND_CAMERA]:
		ram.encode_u16(at, machine.d0 & 0xFFFF)
		ram.encode_u16(at + 2, machine.d1 & 0xFFFF)
	ram.encode_u16(GROUND_ZOOM, machine.d2 & 0xFFFF)
	ram.encode_u16(GROUND_ZOOM + 2, machine.d3 & 0xFFFF)
	_scroll_ground_only()


func _set_long(offset: int, value: int) -> void:
	machine.ram.encode_u16(offset, (value >> 16) & 0xFFFF)
	machine.ram.encode_u16(offset + 2, value & 0xFFFF)


func _long(offset: int) -> int:
	return (machine.ram.decode_u16(offset) << 16) | machine.ram.decode_u16(offset + 2)


## The records that are shown, lowest depth first. Equal depths come out in
## the order the original's sort leaves them in ($133A0).
func _shown_in_order() -> PackedInt32Array:
	var ram := machine.ram
	var records := PackedInt32Array()
	var depths := PackedInt32Array()
	for index in OBJECT_COUNT:
		var record := OBJECTS + index * OBJECT_SIZE
		if ram.decode_u16(record + SHOWN) == 1:
			records.append(record)
			depths.append(ram.decode_s16(record + DEPTH))
	var count := records.size()
	for index in count - 1:
		var lowest := index
		var depth := depths[index]
		for other in range(index + 1, count):
			if depths[other] < depth:
				lowest = other
				depth = depths[other]
		if lowest != index:
			depths[lowest] = depths[index]
			depths[index] = depth
			var record := records[lowest]
			records[lowest] = records[index]
			records[index] = record
	return records


## Makes the strips of everything shown, as $1229E makes hardware sprites.
func _gather() -> void:
	var ram := machine.ram
	var rom := machine.rom
	var made := PackedInt32Array()
	var tiles := PackedByteArray()
	var columns_left := HARDWARE_COLUMNS
	for record in _shown_in_order():
		var columns := ram.decode_u16(record + COLUMNS)
		if hardware_limits:
			if columns > columns_left:
				break
			columns_left -= columns
		var rows := mini(ram.decode_u16(record + ROWS), STRIP_TILES)
		var x := ram.decode_s16(record + X)
		# the hardware counts lines in nine bits; 240 on are above the picture
		var top := ram.decode_u16(record + Y) & 0x1FF
		if top >= 240:
			top -= 0x200
		var zoom_x := ram.decode_u16(record + ZOOM_X)
		var zoom_y := ram.decode_u16(record + ZOOM_Y)
		var palette := ram.decode_u16(record + PALETTE)
		var body := _long(record + PICTURE_BODY) & 0xFFFFFF
		var source := rom
		if body >= 0x100000 and body < 0x200000:
			source = ram
			body &= 0xFFFF
		elif body >= 0x200000:
			body -= 0x100000
		var column_bytes := rows * 4
		var narrow := zoom_x < SMALLEST_COLUMN_ZOOM
		var control := (zoom_y - 1) & 0xFFFF
		var steps := 0
		var owed := -8
		if not narrow:
			control = ((((zoom_x << 4) - 0x100) & 0xF00) + zoom_y - 1) & 0xFFFF
			steps = COLUMN_WIDTH_STEPS + (zoom_x & 0xF) * 64
		var shrink_y := control & 0xFF
		for column in columns:
			if narrow:
				# some columns are left out, the others are a pixel wide
				owed += zoom_x
				if owed < 0:
					continue
				owed -= 0x10
			else:
				control = (control + rom.decode_u16(steps + column * 2)) & 0xFFFF
			var shrink_x := (control >> 8) & 0xF
			made.append(x)
			made.append(top)
			made.append(rows)
			made.append(shrink_x)
			made.append(shrink_y)
			x += shrink_x + 1
			var from := body + column * column_bytes
			var at := tiles.size()
			tiles.append_array(source.slice(from, from + column_bytes))
			if palette != 0:
				for row in rows:
					tiles[at + row * 4 + 3] = palette & 0xFF
			tiles.append_array(_blank.slice(column_bytes))
	_pending_strips = made
	_pending_tiles = tiles
