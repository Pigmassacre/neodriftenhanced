"""Static recompiler: 68000 program code to GDScript.

Every basic block becomes one GDScript function that returns the address of
the next block. The generated class extends the hand-written machine in
Project/machine/neogeo_machine.gd, which provides registers, flags, memory
access and the dispatcher.

Flags are kept as separate 0/1 integers (fn fz fv fc fx) and are only
computed where a later instruction can observe them.
"""
import m68k
from m68k import COND_USES, Illegal

MASK = {1: 0xff, 2: 0xffff, 4: 0xffffffff}
BITS = {1: 8, 2: 16, 4: 32}
ALL = frozenset("nzvcx")
NZVC = frozenset("nzvc")

COND_EXPR = {
    "t": "true", "f": "false",
    "hi": "(fc | fz) == 0", "ls": "(fc | fz) != 0",
    "cc": "fc == 0", "cs": "fc != 0", "ne": "fz == 0", "eq": "fz != 0",
    "vc": "fv == 0", "vs": "fv != 0", "pl": "fn == 0", "mi": "fn != 0",
    "ge": "fn == fv", "lt": "fn != fv",
    "gt": "(fz == 0 and fn == fv)", "le": "(fz != 0 or fn != fv)",
}

ARITH = {"add", "sub", "addi", "subi", "addq", "subq", "neg"}
COMPARE = {"cmp", "cmpi", "cmpa"}
LOGIC = {"move", "and", "or", "eor", "andi", "ori", "eori", "not", "tst", "clr", "ext", "swap",
         "moveq", "mulu", "muls", "tas"}
BITOPS = {"btst", "bchg", "bclr", "bset"}
SHIFTS = {"asl", "asr", "lsl", "lsr", "rol", "ror", "roxl", "roxr"}
HELPER_ALL = {"divu", "divs", "abcd", "sbcd", "nbcd"} | SHIFTS


def flag_effects(ins):
    """(uses, kills) of condition flags for liveness."""
    n = ins.name
    if n in ("addq", "subq") and ins.dst[0] == "a":
        return frozenset(), frozenset()
    if n in ARITH:
        return frozenset(), ALL
    if n in COMPARE:
        return frozenset(), NZVC
    if n in LOGIC:
        return frozenset(), NZVC
    if n in BITOPS:
        return frozenset(), frozenset("z")
    if n in ("addx", "subx", "negx"):
        return frozenset("xz"), frozenset("nvcx")
    if n in ("roxl", "roxr", "abcd", "sbcd", "nbcd"):
        return frozenset("xz"), frozenset()
    if n in SHIFTS or n in ("divu", "divs"):
        return frozenset(), frozenset()
    if n in ("bcc", "dbcc", "scc"):
        return frozenset(COND_USES[ins.aux]), frozenset()
    if n in ("move_to_ccr", "move_to_sr"):
        return frozenset(), ALL
    if n in ("move_from_sr", "andi_ccr", "ori_ccr", "eori_ccr", "andi_sr", "ori_sr", "eori_sr",
             "rts", "rte", "rtr", "trap", "stop"):
        return ALL, frozenset()
    if n in ("jsr", "jmp") and ins.target is None:
        return ALL, frozenset()
    return frozenset(), frozenset()


def _ext_words(ea, size):
    """Extension words an operand takes; None for an absolute address (one or two)."""
    if ea is None or ea[0] in ("d", "a", "ind", "pi", "pd"):
        return 0
    if ea[0] == "imm":
        return 2 if size == 4 else 1
    if ea[0] == "abs":
        return None
    return 1


def _ea_cycles(ea, long, abs_words):
    """Time to work out an operand's address and fetch it."""
    if ea is None:
        return 0
    kind = ea[0]
    if kind in ("d", "a"):
        return 0
    if kind == "abs":
        return (8 if long else 4) + 4 * abs_words
    base = {"ind": 4, "pi": 4, "pd": 6, "disp": 8, "idx": 10, "pcidx": 10, "imm": 4}[kind]
    return base + (4 if long else 0)


# jmp, jsr, lea, pea and movem have their own times per addressing mode;
# an absolute address adds 4 per extension word to the "abs" entry.
_CONTROL = {
    "jmp": {"ind": 8, "disp": 10, "idx": 14, "pcidx": 14, "abs": 6},
    "jsr": {"ind": 16, "disp": 18, "idx": 22, "pcidx": 22, "abs": 14},
    "lea": {"ind": 4, "disp": 8, "idx": 12, "pcidx": 12, "abs": 4},
    "pea": {"ind": 12, "disp": 16, "idx": 20, "pcidx": 20, "abs": 12},
    "movem_to_mem": {"ind": 8, "pd": 8, "disp": 12, "idx": 14, "abs": 8},
    "movem_to_reg": {"ind": 12, "pi": 12, "disp": 16, "idx": 18, "pcidx": 18, "abs": 12},
}
_FIXED = {"nop": 4, "moveq": 4, "ext": 4, "swap": 4, "exg": 6, "rts": 16, "rte": 20, "rtr": 20,
          "link": 16, "unlk": 12, "trap": 34, "stop": 4, "reset": 132, "bra": 10, "bsr": 18,
          "move_to_usp": 4, "move_from_usp": 4, "andi_ccr": 20, "ori_ccr": 20, "eori_ccr": 20,
          "andi_sr": 20, "ori_sr": 20, "eori_sr": 20}


