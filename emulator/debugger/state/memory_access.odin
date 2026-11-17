package state

import rv "../../core"

// Which load or store the next instruction will do. Next records it
// (Session.last_access) so the Memory tab can stay on the data a program is
// working with; the Memory and Stack tabs colour it.

Memory_Access_Kind :: enum {
	None,
	Load,
	Store,
}

Memory_Access :: struct {
	kind:    Memory_Access_Kind,
	address: u64,
	size:    u64,
}

// The load or store the instruction at the PC is about to do, if any.
next_memory_access :: proc(session: ^Session) -> Memory_Access {
	cpu := &session.machine.cpu
	raw, ok := rv.bus_load(&session.machine.bus, cpu.pc, 4)
	if !ok {
		return {}
	}
	instruction := u32(raw)
	base := rv.reg_read(cpu, rv.rs1(instruction))
	size := u64(1) << (rv.funct3(instruction) & 0b11)
	switch rv.opcode(instruction) {
	case rv.OPCODE_LOAD:
		return {.Load, base + rv.imm_i(instruction), size}
	case rv.OPCODE_STORE:
		return {.Store, base + rv.imm_s(instruction), size}
	case rv.OPCODE_AMO:
		// No offset; LR only reads, SC and the AMOs write.
		kind := Memory_Access_Kind.Load if rv.funct5(instruction) == rv.AMO_LR else .Store
		return {kind, base, size}
	}
	return {}
}
