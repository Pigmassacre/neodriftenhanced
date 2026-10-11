"""68000 instruction decoder for the static recompiler.

decode(fetch16, addr) returns an Instr describing one instruction, or raises
Illegal. Operands are small tuples:

  ("d", n) ("a", n)                 registers
  ("ind", n) ("pi", n) ("pd", n)    (An) (An)+ -(An)
  ("disp", n, d16)                  (d16,An)
  ("idx", n, d8, xkind, xn, xlong)  (d8,An,Xn)  xkind is "d" or "a"
  ("abs", addr)                     absolute
  ("pcidx", base, d8, xkind, xn, xlong)
  ("imm", value)
"""


class Illegal(Exception):
    pass


CONDITIONS = ["t", "f", "hi", "ls", "cc", "cs", "ne", "eq", "vc", "vs", "pl", "mi", "ge", "lt", "gt", "le"]
COND_USES = {
    "t": "", "f": "", "hi": "cz", "ls": "cz", "cc": "c", "cs": "c", "ne": "z", "eq": "z",
    "vc": "v", "vs": "v", "pl": "n", "mi": "n", "ge": "nv", "lt": "nv", "gt": "nzv", "le": "nzv",
}


class Instr:
    __slots__ = ("addr", "length", "name", "size", "src", "dst", "aux", "flow", "target")

    def __init__(self, addr, name, size=0, src=None, dst=None, aux=None, flow="next", target=None):
        self.addr = addr
        self.length = 0
        self.name = name
        self.size = size
        self.src = src
        self.dst = dst
        self.aux = aux
        self.flow = flow        # next, branch, cbranch, call, jump, return, stop
        self.target = target    # static target address, or None when computed

    def __repr__(self):
        return "%06X %s.%d %r %r %r" % (self.addr, self.name, self.size, self.src, self.dst, self.aux)


def _s8(v):
    return (v ^ 0x80) - 0x80


def _s16(v):
    return (v ^ 0x8000) - 0x8000


class _Reader:
    def __init__(self, fetch16, addr):
        self.fetch16 = fetch16
        self.start = addr
        self.pc = addr

    def word(self):
        v = self.fetch16(self.pc)
        self.pc += 2
        return v

    def long(self):
        hi = self.word()
        return (hi << 16) | self.word()

    def ea(self, mode, reg, size):
        if mode == 0:
            return ("d", reg)
        if mode == 1:
            return ("a", reg)
        if mode == 2:
            return ("ind", reg)
        if mode == 3:
            return ("pi", reg)
        if mode == 4:
            return ("pd", reg)
        if mode == 5:
            return ("disp", reg, _s16(self.word()))
        if mode == 6:
            ext = self.word()
            if ext & 0x0700:
                raise Illegal("68020 index")
            return ("idx", reg, _s8(ext & 0xff), "a" if ext & 0x8000 else "d", (ext >> 12) & 7, bool(ext & 0x800))
        if reg == 0:
            return ("abs", _s16(self.word()) & 0xffffffff)
        if reg == 1:
            return ("abs", self.long())
        if reg == 2:
            base = self.pc
            return ("abs", (base + _s16(self.word())) & 0xffffffff)
        if reg == 3:
            base = self.pc
            ext = self.word()
            if ext & 0x0700:
                raise Illegal("68020 index")
            return ("pcidx", base, _s8(ext & 0xff), "a" if ext & 0x8000 else "d", (ext >> 12) & 7, bool(ext & 0x800))
        if reg == 4:
            if size == 1:
                return ("imm", self.word() & 0xff)
            if size == 2:
                return ("imm", self.word())
            if size == 4:
                return ("imm", self.long())
        raise Illegal("ea")


def _is_mem_alterable(ea):
    return ea[0] in ("ind", "pi", "pd", "disp", "idx", "abs_alterable") or ea[0] == "abs"


def _check_data_alterable(ea, mode, reg):
    if mode == 1 or (mode == 7 and reg > 1):
        raise Illegal("not data alterable")


SIZES = {0: 1, 1: 2, 2: 4}


def decode(fetch16, addr):
    r = _Reader(fetch16, addr)
    op = r.word()
    ins = _decode(r, op, addr)
    ins.length = r.pc - addr
    return ins


