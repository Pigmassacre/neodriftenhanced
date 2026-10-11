class_name Z80
extends RefCounted
## Z80 interpreter for the sound CPU.
##
## Documented instruction set; the undocumented flag bits (3 and 5) are not
## modelled. Memory and ports are reached through the owner, which must
## provide mem_read(addr), mem_write(addr, value), port_in(port16) and
## port_out(port16, value).

const FLAG_C := 0x01
const FLAG_N := 0x02
const FLAG_PV := 0x04
const FLAG_H := 0x10
const FLAG_Z := 0x40
const FLAG_S := 0x80

# Cycles for the unprefixed opcodes 0x00-0x3F and 0xC0-0xFF (taken branches cost the same here).
const CYCLES_LOW: Array[int] = [
	4, 10, 7, 6, 4, 4, 7, 4, 4, 11, 7, 6, 4, 4, 7, 4,
	8, 10, 7, 6, 4, 4, 7, 4, 12, 11, 7, 6, 4, 4, 7, 4,
	7, 10, 16, 6, 4, 4, 7, 4, 7, 11, 16, 6, 4, 4, 7, 4,
	7, 10, 13, 6, 11, 11, 10, 4, 7, 11, 13, 6, 4, 4, 7, 4,
]
const CYCLES_HIGH: Array[int] = [
	5, 10, 10, 10, 10, 11, 7, 11, 5, 10, 10, 8, 10, 17, 7, 11,
	5, 10, 10, 11, 10, 11, 7, 11, 5, 4, 10, 11, 10, 4, 7, 11,
	5, 10, 10, 19, 10, 11, 7, 11, 5, 4, 10, 4, 10, 12, 7, 11,
	5, 10, 10, 4, 10, 11, 7, 11, 5, 6, 10, 4, 10, 4, 7, 11,
]

var a := 0
var f := 0
var b := 0
var c := 0
var d := 0
var e := 0
var h := 0
var l := 0
var a_alt := 0
var f_alt := 0
var bc_alt := 0
var de_alt := 0
var hl_alt := 0
var ix := 0
var iy := 0
var sp := 0
var pc := 0
var iff1 := false
var iff2 := false
var halted := false
var cycles := 0
var bad_opcode := -1

var bus: Object
var _szp := PackedInt32Array()
# 0: HL, 1: IX, 2: IY for the instruction being executed
var _index := 0


func _init(owner: Object) -> void:
	bus = owner
	_szp.resize(256)
	for value in 256:
		var parity := 0
		for bit in 8:
			parity ^= (value >> bit) & 1
		_szp[value] = (value & FLAG_S) | (FLAG_Z if value == 0 else 0) | (0 if parity else FLAG_PV)


func reset() -> void:
	pc = 0
	sp = 0xFFFF
	iff1 = false
	iff2 = false
	halted = false


func nmi() -> void:
	halted = false
	iff2 = iff1
	iff1 = false
	_push(pc)
	pc = 0x66
	cycles += 11


## Maskable interrupt, mode 1. Returns false when interrupts are disabled.
func irq() -> bool:
	if not iff1:
		return false
	halted = false
	iff1 = false
	iff2 = false
	_push(pc)
	pc = 0x38
	cycles += 13
	return true


# --- helpers -----------------------------------------------------------------

func _fetch() -> int:
	var value: int = bus.mem_read(pc)
	pc = (pc + 1) & 0xFFFF
	return value


func _fetch16() -> int:
	var low := _fetch()
	return low | (_fetch() << 8)


func _read16(addr: int) -> int:
	return bus.mem_read(addr) | (bus.mem_read((addr + 1) & 0xFFFF) << 8)


func _write16(addr: int, value: int) -> void:
	bus.mem_write(addr, value & 0xFF)
	bus.mem_write((addr + 1) & 0xFFFF, value >> 8)


func _push(value: int) -> void:
	sp = (sp - 2) & 0xFFFF
	_write16(sp, value)


func _pop() -> int:
	var value := _read16(sp)
	sp = (sp + 2) & 0xFFFF
	return value


func _hl() -> int:
	if _index == 1:
		return ix
	if _index == 2:
		return iy
	return (h << 8) | l


func _set_hl(value: int) -> void:
	if _index == 1:
		ix = value
	elif _index == 2:
		iy = value
	else:
		h = value >> 8
		l = value & 0xFF


