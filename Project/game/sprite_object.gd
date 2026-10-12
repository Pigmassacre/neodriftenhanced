extends GameRoutines
## Things on screen. The game keeps a record for each thing it draws and
## builds the hardware's sprites from all of them once a frame (the builder,
## $12036-$13330, is still translated). These are the routines the rest of
## the game uses to change such a record, in register A0.

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


func routines() -> Dictionary:
	return {
		0x12256: depth_from_registers,
		0x1225C: place_from_registers,
		0x12266: zoom_from_registers,
		0x12270: picture_from_registers,
		0x12286: show_from_registers,
	}


func scratch() -> Dictionary:
	return {0x12256: ["ccr"], 0x1225C: ["ccr"], 0x12266: ["ccr"], 0x12270: ["ccr"], 0x12286: ["ccr"]}


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
