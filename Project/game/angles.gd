extends GameRoutines
## Directions. The game counts them clockwise on screen from "towards
## larger x", here with $100 to the full turn.

## The angle whose tangent is the index / 256, up to just under a quarter turn.
const ARC_TANGENTS := 0x101E0


func routines() -> Dictionary:
	return {
		0x1014C: towards_from_registers,
		0x1018E: func() -> void: m.d0 = with_low16(m.d0, _rise(m, low16(m.d2), low16(m.d3))),
	}


func scratch() -> Dictionary:
	return {0x1014C: ["ccr"], 0x1018E: ["d2", "d3", "ccr"]}


## $1014C: the direction of D2 across and D3 down, in D0.
func towards_from_registers() -> void:
	m.d0 = with_low16(m.d0, towards(m, low16(m.d2), low16(m.d3)))


## The direction in which a point `x` across and `y` down lies, 0 to $100.
static func towards(machine: NeoGeoMachine, x: int, y: int) -> int:
	if y >= 0:
		if x >= 0:
			return _rise(machine, x, y)
		return 0x80 - _rise(machine, -x, y)
	if x < 0:
		return 0x80 + _rise(machine, -x, -y)
	return 0x100 - _rise(machine, x, -y)


## The angle of a slope, 0 (flat) to $40 (straight up).
static func _rise(machine: NeoGeoMachine, across: int, up: int) -> int:
	across &= 0xFFFF
	if across == 0:
		return 0x40
	# the 68000 divides 32 bits by 16 here, both unsigned
	var scaled := (wrap16(up) << 8) & 0xFFFFFFFF
	var tangent := scaled / across
	if tangent > 0x7FFF:
		return 0x40
	if scaled % across >= across >> 1:
		tangent += 1
	if tangent >= 0x517C:
		return 0x40
	if tangent >= 0x1B27:
		return 0x3F
	if tangent >= 0x1047:
		return 0x3E
	if tangent >= 0xB9D:
		return 0x3D
	var angle := machine.rom[(ARC_TANGENTS + tangent) ^ 1]
	return angle - 0x100 if angle >= 0x80 else angle