## Address of the (HL) operand; reads the displacement for (IX+d) / (IY+d).
func _hl_address() -> int:
	if _index == 0:
		return (h << 8) | l
	var disp := _fetch()
	cycles += 8
	return ((ix if _index == 1 else iy) + ((disp ^ 0x80) - 0x80)) & 0xFFFF


func _reg(index: int) -> int:
	match index:
		0: return b
		1: return c
		2: return d
		3: return e
		4: return h
		5: return l
		7: return a
	return 0


func _set_reg(index: int, value: int) -> void:
	match index:
		0: b = value
		1: c = value
		2: d = value
		3: e = value
		4: h = value
		5: l = value
		7: a = value


func _pair(index: int) -> int:
	match index:
		0: return (b << 8) | c
		1: return (d << 8) | e
		2: return _hl()
	return sp


func _set_pair(index: int, value: int) -> void:
	match index:
		0:
			b = value >> 8
			c = value & 0xFF
		1:
			d = value >> 8
			e = value & 0xFF
		2:
			_set_hl(value)
		_:
			sp = value


func _condition(index: int) -> bool:
	match index:
		0: return (f & FLAG_Z) == 0
		1: return (f & FLAG_Z) != 0
		2: return (f & FLAG_C) == 0
		3: return (f & FLAG_C) != 0
		4: return (f & FLAG_PV) == 0
		5: return (f & FLAG_PV) != 0
		6: return (f & FLAG_S) == 0
	return (f & FLAG_S) != 0


func _add(value: int, carry: int) -> void:
	var result := a + value + carry
	f = (result & FLAG_S) | (FLAG_Z if (result & 0xFF) == 0 else 0) | ((result >> 8) & 1) \
			| ((a ^ value ^ result) & FLAG_H) | (((a ^ result) & (value ^ result) & 0x80) >> 5)
	a = result & 0xFF


func _sub(value: int, carry: int, store: bool) -> void:
	var result := a - value - carry
	f = (result & FLAG_S) | (FLAG_Z if (result & 0xFF) == 0 else 0) | ((result >> 8) & 1) | FLAG_N \
			| ((a ^ value ^ result) & FLAG_H) | (((a ^ value) & (a ^ result) & 0x80) >> 5)
	if store:
		a = result & 0xFF


func _alu(operation: int, value: int) -> void:
	match operation:
		0: _add(value, 0)
		1: _add(value, f & FLAG_C)
		2: _sub(value, 0, true)
		3: _sub(value, f & FLAG_C, true)
		4:
			a &= value
			f = _szp[a] | FLAG_H
		5:
			a ^= value
			f = _szp[a]
		6:
			a |= value
			f = _szp[a]
		7: _sub(value, 0, false)


func _inc8(value: int) -> int:
	value = (value + 1) & 0xFF
	f = (f & FLAG_C) | (value & FLAG_S) | (FLAG_Z if value == 0 else 0) \
			| (FLAG_H if (value & 0x0F) == 0 else 0) | (FLAG_PV if value == 0x80 else 0)
	return value


func _dec8(value: int) -> int:
	value = (value - 1) & 0xFF
	f = (f & FLAG_C) | FLAG_N | (value & FLAG_S) | (FLAG_Z if value == 0 else 0) \
			| (FLAG_H if (value & 0x0F) == 0x0F else 0) | (FLAG_PV if value == 0x7F else 0)
	return value


func _rotate(kind: int, value: int) -> int:
	var carry := 0
	match kind:
		0:
			carry = value >> 7
			value = ((value << 1) | carry) & 0xFF
		1:
			carry = value & 1
			value = (value >> 1) | (carry << 7)
		2:
			carry = value >> 7
			value = ((value << 1) | (f & FLAG_C)) & 0xFF
		3:
			carry = value & 1
			value = (value >> 1) | ((f & FLAG_C) << 7)
		4:
			carry = value >> 7
			value = (value << 1) & 0xFF
		5:
			carry = value & 1
			value = (value >> 1) | (value & 0x80)
		6:
			carry = value >> 7
			value = ((value << 1) | 1) & 0xFF
		7:
			carry = value & 1
			value >>= 1
	f = _szp[value] | carry
	return value


# --- execution ---------------------------------------------------------------

