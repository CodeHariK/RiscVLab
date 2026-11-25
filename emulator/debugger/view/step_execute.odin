package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import disasm "../../disasm"
import state "../state"

// The execute stage of the detailed step view (step_detail.odin): the
// arithmetic, address or decision the instruction made, written with the
// values it used, e.g.
//
//   t1 0x3 (3) != zero 0x0 -> taken: target = pc 0x80000020 + -0x10 = 0x80000010
//   address = t0 0x80001000 + 0x0 = 0x80001000 (numbers)

execute_text :: proc(session: ^state.Session, entry: state.Timeline_Entry) -> string {
	instruction := entry.instruction
	mnemonic := step_mnemonic(entry)
	pc := entry.pc
	a, b := entry.rs1_value, entry.rs2_value
	s1 := disasm.register_name(rv.rs1(instruction))
	s2 := disasm.register_name(rv.rs2(instruction))
	result := result_text(entry)

	switch rv.opcode(instruction) {
	case rv.OPCODE_LUI:
		return fmt.tprintf("0x%x << 12 = %s", instruction >> 12, result)
	case rv.OPCODE_AUIPC:
		return fmt.tprintf("pc 0x%x + (0x%x << 12) = %s", pc, instruction >> 12, result)
	case rv.OPCODE_JAL:
		offset := rv.imm_j(instruction)
		return fmt.tprintf(
			"target = pc 0x%x + %s = 0x%x%s%s",
			pc,
			signed_text(i64(offset)),
			pc + offset,
			state.symbol_label(session, pc + offset),
			return_address_text(instruction, pc),
		)
	case rv.OPCODE_JALR:
		target := (a + rv.imm_i(instruction)) & ~u64(1)
		return fmt.tprintf(
			"target = (%s 0x%x + %s) & ~1 = 0x%x%s%s",
			s1,
			a,
			signed_text(i64(rv.imm_i(instruction))),
			target,
			state.symbol_label(session, target),
			return_address_text(instruction, pc),
		)
	case rv.OPCODE_BRANCH:
		comparison, taken := branch_comparison(mnemonic, a, b)
		offset := rv.imm_b(instruction)
		decision := "not taken: continue with the next instruction"
		if taken {
			decision = fmt.tprintf(
				"taken: target = pc 0x%x + %s = 0x%x%s",
				pc,
				signed_text(i64(offset)),
				pc + offset,
				state.symbol_label(session, pc + offset),
			)
		}
		return fmt.tprintf("%s %s %s %s %s -> %s", s1, value_text(a), comparison, s2, value_text(b), decision)
	case rv.OPCODE_LOAD:
		address := a + rv.imm_i(instruction)
		return fmt.tprintf(
			"address = %s 0x%x + %s = 0x%x%s",
			s1,
			a,
			signed_text(i64(rv.imm_i(instruction))),
			address,
			state.symbol_label(session, address),
		)
	case rv.OPCODE_STORE:
		address := a + rv.imm_s(instruction)
		return fmt.tprintf(
			"address = %s 0x%x + %s = 0x%x%s",
			s1,
			a,
			signed_text(i64(rv.imm_s(instruction))),
			address,
			state.symbol_label(session, address),
		)
	case rv.OPCODE_OP_IMM, rv.OPCODE_OP_IMM_32:
		operand := signed_text(i64(rv.imm_i(instruction)))
		if is_shift(mnemonic) {
			shift_mask: u32 = 0x3F if rv.opcode(instruction) == rv.OPCODE_OP_IMM else 0x1F
			operand = value_text(u64((instruction >> 20) & shift_mask))
		}
		return arithmetic_text(mnemonic, s1, a, operand, result)
	case rv.OPCODE_OP, rv.OPCODE_OP_32:
		text := arithmetic_text(mnemonic, s1, a, fmt.tprintf("%s %s", s2, value_text(b)), result)
		return fmt.tprintf("%s%s", text, muldiv_note(mnemonic, a, b))
	case rv.OPCODE_MISC_MEM:
		return "fence: orders memory accesses; nothing to do on one in-order hart"
	case rv.OPCODE_AMO:
		return atomic_execute_text(session, entry, mnemonic, s1, s2)
	case rv.OPCODE_SYSTEM:
		if rv.funct3(instruction) != 0 {
			return csr_execute_text(session, entry, mnemonic, s1)
		}
		return system_call_text(entry)
	}
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("unknown encoding: raises %v (mtval = 0x%x)", trap.cause, trap.value)
	}
	return "?"
}

