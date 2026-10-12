class_name GameRoutines
extends RefCounted
## Base of the hand-written game code in this folder.
##
## The game is being decompiled routine by routine. Until all of it is, a
## hand-written routine runs among translated ones: it is entered where the
## original was (`routines()` maps addresses to methods), takes its
## arguments from the 68000 registers of the machine `m`, works on the same
## work RAM, and leaves in registers what its callers go on to use.
## `scratch()` names the registers a routine leaves different from the
## original because no caller reads them ("ccr" for the flags, "d0.high"
## for the upper half of D0 alone). A routine not yet decompiled is called
## with `m.call_routine(address)`, after setting the registers it reads.
##
## Hand-written code takes no processor time and is never interrupted, so it
## must not wait for an interrupt as the original does in places.
##
## Tools/verify_session.py --check-routines runs every call of every routine
## here twice, original and hand-written, and compares the outcomes.

var m: NeoGeoMachine


func _init(machine: NeoGeoMachine) -> void:
	m = machine


## Address of each routine replaced, and the method that replaces it.
func routines() -> Dictionary:
	return {}


## Per address, the registers the method leaves different from the original.
func scratch() -> Dictionary:
	return {}


## Per address, ways to alter the state a routine is entered with (callables
## that change work RAM or registers). The check also compares the routine
## with its original from such states now and then, which covers branches no
## recorded session takes. The game itself never runs them.
func variations() -> Dictionary:
	return {}


# Work RAM by bus address ($100000-$10FFFF), big-endian as the game sees it.

func u8(address: int) -> int:
	return m.ram[(address & 0xFFFF) ^ 1]


func s8(address: int) -> int:
	var value := m.ram[(address & 0xFFFF) ^ 1]
	return value - 0x100 if value >= 0x80 else value


func u16(address: int) -> int:
	return m.ram.decode_u16(address & 0xFFFF)


func s16(address: int) -> int:
	return m.ram.decode_s16(address & 0xFFFF)


func u32(address: int) -> int:
	return (m.ram.decode_u16(address & 0xFFFF) << 16) | m.ram.decode_u16((address + 2) & 0xFFFF)


func s32(address: int) -> int:
	return (m.ram.decode_s16(address & 0xFFFF) << 16) | m.ram.decode_u16((address + 2) & 0xFFFF)


func set8(address: int, value: int) -> void:
	m.ram[(address & 0xFFFF) ^ 1] = value & 0xFF


func set16(address: int, value: int) -> void:
	m.ram.encode_s16(address & 0xFFFF, wrap16(value))


func set32(address: int, value: int) -> void:
	m.ram.encode_u16(address & 0xFFFF, (value >> 16) & 0xFFFF)
	m.ram.encode_u16((address + 2) & 0xFFFF, value & 0xFFFF)


# The program ROM by bus address.

func rom_u8(address: int) -> int:
	return m.rom[address ^ 1]


func rom_s8(address: int) -> int:
	var value := m.rom[address ^ 1]
	return value - 0x100 if value >= 0x80 else value


func rom_u16(address: int) -> int:
	return m.rom.decode_u16(address)


func rom_s16(address: int) -> int:
	return m.rom.decode_s16(address)


func rom_u32(address: int) -> int:
	return (m.rom.decode_u16(address) << 16) | m.rom.decode_u16(address + 2)


# The game's arithmetic wraps at 16 or 32 bits.

static func wrap16(value: int) -> int:
	value &= 0xFFFF
	return value - 0x10000 if value >= 0x8000 else value


static func wrap32(value: int) -> int:
	value &= 0xFFFFFFFF
	return value - 0x100000000 if value >= 0x80000000 else value


## The low word of a register, signed.
static func low16(register: int) -> int:
	return wrap16(register)


## `register` with its low word replaced.
static func with_low16(register: int, value: int) -> int:
	return (register & 0xFFFF0000) | (value & 0xFFFF)


## The 68000's signed divide as the game uses it: the low word of the
## quotient, or of the dividend when the quotient does not fit in 16 bits
## (the processor then leaves the register alone).
static func divide16(dividend: int, divisor: int) -> int:
	if divisor == 0:
		return wrap16(dividend)
	var magnitude := absi(dividend) / absi(divisor)
	var quotient := magnitude if (dividend < 0) == (divisor < 0) else -magnitude
	if quotient > 32767 or quotient < -32768 or (absi(dividend) >> 16) >= absi(divisor):
		return wrap16(dividend)
	return quotient