def cycles(ins):
    """68000 cycles for an instruction, from the processor's timing tables.

    Where the time depends on what happens at run time this is the smallest
    case, and the generated code adds the rest: a branch taken (or a word
    branch not taken), dbcc ending, scc setting a register, shifts by a
    register count, and the data-dependent part of multiply and divide.
    """
    n = ins.name
    if n in _FIXED:
        return _FIXED[n]
    long = ins.size == 4
    if n == "bcc":
        return 8 if ins.length == 2 else 12
    if n == "dbcc":
        return 10
    # how many extension words belong to absolute addresses
    fixed = 1 if n in ("movem_to_mem", "movem_to_reg") else 0
    known = 0
    absolute = 0
    for ea in (ins.src, ins.dst):
        size = 2 if (n in BITOPS and ea is ins.src) else ins.size
        if ea is not None and ea[0] == "imm" and (n in SHIFTS or n in ("addq", "subq")):
            continue
        words = _ext_words(ea, size)
        if words is None:
            absolute += 1
        else:
            known += words
    abs_words = ins.length // 2 - 1 - fixed - known
    src_mem = ins.src is not None and ins.src[0] not in ("d", "a", "imm")
    dst_mem = ins.dst is not None and ins.dst[0] not in ("d", "a")
    if n in _CONTROL:
        ea = ins.dst if n in ("jmp", "jsr", "movem_to_mem") else ins.src
        cost = _CONTROL[n][ea[0]] + (4 * abs_words if ea[0] == "abs" else 0)
        if n.startswith("movem"):
            cost += bin(ins.aux).count("1") * (8 if long else 4)
        return cost
    # with two absolute operands only their total length is known, and it is all that matters
    src = _ea_cycles(ins.src, long, abs_words if absolute == 1 else 0)
    dst = _ea_cycles(ins.dst, long, abs_words)
    if n in ("move", "movea"):
        if ins.dst[0] == "pd":
            dst -= 2
        return 4 + src + dst
    if n in ("add", "sub", "and", "or", "eor"):
        if dst_mem:
            return (12 if long else 8) + dst
        if n == "eor":
            return 8 if long else 4
        return (4 if not long else 6 if src_mem else 8) + src
    if n in ("adda", "suba"):
        return (8 if not long or not src_mem else 6) + src
    if n == "cmp":
        if ins.dst[0] == "pi":
            return 20 if long else 12
        return (6 if long else 4) + src
    if n == "cmpa":
        return 6 + src
    if n in ("addi", "subi", "andi", "ori", "eori"):
        return ((20 if long else 12) + dst) if dst_mem else (16 if long else 8)
    if n == "cmpi":
        return ((12 if long else 8) + dst) if dst_mem else (14 if long else 8)
    if n in ("addq", "subq"):
        if dst_mem:
            return (12 if long else 8) + dst
        return 8 if long or ins.dst[0] == "a" else 4
    if n in ("clr", "neg", "negx", "not"):
        return ((12 if long else 8) + dst) if dst_mem else (6 if long else 4)
    if n == "tst":
        return 4 + src
    if n == "scc":
        return (8 + dst) if dst_mem else 4
    if n == "tas":
        return (14 + dst) if dst_mem else 4
    if n == "nbcd":
        return (8 + dst) if dst_mem else 6
    if n in ("abcd", "sbcd"):
        return 18 if ins.dst[0] == "pd" else 6
    if n in ("addx", "subx"):
        if ins.dst[0] == "pd":
            return 30 if long else 18
        return 8 if long else 4
    if n in BITOPS:
        dst = _ea_cycles(ins.dst, False, abs_words)
        static = ins.src[0] == "imm"
        if n == "btst":
            return ((8 if static else 4) + dst) if dst_mem else (10 if static else 6)
        if dst_mem:
            return (12 if static else 8) + dst
        return (10 if n == "bclr" else 8) + (4 if static else 0)
    if n in SHIFTS:
        if dst_mem:
            return 8 + dst
        return (8 if long else 6) + (2 * ins.src[1] if ins.src[0] == "imm" else 0)
    if n in ("mulu", "muls"):
        return 38 + src
    if n in ("divu", "divs"):
        return src
    if n in ("move_to_sr", "move_to_ccr"):
        return 12 + src
    if n == "move_from_sr":
        return (8 + dst) if dst_mem else 6
    raise AssertionError("no timing for %s" % n)


class Block:
    def __init__(self, start):
        self.start = start
        self.instrs = []
        self.fault = None       # address where decoding failed
        self.next = None        # fall-through address
        self.succ = []          # static successors (for liveness)
        self.live_out = ALL
        self.all_live = False   # leaves to an unknown place