// "; return address = pc + 4 = 0x...", or that there is none: with
// rd = zero (j, ret) the jump keeps no way back.
@(private)
return_address_text :: proc(instruction: u32, pc: u64) -> string {
	if rv.rd(instruction) == 0 {
		return "; rd is zero, so no return address is kept"
	}
	return fmt.tprintf("; return address = pc + 4 = 0x%x", pc + rv.INSTRUCTION_SIZE)
}

// LR / SC / AMO: the address (rs1, no offset), and for SC whether the
// reservation holds, for an AMO the new value.
@(private)
atomic_execute_text :: proc(session: ^state.Session, entry: state.Timeline_Entry, mnemonic: string, s1: string, s2: string) -> string {
	instruction := entry.instruction
	address := entry.rs1_value
	place := state.symbol_label(session, address)
	if trap, took_trap := entry.trap.?; took_trap {
		#partial switch trap.cause {
		case .Load_Address_Misaligned, .Store_Address_Misaligned:
			return fmt.tprintf("address = %s 0x%x: raises %v (atomics must be aligned to their size)", s1, address, trap.cause)
		case .Load_Access_Fault, .Store_Access_Fault:
			return fmt.tprintf("address = %s 0x%x: raises %v (no memory there)", s1, address, trap.cause)
		}
		return fmt.tprintf("raises %v", trap.cause)
	}
	size := u64(1) << (rv.funct3(instruction) & 0b11)
	switch rv.funct5(instruction) {
	case rv.AMO_LR:
		return fmt.tprintf("address = %s 0x%x%s; reserve it, so a later SC there can succeed", s1, address, place)
	case rv.AMO_SC:
		reservation := entry.reservation
		if !reservation.valid {
			return fmt.tprintf("no reservation (no LR since the last SC or trap): fail, %s = 1", disasm.register_name(rv.rd(instruction)))
		}
		if reservation.address != address || reservation.size != size {
			return fmt.tprintf("the reservation is for 0x%x, not 0x%x: fail, rd = 1", reservation.address, address)
		}
		return fmt.tprintf("the reservation for 0x%x%s holds: store %s, rd = 0 (success)", address, place, s2)
	}
	old := entry.load_value
	if size == 4 {
		old = u64(i64(i32(u32(old))))
	}
	return fmt.tprintf(
		"address = %s 0x%x%s; rd = old %s; memory = old %s %s %s = %s",
		s1,
		address,
		place,
		value_text(old),
		atomic_operator(mnemonic),
		s2,
		value_text(entry.rs2_value),
		value_text(entry.memory_new),
	)
}

// "+" for amoadd, "min (signed) with" for amomin, ...
@(private)
atomic_operator :: proc(mnemonic: string) -> string {
	name := mnemonic[:strings.index_byte(mnemonic, '.')] if strings.contains(mnemonic, ".") else mnemonic
	switch name {
	case "amoswap": return "replaced by"
	case "amoadd": return "+"
	case "amoand": return "&"
	case "amoor": return "|"
	case "amoxor": return "^"
	case "amomin": return "min (signed) with"
	case "amomax": return "max (signed) with"
	case "amominu": return "min (unsigned) with"
	case "amomaxu": return "max (unsigned) with"
	}
	return "?"
}

// The value written to rd, or why there isn't one.
@(private)
result_text :: proc(entry: state.Timeline_Entry) -> string {
	if entry.record.register_changed {
		return value_text(entry.register_new)
	}
	return "(dropped: rd is zero)"
}

// ADD / SUB / AND / shifts / SLT and their I and W forms.
@(private)
arithmetic_text :: proc(mnemonic: string, s1: string, a: u64, operand: string, result: string) -> string {
	if strings.has_prefix(mnemonic, "slt") {
		kind := "unsigned" if strings.has_suffix(mnemonic, "u") else "signed"
		return fmt.tprintf("is %s %s < %s (%s)? -> %s", s1, value_text(a), operand, kind, result)
	}
	return fmt.tprintf("%s %s %s %s = %s%s", s1, value_text(a), operator(mnemonic), operand, result, word_note(mnemonic))
}

