package rvdbg

import "core:fmt"
import "core:strings"
import rv "../core"

// The execute stage of the detailed step view (step_detail.odin): the
// arithmetic, address or decision the instruction made, written with the
// values it used, e.g.
//
//   t1 0x3 (3) != zero 0x0 -> taken: target = pc 0x80000020 + -0x10 = 0x80000010
//   address = t0 0x80001000 + 0x0 = 0x80001000 (numbers)

execute_text :: proc(session: ^Session, entry: Timeline_Entry) -> string {
	instruction := entry.instruction
	mnemonic := step_mnemonic(entry)
	pc := entry.pc
	a, b := entry.rs1_value, entry.rs2_value
	s1 := rv.register_name(rv.rs1(instruction))
	s2 := rv.register_name(rv.rs2(instruction))
	result := result_text(entry)

	switch rv.opcode(instruction) {
	case rv.OPCODE_LUI:
		return fmt.tprintf("0x%x << 12 = %s", instruction >> 12, result)
	case rv.OPCODE_AUIPC:
		return fmt.tprintf("pc 0x%x + (0x%x << 12) = %s", pc, instruction >> 12, result)
	case rv.OPCODE_JAL:
		offset := rv.imm_j(instruction)
		return fmt.tprintf(
			"target = pc 0x%x + %s = 0x%x%s; return address = pc + 4 = 0x%x",
			pc,
			signed_text(i64(offset)),
			pc + offset,
			symbol_label(session, pc + offset),
			pc + rv.INSTRUCTION_SIZE,
		)
	case rv.OPCODE_JALR:
		target := (a + rv.imm_i(instruction)) & ~u64(1)
		return fmt.tprintf(
			"target = (%s 0x%x + %s) & ~1 = 0x%x%s; return address = pc + 4 = 0x%x",
			s1,
			a,
			signed_text(i64(rv.imm_i(instruction))),
			target,
			symbol_label(session, target),
			pc + rv.INSTRUCTION_SIZE,
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
				symbol_label(session, pc + offset),
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
			symbol_label(session, address),
		)
	case rv.OPCODE_STORE:
		address := a + rv.imm_s(instruction)
		return fmt.tprintf(
			"address = %s 0x%x + %s = 0x%x%s",
			s1,
			a,
			signed_text(i64(rv.imm_s(instruction))),
			address,
			symbol_label(session, address),
		)
	case rv.OPCODE_OP_IMM, rv.OPCODE_OP_IMM_32:
		operand := signed_text(i64(rv.imm_i(instruction)))
		if is_shift(mnemonic) {
			shift_mask: u32 = 0x3F if rv.opcode(instruction) == rv.OPCODE_OP_IMM else 0x1F
			operand = value_text(u64((instruction >> 20) & shift_mask))
		}
		return arithmetic_text(mnemonic, s1, a, operand, result)
	case rv.OPCODE_OP, rv.OPCODE_OP_32:
		return arithmetic_text(mnemonic, s1, a, fmt.tprintf("%s %s", s2, value_text(b)), result)
	case rv.OPCODE_MISC_MEM:
		return "fence: orders memory accesses; nothing to do on one in-order hart"
	case rv.OPCODE_SYSTEM:
		if rv.funct3(instruction) != 0 {
			return csr_execute_text(entry, mnemonic, s1)
		}
		return system_call_text(entry)
	}
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("unknown encoding: raises %v (mtval = 0x%x)", trap.cause, trap.value)
	}
	return "?"
}

// The value written to rd, or why there isn't one.
@(private = "file")
result_text :: proc(entry: Timeline_Entry) -> string {
	if entry.record.register_changed {
		return value_text(entry.register_new)
	}
	return "(dropped: rd is zero)"
}

// ADD / SUB / AND / shifts / SLT and their I and W forms.
@(private = "file")
arithmetic_text :: proc(mnemonic: string, s1: string, a: u64, operand: string, result: string) -> string {
	if strings.has_prefix(mnemonic, "slt") {
		kind := "unsigned" if strings.has_suffix(mnemonic, "u") else "signed"
		return fmt.tprintf("is %s %s < %s (%s)? -> %s", s1, value_text(a), operand, kind, result)
	}
	return fmt.tprintf("%s %s %s %s = %s%s", s1, value_text(a), operator(mnemonic), operand, result, word_note(mnemonic))
}

// CSRRW / CSRRS / CSRRC (and the immediate forms): the new value worked
// out from the old one, and what the CSR kept.
@(private = "file")
csr_execute_text :: proc(entry: Timeline_Entry, mnemonic: string, s1: string) -> string {
	instruction := entry.instruction
	csr := rv.csr_name(rv.csr_address(instruction))
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf("CSR 0x%03x is not implemented: raises %v", rv.csr_address(instruction), trap.cause)
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

// ECALL / EBREAK (trap into the handler) and MRET (return from it).
@(private = "file")
system_call_text :: proc(entry: Timeline_Entry) -> string {
	switch entry.instruction {
	case rv.ENCODING_MRET:
		return "return from the trap handler: pc = mepc, MIE = MPIE, privilege = MPP"
	}
	if trap, took_trap := entry.trap.?; took_trap {
		if entry.stops {
			return fmt.tprintf("raises %v; no handler is set up (mtvec = 0)", trap.cause)
		}
		return fmt.tprintf("raises %v; mtvec = 0x%x is set, so the handler runs", trap.cause, entry.next_pc)
	}
	return "?"
}