func step() -> void:
	if halted:
		cycles += 4
		return
	_index = 0
	var op := _fetch()
	while op == 0xDD or op == 0xFD:
		_index = 1 if op == 0xDD else 2
		cycles += 4
		op = _fetch()
	if op == 0xCB:
		_step_cb()
	elif op == 0xED:
		_index = 0
		_step_ed()
	elif op < 0x40:
		cycles += CYCLES_LOW[op]
		_step_low(op)
	elif op < 0x80:
		_step_load(op)
	elif op < 0xC0:
		var source := op & 7
		if source == 6:
			cycles += 7
			_alu((op >> 3) & 7, bus.mem_read(_hl_address()))
		else:
			cycles += 4
			_alu((op >> 3) & 7, _reg_indexed(source))
	else:
		cycles += CYCLES_HIGH[op - 0xC0]
		_step_high(op)


## Register operand; with an index prefix H and L mean the index register halves.
func _reg_indexed(index: int) -> int:
	if _index != 0 and (index == 4 or index == 5):
		var value := ix if _index == 1 else iy
		return (value >> 8) if index == 4 else (value & 0xFF)
	return _reg(index)


func _set_reg_indexed(index: int, value: int) -> void:
	if _index != 0 and (index == 4 or index == 5):
		var current := ix if _index == 1 else iy
		current = ((value << 8) | (current & 0xFF)) if index == 4 else ((current & 0xFF00) | value)
		if _index == 1:
			ix = current
		else:
			iy = current
	else:
		_set_reg(index, value)


func _step_load(op: int) -> void:
	var dest := (op >> 3) & 7
	var source := op & 7
	if op == 0x76:
		halted = true
		cycles += 4
	elif source == 6:
		cycles += 7
		_set_reg(dest, bus.mem_read(_hl_address()))
	elif dest == 6:
		cycles += 7
		bus.mem_write(_hl_address(), _reg(source))
	else:
		cycles += 4
		_set_reg_indexed(dest, _reg_indexed(source))


func _step_low(op: int) -> void:
	var y := (op >> 3) & 7
	match op & 7:
		0:
			match y:
				0:
					pass
				1:
					var temp := a
					a = a_alt
					a_alt = temp
					temp = f
					f = f_alt
					f_alt = temp
				2:
					var offset := _fetch()
					b = (b - 1) & 0xFF
					if b != 0:
						pc = (pc + ((offset ^ 0x80) - 0x80)) & 0xFFFF
				3:
					var offset := _fetch()
					pc = (pc + ((offset ^ 0x80) - 0x80)) & 0xFFFF
				_:
					var offset := _fetch()
					if _condition(y - 4):
						pc = (pc + ((offset ^ 0x80) - 0x80)) & 0xFFFF
		1:
			if (op & 8) == 0:
				_set_pair(y >> 1, _fetch16())
			else:
				var left := _hl()
				var right := _pair(y >> 1)
				var result := left + right
				f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | ((result >> 16) & 1) \
						| (((left ^ right ^ result) >> 8) & FLAG_H)
				_set_hl(result & 0xFFFF)
		2:
			match y:
				0: bus.mem_write((b << 8) | c, a)
				1: a = bus.mem_read((b << 8) | c)
				2: bus.mem_write((d << 8) | e, a)
				3: a = bus.mem_read((d << 8) | e)
				4: _write16(_fetch16(), _hl())
				5: _set_hl(_read16(_fetch16()))
				6: bus.mem_write(_fetch16(), a)
				7: a = bus.mem_read(_fetch16())
		3:
			var index := y >> 1
			_set_pair(index, (_pair(index) + (1 if (op & 8) == 0 else -1)) & 0xFFFF)
		4:
			if y == 6:
				var addr := _hl_address()
				bus.mem_write(addr, _inc8(bus.mem_read(addr)))
			else:
				_set_reg_indexed(y, _inc8(_reg_indexed(y)))
		5:
			if y == 6:
				var addr := _hl_address()
				bus.mem_write(addr, _dec8(bus.mem_read(addr)))
			else:
				_set_reg_indexed(y, _dec8(_reg_indexed(y)))
		6:
			if y == 6:
				var addr := _hl_address()
				bus.mem_write(addr, _fetch())
			else:
				_set_reg_indexed(y, _fetch())
		7:
			match y:
				0:
					var carry := a >> 7
					a = ((a << 1) | carry) & 0xFF
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | carry
				1:
					var carry := a & 1
					a = (a >> 1) | (carry << 7)
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | carry
				2:
					var carry := a >> 7
					a = ((a << 1) | (f & FLAG_C)) & 0xFF
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | carry
				3:
					var carry := a & 1
					a = (a >> 1) | ((f & FLAG_C) << 7)
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | carry
				4:
					_daa()
				5:
					a ^= 0xFF
					f |= FLAG_H | FLAG_N
				6:
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | FLAG_C
				7:
					f = (f & (FLAG_S | FLAG_Z | FLAG_PV)) | (FLAG_H if (f & FLAG_C) else 0) \
							| ((f & FLAG_C) ^ FLAG_C)