// CSRRW / CSRRS / CSRRC (and the immediate forms): the new value worked
// out from the old one, and what the CSR kept.
@(private)
csr_execute_text :: proc(session: ^state.Session, entry: state.Timeline_Entry, mnemonic: string, s1: string) -> string {
	instruction := entry.instruction
	csr := disasm.csr_name(rv.csr_address(instruction))
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("%s: raises %v", csr_trap_reason(session, entry), trap.cause)
	}
	old := entry.csr_value
	source := entry.rs1_value
	source_text := fmt.tprintf("%s %s", s1, value_text(source))
	if strings.has_suffix(mnemonic, "i") {
		source = u64(rv.rs1(instruction))
		source_text = fmt.tprintf("uimm %s", value_text(source))
	}

	wanted: u64
	how: string
	switch mnemonic {
	case "csrrw", "csrrwi":
		wanted, how = source, fmt.tprintf("new %s = %s", csr, source_text)
	case "csrrs", "csrrsi":
		wanted, how = old | source, fmt.tprintf("new %s = old %s | %s = 0x%x", csr, value_text(old), source_text, old | source)
	case "csrrc", "csrrci":
		wanted, how = old &~ source, fmt.tprintf("new %s = old %s & ~%s = 0x%x", csr, value_text(old), source_text, old &~ source)
	}

	record := entry.record
	if !record.csr_changed {
		return fmt.tprintf("rd gets old %s %s; source is zero, so %s is not written", csr, value_text(old), csr)
	}
	kept := ""
	if entry.csr_new != wanted {
		kept = fmt.tprintf(" -> kept 0x%x (WARL: the CSR only keeps the bits it supports)", entry.csr_new)
	}
	return fmt.tprintf("%s%s; rd gets the old value %s", how, kept, value_text(old))
}

// Why a CSR instruction trapped, in the order the hart checks: privilege,
// whether the CSR exists, then writing a read-only one.
@(private)
csr_trap_reason :: proc(session: ^state.Session, entry: state.Timeline_Entry) -> string {
	address := rv.csr_address(entry.instruction)
	name := disasm.csr_name(address)
	if name == "" {
		name = fmt.tprintf("CSR 0x%03x", address)
	}
	privilege := entry.record.privilege // before the step
	if u32(privilege) < rv.csr_level(address) {
		return fmt.tprintf("%s needs privilege level %d, but the hart runs in %v mode", name, rv.csr_level(address), privilege)
	}
	if _, exists := rv.csr_read(&session.machine.cpu, address); !exists {
		return fmt.tprintf("%s is not implemented", name)
	}
	if rv.csr_is_read_only(address) {
		return fmt.tprintf("%s is read-only (address bits 11:10 = 11), and this instruction writes it", name)
	}
	return fmt.tprintf("%s can't be accessed this way", name)
}

// ECALL / EBREAK (trap into the handler) and MRET / SRET (return from it).
@(private)
system_call_text :: proc(entry: state.Timeline_Entry) -> string {
	switch entry.instruction {
	case rv.ENCODING_MRET:
		return fmt.tprintf("return from the trap handler: pc = mepc = 0x%x, MIE = MPIE, privilege = MPP", entry.next_pc)
	case rv.ENCODING_SRET:
		return fmt.tprintf("return from the supervisor trap handler: pc = sepc = 0x%x, SIE = SPIE, privilege = SPP", entry.next_pc)
	}
	if trap, took_trap := entry.trap.?; took_trap {
		if entry.stops {
			return fmt.tprintf("raises %v; no handler is set up (its trap vector's base = 0)", trap.cause)
		}
		if entry.record.trap_to_supervisor {
			return fmt.tprintf("raises %v; medeleg delegates it, so supervisor mode's handler (stvec) at 0x%x runs", trap.cause, entry.next_pc)
		}
		return fmt.tprintf("raises %v; mtvec is set, so the handler at 0x%x runs", trap.cause, entry.next_pc)
	}
	return "?"
}