class Program:
    def __init__(self, fetch16, const_read, is_ram):
        self.fetch16 = fetch16
        self.const_read = const_read   # (addr, size) -> value or None when not constant
        self.is_ram = is_ram
        self.instrs = {}
        self.leaders = set()
        self.blocks = {}

    def decode(self, addr):
        ins = self.instrs.get(addr)
        if ins is None:
            ins = self.instrs[addr] = m68k.decode(self.fetch16, addr)
        return ins

    def explore(self, seeds):
        """Recursive descent from the seed addresses."""
        work = [s for s in seeds if s not in self.leaders]
        self.leaders.update(work)
        while work:
            addr = work.pop()
            prev = None
            while True:
                try:
                    ins = self.decode(addr)
                except Illegal:
                    break
                nxt = addr + ins.length
                new = self.offset_table(prev, ins)
                prev = ins
                if ins.flow in ("branch", "cbranch", "call") and ins.target is not None:
                    new.append(ins.target)
                if ins.flow == "jump" and ins.target is not None:
                    new.append(ins.target)
                if ins.flow in ("cbranch", "call", "sr", "stop"):
                    new.append(nxt)
                new += self.jump_table(ins)
                for a in new:
                    if a not in self.leaders:
                        self.leaders.add(a)
                        work.append(a)
                if ins.flow != "next":
                    break
                addr = nxt
                if addr in self.leaders:
                    break

    def plausible(self, addr, limit=64):
        """Does straight-line decoding from addr look like real code?

        Used for addresses found by scanning for pointers: it must decode
        without illegal opcodes up to an instruction that ends the flow, and
        must not start with the opcodes that runs of data usually decode to.
        """
        try:
            first = self.fetch16(addr)
        except Illegal:
            return False
        if first in (0x0000, 0xffff):
            return False
        for _ in range(limit):
            try:
                ins = m68k.decode(self.fetch16, addr)
            except Illegal:
                return False
            if ins.flow in ("return", "jump", "branch"):
                if ins.target is not None:
                    try:
                        self.fetch16(ins.target)
                    except Illegal:
                        return False
                return True
            addr += ins.length
        return False

    def unrolled_starts(self):
        """Starts of unrolled loops that reach back before a known block.

        The game enters long runs of repeated instructions at a computed
        position. Only the explicitly called tail is found by following the
        code, so where a block is preceded by exact repetitions of its own
        first instructions, the run is followed backwards to its start.
        """
        found = set()
        for start in sorted(self.leaders):
            lengths = []
            addr = start
            try:
                if self.fetch16(start) in (0x0000, 0xffff):
                    continue
                for _ in range(4):
                    ins = self.decode(addr)
                    addr += ins.length
                    lengths.append(addr - start)
                    if ins.flow != "next":
                        break
            except Illegal:
                pass
            for period in lengths:
                try:
                    unit = [self.fetch16(start + o) for o in range(0, period, 2)]
                    low = start
                    while low - period >= 0 and \
                            [self.fetch16(low - period + o) for o in range(0, period, 2)] == unit:
                        low -= period
                except Illegal:
                    continue
                if low < start and low not in self.instrs:
                    found.add(low)
                    break
        return found

    def offset_table(self, prev, ins):
        """Targets of `move.w (table,PC,Dn),Dn` followed by `jmp` or `jsr (base,PC,Dn)`."""
        if prev is None or ins.name not in ("jmp", "jsr") or ins.dst[0] != "pcidx":
            return []
        if prev.name != "move" or prev.size != 2 or prev.src[0] != "pcidx":
            return []
        table = prev.src[1] + prev.src[2]
        base = ins.dst[1] + ins.dst[2]
        out = []
        lowest = None
        while len(out) < 256 and (lowest is None or table < lowest):
            try:
                target = (base + ((self.fetch16(table) ^ 0x8000) - 0x8000)) & 0xffffff
            except Illegal:
                break
            if target & 1 or not self.plausible(target):
                break
            out.append(target)
            if target > table and (lowest is None or target < lowest):
                lowest = target
            table += 2
        return out

    def repeated_runs(self, first, last, minimum=8):
        """Starts of long runs of one repeated instruction between two addresses.

        These are unrolled loops entered at a computed position; nothing may
        ever jump to their start, so they are found by their shape.
        """
        found = set()
        addr = first
        while addr < last:
            try:
                word = self.fetch16(addr)
                run = 1
                while self.fetch16(addr + run * 2) == word:
                    run += 1
            except Illegal:
                break
            if run >= minimum and word not in (0x0000, 0xffff, 0x4e71) and addr not in self.instrs:
                try:
                    if m68k.decode(self.fetch16, addr).length == 2 and self.plausible(addr, limit=1024):
                        found.add(addr)
                except Illegal:
                    pass
            addr += run * 2
        return found

    def jump_table(self, ins):
        """Targets of a longword jump table read with a PC-relative index."""
        if ins.name != "movea" or ins.size != 4 or ins.src[0] != "pcidx":
            return []
        table = ins.src[1] + ins.src[2]
        out = []
        lowest = None
        while len(out) < 256:
            if lowest is not None and table >= lowest:
                break
            try:
                v = (self.fetch16(table) << 16) | self.fetch16(table + 2)
                if v & 1:
                    break
                self.fetch16(v)
            except Illegal:
                break
            out.append(v)
            if v > ins.addr and (lowest is None or v < lowest):
                lowest = v
            table += 4
        return out

    def build_blocks(self):
        self.blocks = {}
        for start in sorted(self.leaders):
            b = Block(start)
            addr = start
            while True:
                try:
                    ins = self.decode(addr)
                except Illegal:
                    b.fault = addr
                    break
                b.instrs.append(ins)
                addr += ins.length
                if ins.flow != "next":
                    break
                if addr in self.leaders:
                    break
            b.next = addr
            last = b.instrs[-1] if b.instrs else None
            if b.fault is not None or last is None:
                b.all_live = True
            elif last.flow == "next":
                b.succ = [addr]
            elif last.flow in ("sr", "stop"):
                b.all_live = True
            elif last.flow == "branch":
                b.succ = [last.target]
            elif last.flow == "cbranch":
                b.succ = [last.target, addr]
            elif last.flow == "call":
                # flags flow into the callee; what it returns is unknown
                if last.target is None:
                    b.all_live = True
                else:
                    b.succ = [last.target]
            elif last.flow == "jump":
                if last.target is None:
                    b.all_live = True
                else:
                    b.succ = [last.target]
            else:
                b.all_live = True
            self.blocks[start] = b

    def liveness(self):
        live_in = {a: frozenset() for a in self.blocks}
        changed = True
        while changed:
            changed = False
            for a in sorted(self.blocks, reverse=True):
                b = self.blocks[a]
                if b.all_live:
                    out = ALL
                else:
                    out = frozenset()
                    for s in b.succ:
                        out |= live_in.get(s, ALL)
                b.live_out = out
                live = out
                for ins in reversed(b.instrs):
                    uses, kills = flag_effects(ins)
                    live = (live - kills) | uses
                if live != live_in[a]:
                    live_in[a] = live
                    changed = True