func _daa() -> void:
	var adjust := 0
	var carry := f & FLAG_C
	if (f & FLAG_H) or (a & 0x0F) > 9:
		adjust = 0x06
	if carry or a > 0x99:
		adjust |= 0x60
		carry = FLAG_C
	var before := a
	if f & FLAG_N:
		a = (a - adjust) & 0xFF
	else:
		a = (a + adjust) & 0xFF
	f = _szp[a] | carry | (f & FLAG_N) | ((before ^ a) & FLAG_H)


func _step_high(op: int) -> void:
	var y := (op >> 3) & 7
	match op & 7:
		0:
			if _condition(y):
				pc = _pop()
		1:
			if (op & 8) == 0:
				var value := _pop()
				if y == 6:
					a = value >> 8
					f = value & 0xFF
				else:
					_set_pair(y >> 1, value)
			else:
				match y:
					1:
						pc = _pop()
					3:
						var temp := (b << 8) | c
						_set_pair(0, bc_alt)
						bc_alt = temp
						temp = (d << 8) | e
						_set_pair(1, de_alt)
						de_alt = temp
						temp = (h << 8) | l
						h = hl_alt >> 8
						l = hl_alt & 0xFF
						hl_alt = temp
					5:
						pc = _hl()
					7:
						sp = _hl()
		2:
			var target := _fetch16()
			if _condition(y):
				pc = target
		3:
			match y:
				0:
					pc = _fetch16()
				2:
					bus.port_out((a << 8) | _fetch(), a)
				3:
					a = bus.port_in((a << 8) | _fetch())
				4:
					var value := _read16(sp)
					_write16(sp, _hl())
					_set_hl(value)
				5:
					var temp := (d << 8) | e
					d = h
					e = l
					h = temp >> 8
					l = temp & 0xFF
				6:
					iff1 = false
					iff2 = false
				7:
					iff1 = true
					iff2 = true
		4:
			var target := _fetch16()
			if _condition(y):
				_push(pc)
				pc = target
		5:
			if (op & 8) == 0:
				_push(((a << 8) | f) if y == 6 else _pair(y >> 1))
			else:
				var target := _fetch16()
				_push(pc)
				pc = target
		6:
			_alu(y, _fetch())
		7:
			_push(pc)
			pc = y * 8


func _step_cb() -> void:
	var addr := 0
	if _index != 0:
		# DD CB d op: the displacement comes before the opcode
		var disp := _fetch()
		addr = ((ix if _index == 1 else iy) + ((disp ^ 0x80) - 0x80)) & 0xFFFF
	var op := _fetch()
	var target := op & 7
	var y := (op >> 3) & 7
	var in_memory := target == 6 or _index != 0
	if in_memory and _index == 0:
		addr = (h << 8) | l
	var value: int = bus.mem_read(addr) if in_memory else _reg(target)
	cycles += 15 if in_memory else 8
	match op >> 6:
		0:
			value = _rotate(y, value)
		1:
			f = (f & FLAG_C) | FLAG_H | (FLAG_Z | FLAG_PV if (value & (1 << y)) == 0 else 0) \
					| (FLAG_S if (y == 7 and (value & 0x80) != 0) else 0)
			return
		2:
			value &= ~(1 << y) & 0xFF
		3:
			value |= 1 << y
	if in_memory:
		bus.mem_write(addr, value)
	else:
		_set_reg(target, value)