def _decode(r, op, addr):
    top = op >> 12
    mode, reg = (op >> 3) & 7, op & 7
    reg9 = (op >> 9) & 7
    szbits = (op >> 6) & 3

    if top == 0:
        if op & 0x0100:
            if mode == 1:
                raise Illegal("movep")
            name = ("btst", "bchg", "bclr", "bset")[szbits]
            dst = r.ea(mode, reg, 1)
            if name != "btst" and mode == 7 and reg > 1:
                raise Illegal(name)
            return Instr(addr, name, 4 if mode == 0 else 1, ("d", reg9), dst)
        kind = reg9
        if kind == 4:
            name = ("btst", "bchg", "bclr", "bset")[szbits]
            bit = r.word() & 0xff
            dst = r.ea(mode, reg, 1)
            if mode == 1 or (mode == 7 and reg == 4) or (name != "btst" and mode == 7 and reg > 1):
                raise Illegal(name)
            return Instr(addr, name, 4 if mode == 0 else 1, ("imm", bit), dst)
        if kind == 7 or szbits == 3:
            raise Illegal("group 0")
        name = ("ori", "andi", "subi", "addi", None, "eori", "cmpi")[kind]
        size = SIZES[szbits]
        if mode == 7 and reg == 4:
            if name not in ("ori", "andi", "eori") or size == 4:
                raise Illegal(name)
            imm = r.word()
            if size == 1:
                return Instr(addr, name + "_ccr", 1, ("imm", imm & 0xff))
            return Instr(addr, name + "_sr", 2, ("imm", imm), flow="sr")
        src = ("imm", r.word() & 0xff) if size == 1 else ("imm", r.word()) if size == 2 else ("imm", r.long())
        dst = r.ea(mode, reg, size)
        if mode == 1 or (mode == 7 and reg > 1 and not (name == "cmpi" and False)):
            raise Illegal(name)
        return Instr(addr, name, size, src, dst)

    if top in (1, 2, 3):
        size = {1: 1, 3: 2, 2: 4}[top]
        src = r.ea(mode, reg, size)
        dmode = (op >> 6) & 7
        if mode == 1 and size == 1:
            raise Illegal("move.b An")
        if dmode == 1:
            if size == 1:
                raise Illegal("movea.b")
            return Instr(addr, "movea", size, src, ("a", reg9))
        if dmode == 7 and reg9 > 1:
            raise Illegal("move dst")
        dst = r.ea(dmode, reg9, size)
        return Instr(addr, "move", size, src, dst)

    if top == 4:
        if op == 0x4e71:
            return Instr(addr, "nop")
        if op == 0x4e70:
            return Instr(addr, "reset")
        if op == 0x4e72:
            return Instr(addr, "stop", 2, ("imm", r.word()), flow="stop")
        if op == 0x4e73:
            return Instr(addr, "rte", flow="return")
        if op == 0x4e75:
            return Instr(addr, "rts", flow="return")
        if op == 0x4e77:
            return Instr(addr, "rtr", flow="return")
        if op == 0x4e76:
            raise Illegal("trapv")
        if (op & 0xfff0) == 0x4e40:
            return Instr(addr, "trap", aux=op & 15, flow="return")
        if (op & 0xfff8) == 0x4e50:
            return Instr(addr, "link", 0, ("imm", _s16(r.word())), ("a", reg))
        if (op & 0xfff8) == 0x4e58:
            return Instr(addr, "unlk", 0, None, ("a", reg))
        if (op & 0xfff8) == 0x4e60:
            return Instr(addr, "move_to_usp", 4, ("a", reg))
        if (op & 0xfff8) == 0x4e68:
            return Instr(addr, "move_from_usp", 4, None, ("a", reg))
        if (op & 0xffc0) in (0x4e80, 0x4ec0):
            if mode in (0, 1, 3, 4) or (mode == 7 and reg == 4):
                raise Illegal("jmp ea")
            dst = r.ea(mode, reg, 4)
            call = (op & 0xffc0) == 0x4e80
            target = dst[1] & 0xffffff if dst[0] == "abs" else None
            return Instr(addr, "jsr" if call else "jmp", 4, None, dst, flow="call" if call else "jump", target=target)
        if (op & 0xf1c0) == 0x41c0:
            if mode in (0, 1, 3, 4) or (mode == 7 and reg == 4):
                raise Illegal("lea ea")
            return Instr(addr, "lea", 4, r.ea(mode, reg, 4), ("a", reg9))
        if (op & 0xf1c0) == 0x4180:
            raise Illegal("chk")
        if (op & 0xffc0) == 0x40c0:
            _check_data_alterable(None, mode, reg)
            return Instr(addr, "move_from_sr", 2, None, r.ea(mode, reg, 2))
        if (op & 0xffc0) == 0x44c0:
            if mode == 1:
                raise Illegal("move ccr")
            return Instr(addr, "move_to_ccr", 2, r.ea(mode, reg, 2))
        if (op & 0xffc0) == 0x46c0:
            if mode == 1:
                raise Illegal("move sr")
            return Instr(addr, "move_to_sr", 2, r.ea(mode, reg, 2), flow="sr")
        sub = (op >> 8) & 15
        if sub in (0, 2, 4, 6) and szbits != 3:
            _check_data_alterable(None, mode, reg)
            name = {0: "negx", 2: "clr", 4: "neg", 6: "not"}[sub]
            return Instr(addr, name, SIZES[szbits], None, r.ea(mode, reg, SIZES[szbits]))
        if sub == 8:
            if szbits == 0:
                _check_data_alterable(None, mode, reg)
                return Instr(addr, "nbcd", 1, None, r.ea(mode, reg, 1))
            if szbits == 1:
                if mode == 0:
                    return Instr(addr, "swap", 4, None, ("d", reg))
                if mode in (1, 3, 4) or (mode == 7 and reg == 4):
                    raise Illegal("pea")
                return Instr(addr, "pea", 4, r.ea(mode, reg, 4))
            size = 2 if szbits == 2 else 4
            if mode == 0:
                return Instr(addr, "ext", size, None, ("d", reg))
            mask = r.word()
            if mode in (1, 3) or (mode == 7 and reg > 1):
                raise Illegal("movem")
            return Instr(addr, "movem_to_mem", size, None, r.ea(mode, reg, size), aux=mask)
        if sub == 10:
            if szbits == 3:
                if op == 0x4afc:
                    raise Illegal("illegal")
                _check_data_alterable(None, mode, reg)
                return Instr(addr, "tas", 1, None, r.ea(mode, reg, 1))
            if mode == 1 and szbits == 0:
                raise Illegal("tst.b An")
            return Instr(addr, "tst", SIZES[szbits], r.ea(mode, reg, SIZES[szbits]))
        if sub == 12 and szbits >= 2:
            size = 2 if szbits == 2 else 4
            mask = r.word()
            if mode in (0, 1, 4) or (mode == 7 and reg == 4):
                raise Illegal("movem")
            return Instr(addr, "movem_to_reg", size, r.ea(mode, reg, size), aux=mask)
        raise Illegal("group 4")

    if top == 5:
        if szbits == 3:
            cond = CONDITIONS[(op >> 8) & 15]
            if mode == 1:
                base = r.pc
                target = (base + _s16(r.word())) & 0xffffff
                return Instr(addr, "dbcc", 2, None, ("d", reg), aux=cond, flow="cbranch", target=target)
            _check_data_alterable(None, mode, reg)
            return Instr(addr, "scc", 1, None, r.ea(mode, reg, 1), aux=cond)
        size = SIZES[szbits]
        if mode == 1 and size == 1:
            raise Illegal("addq.b An")
        if mode == 7 and reg > 1:
            raise Illegal("addq ea")
        data = reg9 or 8
        return Instr(addr, "subq" if op & 0x100 else "addq", size, ("imm", data), r.ea(mode, reg, size))

    if top == 6:
        cond = (op >> 8) & 15
        base = r.pc
        disp = _s8(op & 0xff)
        if disp == 0:
            disp = _s16(r.word())
        elif disp == -1:
            raise Illegal("bcc.l")
        target = (base + disp) & 0xffffff
        if target & 1:
            raise Illegal("odd branch")
        if cond == 0:
            return Instr(addr, "bra", flow="branch", target=target)
        if cond == 1:
            return Instr(addr, "bsr", flow="call", target=target)
        return Instr(addr, "bcc", aux=CONDITIONS[cond], flow="cbranch", target=target)

    if top == 7:
        if op & 0x100:
            raise Illegal("moveq")
        return Instr(addr, "moveq", 4, ("imm", _s8(op & 0xff) & 0xffffffff), ("d", reg9))

    if top in (8, 0xc):
        opmode = (op >> 6) & 7
        logic = "or" if top == 8 else "and"
        if opmode in (3, 7):
            if mode == 1:
                raise Illegal("mul/div An")
            name = {(8, 3): "divu", (8, 7): "divs", (0xc, 3): "mulu", (0xc, 7): "muls"}[(top, opmode)]
            return Instr(addr, name, 2, r.ea(mode, reg, 2), ("d", reg9))
        if opmode == 4 and mode in (0, 1):
            name = "sbcd" if top == 8 else "abcd"
            kind = "pd" if mode == 1 else "d"
            return Instr(addr, name, 1, (kind, reg), (kind, reg9))
        if top == 0xc and opmode == 5 and mode == 0:
            return Instr(addr, "exg", 4, ("d", reg9), ("d", reg))
        if top == 0xc and opmode == 5 and mode == 1:
            return Instr(addr, "exg", 4, ("a", reg9), ("a", reg))
        if top == 0xc and opmode == 6 and mode == 1:
            return Instr(addr, "exg", 4, ("d", reg9), ("a", reg))
        if opmode in (5, 6) and mode in (0, 1):
            raise Illegal(logic)
        size = SIZES[opmode & 3]
        if opmode < 3:
            if mode == 1:
                raise Illegal(logic + " An")
            return Instr(addr, logic, size, r.ea(mode, reg, size), ("d", reg9))
        if mode in (0, 1) or (mode == 7 and reg > 1):
            raise Illegal(logic)
        return Instr(addr, logic, size, ("d", reg9), r.ea(mode, reg, size))

    if top in (9, 0xd):
        opmode = (op >> 6) & 7
        base = "sub" if top == 9 else "add"
        if opmode in (3, 7):
            size = 2 if opmode == 3 else 4
            return Instr(addr, base + "a", size, r.ea(mode, reg, size), ("a", reg9))
        size = SIZES[opmode & 3]
        if opmode >= 4 and mode in (0, 1):
            kind = "pd" if mode == 1 else "d"
            return Instr(addr, base + "x", size, (kind, reg), (kind, reg9))
        if opmode < 3:
            if mode == 1 and size == 1:
                raise Illegal(base + ".b An")
            return Instr(addr, base, size, r.ea(mode, reg, size), ("d", reg9))
        if mode == 7 and reg > 1:
            raise Illegal(base)
        return Instr(addr, base, size, ("d", reg9), r.ea(mode, reg, size))

    if top == 0xb:
        opmode = (op >> 6) & 7
        if opmode in (3, 7):
            size = 2 if opmode == 3 else 4
            return Instr(addr, "cmpa", size, r.ea(mode, reg, size), ("a", reg9))
        size = SIZES[opmode & 3]
        if opmode < 3:
            if mode == 1 and size == 1:
                raise Illegal("cmp.b An")
            return Instr(addr, "cmp", size, r.ea(mode, reg, size), ("d", reg9))
        if mode == 1:
            return Instr(addr, "cmp", size, ("pi", reg), ("pi", reg9))
        if mode == 7 and reg > 1:
            raise Illegal("eor")
        return Instr(addr, "eor", size, ("d", reg9), r.ea(mode, reg, size))

    if top == 0xe:
        if szbits == 3:
            if op & 0x0800:
                raise Illegal("bitfield")
            if mode in (0, 1) or (mode == 7 and reg > 1):
                raise Illegal("shift ea")
            name = ("as", "ls", "rox", "ro")[(op >> 9) & 3] + ("l" if op & 0x100 else "r")
            return Instr(addr, name, 2, ("imm", 1), r.ea(mode, reg, 2))
        name = ("as", "ls", "rox", "ro")[(op >> 3) & 3] + ("l" if op & 0x100 else "r")
        count = ("d", reg9) if op & 0x20 else ("imm", reg9 or 8)
        return Instr(addr, name, SIZES[szbits], count, ("d", reg))

    raise Illegal("line %X" % top)