class Emitter:
    def __init__(self, program):
        self.p = program
        self.out = []
        self.indent = 1

    def emit(self, line):
        self.out.append("\t" * self.indent + line)

    # --- operand helpers -------------------------------------------------

    def index(self, xkind, xn, xlong):
        reg = "%s%d" % (xkind, xn)
        return reg if xlong else "(((%s & 0xFFFF) ^ 0x8000) - 0x8000)" % reg

    def address(self, ea, size):
        """Returns (pre statements, expression, post statements, constant or None)."""
        kind = ea[0]
        if kind == "ind":
            return [], "a%d" % ea[1], [], None
        if kind in ("pi", "pd"):
            step = 2 if (size == 1 and ea[1] == 7) else size
            reg = "a%d" % ea[1]
            if kind == "pi":
                return [], reg, ["%s = (%s + %d) & 0xFFFFFFFF" % (reg, reg, step)], None
            return ["%s = (%s - %d) & 0xFFFFFFFF" % (reg, reg, step)], reg, [], None
        if kind == "disp":
            return [], "(a%d + %d)" % (ea[1], ea[2]), [], None
        if kind == "idx":
            return [], "(a%d + %d + %s)" % (ea[1], ea[2], self.index(*ea[3:])), [], None
        if kind == "abs":
            return [], "0x%X" % ea[1], [], ea[1]
        if kind == "pcidx":
            return [], "(%d + %s)" % (ea[1] + ea[2], self.index(*ea[3:])), [], None
        raise AssertionError(ea)

    def mem_read(self, size, expr, const):
        if const is not None:
            c = const & 0xffffff
            v = self.p.const_read(c, size)
            if v is not None:
                return "0x%X" % v
            if self.p.is_ram(c):
                o = c & 0xffff
                if size == 1:
                    return "ram[%d]" % (o ^ 1)
                if size == 2:
                    return "ram.decode_u16(%d)" % o
                return "((ram.decode_u16(%d) << 16) | ram.decode_u16(%d))" % (o, (o + 2) & 0xffff)
        return "r%d(%s)" % (BITS[size], expr)

    def mem_write(self, size, expr, const, value):
        if const is not None and self.p.is_ram(const & 0xffffff):
            o = const & 0xffff
            if size == 1:
                self.emit("ram[%d] = %s" % (o ^ 1, value))
            elif size == 2:
                self.emit("ram.encode_u16(%d, %s)" % (o, value))
            else:
                self.emit("ram.encode_u16(%d, %s >> 16)" % (o, value))
                self.emit("ram.encode_u16(%d, %s & 0xFFFF)" % ((o + 2) & 0xffff, value))
        else:
            self.emit("w%d(%s, %s)" % (BITS[size], expr, value))

    def load(self, ea, size, tmp):
        """Emit `tmp = operand value` (unsigned, masked to size)."""
        kind = ea[0]
        if kind == "imm":
            self.emit("%s = 0x%X" % (tmp, ea[1] & MASK[size]))
        elif kind in ("d", "a"):
            reg = "%s%d" % (kind, ea[1])
            self.emit("%s = %s" % (tmp, reg if size == 4 else "%s & 0x%X" % (reg, MASK[size])))
        else:
            pre, expr, post, const = self.address(ea, size)
            for line in pre:
                self.emit(line)
            self.emit("%s = %s" % (tmp, self.mem_read(size, expr, const)))
            for line in post:
                self.emit(line)

    def store(self, ea, size, value):
        """Emit a write of `value` (already masked, a simple name or literal)."""
        kind = ea[0]
        if kind == "d":
            reg = "d%d" % ea[1]
            if size == 4:
                self.emit("%s = %s" % (reg, value))
            else:
                self.emit("%s = (%s & 0x%X) | %s" % (reg, reg, 0xffffffff ^ MASK[size], value))
        elif kind == "a":
            self.emit("a%d = %s" % (ea[1], value))
        else:
            pre, expr, post, const = self.address(ea, size)
            for line in pre:
                self.emit(line)
            self.mem_write(size, expr, const, value)
            for line in post:
                self.emit(line)

    def load_modify(self, ea, size, tmp):
        """Load for read-modify-write; returns a function that writes the result back."""
        kind = ea[0]
        if kind in ("d", "a"):
            self.load(ea, size, tmp)
            return lambda value: self.store(ea, size, value)
        pre, expr, post, const = self.address(ea, size)
        for line in pre:
            self.emit(line)
        if const is None:
            self.emit("ea = %s" % expr)
            expr = "ea"
        self.emit("%s = %s" % (tmp, self.mem_read(size, expr, const)))

        def write(value):
            self.mem_write(size, expr, const, value)
            for line in post:
                self.emit(line)
        return write

    # --- flags -----------------------------------------------------------

    def logic_flags(self, need, r, size):
        if "n" in need:
            self.emit("fn = %s >> %d" % (r, BITS[size] - 1))
        if "z" in need:
            self.emit("fz = int(%s == 0)" % r)
        if "v" in need:
            self.emit("fv = 0")
        if "c" in need:
            self.emit("fc = 0")

    def add_op(self, need, size, extend=False):
        """r = s + t (+ fx); leaves r masked."""
        sb = BITS[size] - 1
        self.emit("r = s + t" + (" + fx" if extend else ""))
        if "c" in need:
            self.emit("fc = r >> %d" % BITS[size])
        if "x" in need:
            self.emit("fx = r >> %d" % BITS[size])
        self.emit("r &= 0x%X" % MASK[size])
        if "v" in need:
            self.emit("fv = ((s ^ r) & (t ^ r)) >> %d" % sb)
        if "n" in need:
            self.emit("fn = r >> %d" % sb)
        if extend:
            self.emit("if r != 0: fz = 0")
        elif "z" in need:
            self.emit("fz = int(r == 0)")

    def sub_op(self, need, size, extend=False, x_too=True):
        """r = t - s (- fx); leaves r masked."""
        sb = BITS[size] - 1
        if extend:
            self.emit("r = t - s - fx")
            if "c" in need:
                self.emit("fc = int(r < 0)")
            if "x" in need:
                self.emit("fx = int(r < 0)")
            self.emit("r &= 0x%X" % MASK[size])
        else:
            self.emit("r = (t - s) & 0x%X" % MASK[size])
            if "c" in need:
                self.emit("fc = int(s > t)")
            if x_too and "x" in need:
                self.emit("fx = int(s > t)")
        if "v" in need:
            self.emit("fv = ((s ^ t) & (r ^ t)) >> %d" % sb)
        if "n" in need:
            self.emit("fn = r >> %d" % sb)
        if extend:
            self.emit("if r != 0: fz = 0")
        elif "z" in need:
            self.emit("fz = int(r == 0)")

    # --- instructions ----------------------------------------------------

    def instruction(self, ins, need, nxt):
        """Emit one instruction. Returns True when it ended the block (emitted its return)."""
        n, size = ins.name, ins.size
        e = self.emit

        if n == "nop" or n == "reset":
            return False
        if n == "move":
            self.load(ins.src, size, "s")
            self.store(ins.dst, size, "s")
            self.logic_flags(need, "s", size)
        elif n == "movea":
            self.load(ins.src, size, "s")
            e("a%d = %s" % (ins.dst[1], "s" if size == 4 else "((s ^ 0x8000) - 0x8000) & 0xFFFFFFFF"))
        elif n == "moveq":
            v = ins.src[1]
            e("d%d = 0x%X" % (ins.dst[1], v))
            if "n" in need:
                e("fn = %d" % (v >> 31))
            if "z" in need:
                e("fz = %d" % int(v == 0))
            if "v" in need:
                e("fv = 0")
            if "c" in need:
                e("fc = 0")
        elif n == "lea":
            _, expr, _, _ = self.address(ins.src, 4)
            e("a%d = %s & 0xFFFFFFFF" % (ins.dst[1], expr))
        elif n == "pea":
            _, expr, _, _ = self.address(ins.src, 4)
            e("a7 = (a7 - 4) & 0xFFFFFFFF")
            e("w32(a7, %s & 0xFFFFFFFF)" % expr)
        elif n == "clr":
            self.store(ins.dst, size, "0")
            if "n" in need:
                e("fn = 0")
            if "z" in need:
                e("fz = 1")
            if "v" in need:
                e("fv = 0")
            if "c" in need:
                e("fc = 0")
        elif n == "tst":
            self.load(ins.src, size, "s")
            self.logic_flags(need, "s", size)
        elif n == "not":
            write = self.load_modify(ins.dst, size, "t")
            e("r = t ^ 0x%X" % MASK[size])
            write("r")
            self.logic_flags(need, "r", size)
        elif n in ("neg", "negx"):
            write = self.load_modify(ins.dst, size, "s")
            e("t = 0")
            self.sub_op(need, size, extend=(n == "negx"))
            write("r")
        elif n == "ext":
            reg = "d%d" % ins.dst[1]
            if size == 2:
                e("r = (((%s & 0xFF) ^ 0x80) - 0x80) & 0xFFFF" % reg)
                e("%s = (%s & 0xFFFF0000) | r" % (reg, reg))
            else:
                e("r = (((%s & 0xFFFF) ^ 0x8000) - 0x8000) & 0xFFFFFFFF" % reg)
                e("%s = r" % reg)
            self.logic_flags(need, "r", size)
        elif n == "swap":
            reg = "d%d" % ins.dst[1]
            e("r = ((%s << 16) | (%s >> 16)) & 0xFFFFFFFF" % (reg, reg))
            e("%s = r" % reg)
            self.logic_flags(need, "r", 4)
        elif n == "exg":
            a = "%s%d" % ins.src
            b = "%s%d" % ins.dst
            e("r = %s" % a)
            e("%s = %s" % (a, b))
            e("%s = r" % b)
        elif n in ("addq", "subq") and ins.dst[0] == "a":
            reg = "a%d" % ins.dst[1]
            e("%s = (%s %s %d) & 0xFFFFFFFF" % (reg, reg, "+" if n == "addq" else "-", ins.src[1]))
        elif n in ("add", "addi", "addq"):
            self.load(ins.src, size, "s")
            write = self.load_modify(ins.dst, size, "t")
            self.add_op(need, size)
            write("r")
        elif n in ("sub", "subi", "subq"):
            self.load(ins.src, size, "s")
            write = self.load_modify(ins.dst, size, "t")
            self.sub_op(need, size)
            write("r")
        elif n in ("cmp", "cmpi"):
            self.load(ins.src, size, "s")
            self.load(ins.dst, size, "t")
            self.sub_op(need, size, x_too=False)
        elif n in ("adda", "suba", "cmpa"):
            self.load(ins.src, size, "s")
            if size == 2:
                e("s = ((s ^ 0x8000) - 0x8000) & 0xFFFFFFFF")
            reg = "a%d" % ins.dst[1]
            if n == "cmpa":
                e("t = %s" % reg)
                self.sub_op(need, 4, x_too=False)
            else:
                e("%s = (%s %s s) & 0xFFFFFFFF" % (reg, reg, "+" if n == "adda" else "-"))
        elif n in ("addx", "subx"):
            self.load(ins.src, size, "s")
            write = self.load_modify(ins.dst, size, "t")
            if n == "addx":
                self.add_op(need, size, extend=True)
            else:
                self.sub_op(need, size, extend=True)
            write("r")
        elif n in ("and", "or", "eor", "andi", "ori", "eori"):
            self.load(ins.src, size, "s")
            write = self.load_modify(ins.dst, size, "t")
            e("r = s %s t" % {"a": "&", "o": "|", "e": "^"}[n[0]])
            write("r")
            self.logic_flags(need, "r", size)
        elif n in ("mulu", "muls"):
            self.load(ins.src, 2, "s")
            reg = "d%d" % ins.dst[1]
            if n == "mulu":
                e("r = (s * (%s & 0xFFFF)) & 0xFFFFFFFF" % reg)
            else:
                e("r = (((s ^ 0x8000) - 0x8000) * (((%s & 0xFFFF) ^ 0x8000) - 0x8000)) & 0xFFFFFFFF" % reg)
            e("%s = r" % reg)
            # two cycles for every one bit (unsigned) or bit change (signed) in the source
            e("cyc += ONES[%s] * 2" % ("s" if n == "mulu" else "(s ^ (s << 1)) & 0xFFFF"))
            self.logic_flags(need, "r", 4)
        elif n in ("divu", "divs"):
            self.load(ins.src, 2, "s")
            e("d%d = %s(d%d, s)" % (ins.dst[1], n, ins.dst[1]))
        elif n in SHIFTS:
            if ins.src[0] == "imm":
                count = "%d" % ins.src[1]
            else:
                count = "d%d & 63" % ins.src[1]
            write = self.load_modify(ins.dst, size, "t")
            if ins.src[0] != "imm":
                e("cyc += (%s) * 2" % count)
            e("r = sh_%s(t, %s, %d)" % (n, count, BITS[size]))
            write("r")
        elif n in BITOPS:
            width = 32 if ins.dst[0] == "d" else 8
            if ins.src[0] == "imm":
                bit = "0x%X" % (1 << (ins.src[1] % width))
            else:
                e("s = 1 << (d%d & %d)" % (ins.src[1], width - 1))
                bit = "s"
            if n == "btst":
                self.load(ins.dst, 4 if width == 32 else 1, "t")
                if "z" in need:
                    e("fz = int((t & %s) == 0)" % bit)
            else:
                write = self.load_modify(ins.dst, 4 if width == 32 else 1, "t")
                if "z" in need:
                    e("fz = int((t & %s) == 0)" % bit)
                if n == "bchg":
                    e("r = t ^ %s" % bit)
                elif n == "bset":
                    e("r = t | %s" % bit)
                else:
                    e("r = t & (%s ^ 0x%X)" % (bit, MASK[4] if width == 32 else 0xff))
                write("r")
        elif n == "tas":
            write = self.load_modify(ins.dst, 1, "t")
            self.logic_flags(need, "t", 1)
            e("r = t | 0x80")
            write("r")
        elif n == "scc":
            e("r = 0xFF if %s else 0" % COND_EXPR[ins.aux])
            if ins.dst[0] == "d":
                e("cyc += r & 2")
            self.store(ins.dst, 1, "r")
        elif n in ("abcd", "sbcd"):
            self.load(ins.src, 1, "s")
            write = self.load_modify(ins.dst, 1, "t")
            e("r = %s(s, t)" % n)
            write("r")
        elif n == "nbcd":
            write = self.load_modify(ins.dst, 1, "s")
            e("r = sbcd(s, 0)")
            write("r")
        elif n == "link":
            reg = "a%d" % ins.dst[1]
            e("a7 = (a7 - 4) & 0xFFFFFFFF")
            e("w32(a7, %s)" % reg)
            e("%s = a7" % reg)
            e("a7 = (a7 + %d) & 0xFFFFFFFF" % ins.src[1])
        elif n == "unlk":
            reg = "a%d" % ins.dst[1]
            e("a7 = %s" % reg)
            e("%s = r32(a7)" % reg)
            e("a7 = (a7 + 4) & 0xFFFFFFFF")
        elif n == "movem_to_mem":
            self.movem_to_mem(ins)
        elif n == "movem_to_reg":
            self.movem_to_reg(ins)
        elif n == "move_from_sr":
            e("r = get_sr()")
            self.store(ins.dst, 2, "r")
        elif n == "move_to_ccr":
            self.load(ins.src, 2, "s")
            e("set_ccr(s)")
        elif n in ("andi_ccr", "ori_ccr", "eori_ccr"):
            e("set_ccr(get_ccr() %s 0x%X)" % ({"a": "&", "o": "|", "e": "^"}[n[0]], ins.src[1]))
        elif n == "move_to_usp":
            e("usp = a%d" % ins.src[1])
        elif n == "move_from_usp":
            e("a%d = usp" % ins.dst[1])
        elif n == "move_to_sr":
            self.load(ins.src, 2, "s")
            e("set_sr(s)")
            e("return 0x%X" % nxt)
            return True
        elif n in ("andi_sr", "ori_sr", "eori_sr"):
            e("set_sr(get_sr() %s 0x%X)" % ({"a": "&", "o": "|", "e": "^"}[n[0]], ins.src[1]))
            e("return 0x%X" % nxt)
            return True
        elif n == "stop":
            e("set_sr(0x%X)" % ins.src[1])
            e("stopped = true")
            e("return 0x%X" % nxt)
            return True
        elif n == "bra":
            e("return 0x%X" % ins.target)
            return True
        elif n == "bcc":
            e("if %s:" % COND_EXPR[ins.aux])
            e("\tcyc %s 2" % ("+=" if ins.length == 2 else "-="))
            e("\treturn 0x%X" % ins.target)
            e("return 0x%X" % nxt)
            return True
        elif n == "dbcc":
            reg = "d%d" % ins.dst[1]
            pad = ""
            if ins.aux != "f":
                e("if not (%s):" % COND_EXPR[ins.aux])
                pad = "\t"
            e(pad + "r = ((%s & 0xFFFF) - 1) & 0xFFFF" % reg)
            e(pad + "%s = (%s & 0xFFFF0000) | r" % (reg, reg))
            e(pad + "if r != 0xFFFF:")
            e(pad + "\treturn 0x%X" % ins.target)
            e(pad + "cyc += 2")
            e("cyc += 2")
            e("return 0x%X" % nxt)
            return True
        elif n in ("bsr", "jsr", "jmp"):
            if ins.target is not None:
                target = "0x%X" % ins.target
            else:
                _, expr, _, _ = self.address(ins.dst, 4)
                e("r = %s & 0xFFFFFF" % expr)
                target = "r"
            if n != "jmp":
                e("a7 = (a7 - 4) & 0xFFFFFFFF")
                e("w32(a7, 0x%X)" % nxt)
            e("return %s" % target)
            return True
        elif n == "rts":
            e("r = r32(a7)")
            e("a7 = (a7 + 4) & 0xFFFFFFFF")
            e("return r & 0xFFFFFF")
            return True
        elif n == "rte":
            e("s = r16(a7)")
            e("r = r32(a7 + 2)")
            e("a7 = (a7 + 6) & 0xFFFFFFFF")
            e("set_sr(s)")
            e("return r & 0xFFFFFF")
            return True
        elif n == "rtr":
            e("s = r16(a7)")
            e("r = r32(a7 + 2)")
            e("a7 = (a7 + 6) & 0xFFFFFFFF")
            e("set_ccr(s)")
            e("return r & 0xFFFFFF")
            return True
        elif n == "trap":
            e("return fault(0x%X)" % ins.addr)
            return True
        else:
            raise AssertionError(n)
        return False

    def movem_to_mem(self, ins):
        e, size, mask = self.emit, ins.size, ins.aux
        if ins.dst[0] == "pd":
            reg = "a%d" % ins.dst[1]
            names = ["a%d" % i for i in range(7, -1, -1)] + ["d%d" % i for i in range(7, -1, -1)]
            e("ea = %s" % reg)
            for i in range(16):
                if mask & (1 << i):
                    e("ea -= %d" % size)
                    e("w%d(ea, %s)" % (BITS[size], names[i] if size == 4 else names[i] + " & 0xFFFF"))
            e("%s = ea & 0xFFFFFFFF" % reg)
        else:
            _, expr, _, _ = self.address(ins.dst, size)
            names = ["d%d" % i for i in range(8)] + ["a%d" % i for i in range(8)]
            e("ea = %s" % expr)
            for i in range(16):
                if mask & (1 << i):
                    e("w%d(ea, %s)" % (BITS[size], names[i] if size == 4 else names[i] + " & 0xFFFF"))
                    e("ea += %d" % size)

    def movem_to_reg(self, ins):
        e, size, mask = self.emit, ins.size, ins.aux
        names = ["d%d" % i for i in range(8)] + ["a%d" % i for i in range(8)]
        if ins.src[0] == "pi":
            expr = "a%d" % ins.src[1]
        else:
            _, expr, _, _ = self.address(ins.src, size)
        e("ea = %s" % expr)
        for i in range(16):
            if mask & (1 << i):
                if size == 4:
                    e("%s = r32(ea)" % names[i])
                else:
                    e("%s = ((r16(ea) ^ 0x8000) - 0x8000) & 0xFFFFFFFF" % names[i])
                e("ea += %d" % size)
        if ins.src[0] == "pi":
            e("a%d = ea & 0xFFFFFFFF" % ins.src[1])

    # --- blocks ----------------------------------------------------------

    def block(self, b):
        self.indent = 0
        self.emit("func b_%06X() -> int:" % b.start)
        self.indent = 1
        self.emit("var s: int")
        self.emit("var t: int")
        self.emit("var r: int")
        self.emit("var ea: int")
        cost = sum(cycles(i) for i in b.instrs)
        last = b.instrs[-1] if b.instrs else None
        loops = last is not None and last.flow == "cbranch" and last.target == b.start
        if loops:
            # A block that branches back to itself runs as a native loop, but
            # still yields to the dispatcher when an event is due.
            self.emit("while true:")
            self.indent = 2
        self.emit("cyc += %d" % max(cost, 4))
        # flags needed after each instruction
        need_after = []
        live = b.live_out
        for ins in reversed(b.instrs):
            need_after.append(live)
            uses, kills = flag_effects(ins)
            live = (live - kills) | uses
        need_after.reverse()
        ended = False
        for ins, need in zip(b.instrs, need_after):
            nxt = ins.addr + ins.length
            if loops and ins is last:
                self.loop_tail(ins, nxt)
                ended = True
            else:
                ended = self.instruction(ins, need, nxt)
        if loops:
            self.indent = 1
            self.emit("return 0x%X" % b.start)
        if not ended:
            if b.fault is not None:
                self.emit("return fault(0x%X)" % b.fault)
            else:
                self.emit("return 0x%X" % b.next)
        self.out.append("")

    def step(self, ins):
        """A one-instruction block, so that execution can enter anywhere.

        The game jumps into the middle of its unrolled loops; such an entry
        runs instruction by instruction until it reaches a real block start.
        """
        self.indent = 0
        self.emit("func s_%06X() -> int:" % ins.addr)
        self.indent = 1
        self.emit("var s: int")
        self.emit("var t: int")
        self.emit("var r: int")
        self.emit("var ea: int")
        self.emit("cyc += %d" % cycles(ins))
        nxt = ins.addr + ins.length
        if not self.instruction(ins, ALL, nxt):
            self.emit("return 0x%X" % nxt)
        self.out.append("")

    def loop_tail(self, ins, nxt):
        e = self.emit
        again = "if cyc >= event_cyc: return 0x%X" % ins.target
        if ins.name == "bcc":
            e("if not (%s): return 0x%X" % (COND_EXPR[ins.aux], nxt))
            e("cyc %s 2" % ("+=" if ins.length == 2 else "-="))
            e(again)
        else:
            reg = "d%d" % ins.dst[1]
            if ins.aux != "f":
                e("if %s:" % COND_EXPR[ins.aux])
                e("\tcyc += 2")
                e("\treturn 0x%X" % nxt)
            e("r = ((%s & 0xFFFF) - 1) & 0xFFFF" % reg)
            e("%s = (%s & 0xFFFF0000) | r" % (reg, reg))
            e("if r == 0xFFFF:")
            e("\tcyc += 4")
            e("\treturn 0x%X" % nxt)
            e(again)