func _step_ed() -> void:
	var op := _fetch()
	cycles += 12
	var y := (op >> 3) & 7
	if op >= 0x40 and op < 0x80:
		match op & 7:
			0:
				var value: int = bus.port_in((b << 8) | c)
				f = (f & FLAG_C) | _szp[value]
				if y != 6:
					_set_reg(y, value)
			1:
				bus.port_out((b << 8) | c, 0 if y == 6 else _reg(y))
			2:
				var left := (h << 8) | l
				var right := _pair(y >> 1) if (y >> 1) != 2 else left
				var carry := f & FLAG_C
				if (op & 8) == 0:
					var result := left - right - carry
					f = ((result >> 8) & FLAG_S) | (FLAG_Z if (result & 0xFFFF) == 0 else 0) | FLAG_N \
							| ((result >> 16) & 1) | (((left ^ right ^ result) >> 8) & FLAG_H) \
							| (((left ^ right) & (left ^ result) & 0x8000) >> 13)
					h = (result >> 8) & 0xFF
					l = result & 0xFF
				else:
					var result := left + right + carry
					f = ((result >> 8) & FLAG_S) | (FLAG_Z if (result & 0xFFFF) == 0 else 0) \
							| ((result >> 16) & 1) | (((left ^ right ^ result) >> 8) & FLAG_H) \
							| (((left ^ result) & (right ^ result) & 0x8000) >> 13)
					h = (result >> 8) & 0xFF
					l = result & 0xFF
			3:
				var addr := _fetch16()
				var index := y >> 1
				if (op & 8) == 0:
					_write16(addr, ((h << 8) | l) if index == 2 else _pair(index))
				elif index == 2:
					var value := _read16(addr)
					h = value >> 8
					l = value & 0xFF
				else:
					_set_pair(index, _read16(addr))
			4:
				var value := a
				a = 0
				_sub(value, 0, true)
			5:
				pc = _pop()
				iff1 = iff2
			6:
				pass  # interrupt mode: only mode 1 is used
			7:
				match y:
					2, 3:
						a = 0
						f = (f & FLAG_C) | _szp[a] | (FLAG_PV if iff2 else 0)
					4:
						var addr := (h << 8) | l
						var value: int = bus.mem_read(addr)
						bus.mem_write(addr, ((value >> 4) | (a << 4)) & 0xFF)
						a = (a & 0xF0) | (value & 0x0F)
						f = (f & FLAG_C) | _szp[a]
					5:
						var addr := (h << 8) | l
						var value: int = bus.mem_read(addr)
						bus.mem_write(addr, ((value << 4) | (a & 0x0F)) & 0xFF)
						a = (a & 0xF0) | (value >> 4)
						f = (f & FLAG_C) | _szp[a]
	elif op >= 0xA0 and op < 0xC0 and (op & 7) < 4:
		_block(op)
	else:
		bad_opcode = 0xED00 | op


func _block(op: int) -> void:
	var step := -1 if (op & 8) else 1
	var repeat := (op & 0x10) != 0
	var hl := (h << 8) | l
	var bc := (b << 8) | c
	match op & 3:
		0:
			var de := (d << 8) | e
			bus.mem_write(de, bus.mem_read(hl))
			de = (de + step) & 0xFFFF
			d = de >> 8
			e = de & 0xFF
			bc = (bc - 1) & 0xFFFF
			f = (f & (FLAG_S | FLAG_Z | FLAG_C)) | (FLAG_PV if bc != 0 else 0)
			if repeat and bc != 0:
				pc = (pc - 2) & 0xFFFF
				cycles += 5
		1:
			var carry := f & FLAG_C
			_sub(bus.mem_read(hl), 0, false)
			bc = (bc - 1) & 0xFFFF
			f = (f & ~(FLAG_C | FLAG_PV)) | carry | (FLAG_PV if bc != 0 else 0)
			if repeat and bc != 0 and (f & FLAG_Z) == 0:
				pc = (pc - 2) & 0xFFFF
				cycles += 5
		2:
			bus.mem_write(hl, bus.port_in(bc))
			b = (b - 1) & 0xFF
			bc = (b << 8) | c
			f = (f & FLAG_C) | FLAG_N | (FLAG_Z if b == 0 else 0)
			if repeat and b != 0:
				pc = (pc - 2) & 0xFFFF
		3:
			b = (b - 1) & 0xFF
			bc = (b << 8) | c
			bus.port_out(bc, bus.mem_read(hl))
			f = (f & FLAG_C) | FLAG_N | (FLAG_Z if b == 0 else 0)
			if repeat and b != 0:
				pc = (pc - 2) & 0xFFFF
	hl = (hl + step) & 0xFFFF
	h = hl >> 8
	l = hl & 0xFF
	b = bc >> 8
	c = bc & 0xFF
