extends GameRoutines
## Things on screen. The game keeps a record for each thing it draws and
## everything shown is drawn from them once a frame (video/game_scene.gd;
## the original built hardware sprites from them at $1229E). These are the
## routines the rest of the game uses to change such a record, in register A0.

## 1 when shown, 2 when hidden.
const SHOWN := 0x00
## Things with a larger number are drawn over those with a smaller one.
const DEPTH := 0x02
## Where its top left is on screen, in pixels.
const X := 0x04
const Y := 0x06
## Zoom across and down, 8.8 fixed point ($100 = 1:1).
const ZOOM_X := 0x08
const ZOOM_Y := 0x0A
## The first two words of its picture, and the address of the rest.
const PICTURE_HEAD := 0x0C
const PICTURE_BODY := 0x10
const PALETTE := 0x14

## The records: 64 of $16 bytes. The first word of a free one is 0.
const RECORDS := 0x101B20
const RECORD_COUNT := 64
const RECORD_SIZE := 0x16
## More of them, in work RAM the original never uses, for when the machine
## has `more_room`.
const MORE_RECORDS := 0x109000
const MORE_RECORD_COUNT := 64
## What a record is given to start with: shown at 32, 32, a blank picture
## of 4 by 4 tiles.
const FIRST_PLACE := 0x20
const BLANK_PICTURE_HEAD := 4
const BLANK_PICTURE_BODY := 0x292A2
## Where the original, having cleared its 64 records, goes on ($120E0).
const RECORDS_CLEARED := 0x1217A


func routines() -> Dictionary:
	return {
		0x12202: take_free_record,
		0x12256: depth_from_registers,
		0x1225C: place_from_registers,
		0x12266: zoom_from_registers,
		0x12270: picture_from_registers,
		0x12286: show_from_registers,
	}


func scratch() -> Dictionary:
	return {0x12202: ["ccr"], 0x12256: ["ccr"], 0x1225C: ["ccr"], 0x12266: ["ccr"], 0x12270: ["ccr"], 0x12286: ["ccr"]}


func room_hooks() -> Dictionary:
	return {RECORDS_CLEARED: _clear_more_records}


## How many records there are, and the address of each.
static func record_count(machine: NeoGeoMachine) -> int:
	return RECORD_COUNT + (MORE_RECORD_COUNT if machine.more_room else 0)


static func record(index: int) -> int:
	if index < RECORD_COUNT:
		return RECORDS + index * RECORD_SIZE
	return MORE_RECORDS + (index - RECORD_COUNT) * RECORD_SIZE


## $12202: leaves a free record in A0, taken and shown with a blank
## picture, or 0 when there is none.
func take_free_record() -> void:
	m.a0 = take_record(m)


static func take_record(machine: NeoGeoMachine) -> int:
	var ram := machine.ram
	for index in record_count(machine):
		var at := record(index) & 0xFFFF
		if ram.decode_u16(at + SHOWN) != 0:
			continue
		ram.encode_u16(at + SHOWN, 1)
		ram.encode_u16(at + DEPTH, 0)
		ram.encode_u16(at + X, FIRST_PLACE)
		ram.encode_u16(at + Y, FIRST_PLACE)
		ram.encode_u16(at + ZOOM_X, 0x100)
		ram.encode_u16(at + ZOOM_Y, 0x100)
		ram.encode_u16(at + PICTURE_HEAD, BLANK_PICTURE_HEAD)
		ram.encode_u16(at + PICTURE_HEAD + 2, BLANK_PICTURE_HEAD)
		ram.encode_u16(at + PICTURE_BODY, BLANK_PICTURE_BODY >> 16)
		ram.encode_u16(at + PICTURE_BODY + 2, BLANK_PICTURE_BODY & 0xFFFF)
		ram.encode_u16(at + PALETTE, 0)
		return record(index)
	return 0


## Gives a record back.
static func free_record(machine: NeoGeoMachine, sprite: int) -> void:
	machine.ram.encode_u16((sprite + SHOWN) & 0xFFFF, 0)


func _clear_more_records() -> void:
	for index in range(RECORD_COUNT, record_count(m)):
		free_record(m, record(index))


## $12256: depth in D0.
func depth_from_registers() -> void:
	set16(m.a0 + DEPTH, m.d0)


## $1225C: position in D0 and D2.
func place_from_registers() -> void:
	place(m, m.a0, m.d0, m.d2)


## $12266: zoom in D0 and D2.
func zoom_from_registers() -> void:
	zoom(m, m.a0, m.d0, m.d2)


## $12270: picture in A3.
func picture_from_registers() -> void:
	picture(m, m.a0, m.a3)


## $12286: D0 is 1 to show it and 0 to hide it.
func show_from_registers() -> void:
	set16(m.a0 + SHOWN, 2 - low16(m.d0))


static func place(machine: NeoGeoMachine, sprite: int, x: int, y: int) -> void:
	machine.ram.encode_u16((sprite + X) & 0xFFFF, x & 0xFFFF)
	machine.ram.encode_u16((sprite + Y) & 0xFFFF, y & 0xFFFF)


static func zoom(machine: NeoGeoMachine, sprite: int, across: int, down: int) -> void:
	machine.ram.encode_u16((sprite + ZOOM_X) & 0xFFFF, across & 0xFFFF)
	machine.ram.encode_u16((sprite + ZOOM_Y) & 0xFFFF, down & 0xFFFF)


## `address` is that of a picture in the program ROM.
static func picture(machine: NeoGeoMachine, sprite: int, address: int) -> void:
	machine.ram.encode_u16((sprite + PICTURE_HEAD) & 0xFFFF, machine.r16(address))
	machine.ram.encode_u16((sprite + PICTURE_HEAD + 2) & 0xFFFF, machine.r16(address + 2))
	var body := address + 4
	machine.ram.encode_u16((sprite + PICTURE_BODY) & 0xFFFF, (body >> 16) & 0xFFFF)
	machine.ram.encode_u16((sprite + PICTURE_BODY + 2) & 0xFFFF, body & 0xFFFF)


static func show(machine: NeoGeoMachine, sprite: int, shown: bool) -> void:
	machine.ram.encode_u16((sprite + SHOWN) & 0xFFFF, 1 if shown else 2)