def generate(program, base_script, chunk_functions=3000):
    """Returns {filename: source}. Functions are spread over several scripts
    chained by inheritance so that no single script gets too large."""
    em = Emitter(program)
    starts = sorted(program.blocks)
    units = []          # (address, function name, source lines)
    stepped = set()
    for a in starts:
        b = program.blocks[a]
        em.out = []
        em.block(b)
        units.append((a, "b_%06X" % a, em.out))
        for ins in b.instrs[1:]:
            if ins.addr not in program.blocks and ins.addr not in stepped:
                stepped.add(ins.addr)
                em.out = []
                em.step(ins)
                units.append((ins.addr, "s_%06X" % ins.addr, em.out))
    files = {}
    parent = base_script
    count = (len(units) + chunk_functions - 1) // chunk_functions
    for c in range(count):
        body = []
        for _, _, lines in units[c * chunk_functions:(c + 1) * chunk_functions]:
            body += lines
        last = c == count - 1
        name = "program.gd" if last else "program_%02d.gd" % c
        head = ["# Generated by Tools/recomp - do not edit.", 'extends "%s"' % parent, ""]
        if last:
            head += ["func block_table() -> Dictionary:", "\treturn {"]
            head += ["\t\t0x%X: %s," % (a, fn) for a, fn, _ in units]
            head += ["\t}", ""]
        files[name] = "\n".join(head + body) + "\n"
        parent = name
    return files
