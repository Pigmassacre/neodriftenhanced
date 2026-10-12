extends GameRoutines
## The game's random numbers.

## The current number. The recordings from MAME log it once a frame.
const SEED := 0x100430


func routines() -> Dictionary:
	return {
		0x10B8: advance_from_registers,
	}


func scratch() -> Dictionary:
	return {0x10B8: ["ccr"]}


## $10B8
func advance_from_registers() -> void:
	advance(m)


## Moves on to the next number and returns the one before.
static func advance(machine: NeoGeoMachine) -> int:
	var seed := machine.ram.decode_u16(SEED & 0xFFFF)
	var turned := ((seed << 2) | (seed >> 14)) & 0xFFFF
	machine.ram.encode_u16(SEED & 0xFFFF, (seed + turned + 0x3711) & 0xFFFF)
	return seed
