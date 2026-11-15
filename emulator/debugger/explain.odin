package rvdbg

import "core:fmt"
import "core:strings"
import rv "../core"

// Plain-language text for the explanation panel. All strings are
// allocated with the temp allocator, which is freed after each frame.

// What the instruction at the PC is about to do, using the current
// register values. Written before it runs, so results are left out;
// the "Last step" line shows them after Next.
explain_next :: proc(session: ^Session) -> string {
	cpu := &session.machine.cpu
	pc := cpu.pc
	raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
	if !ok {
		return fmt.tprintf("pc 0x%x is outside memory: fetching will raise Instruction_Access_Fault", pc)
	}
	instruction := u32(raw)

	buffer: [rv.DISASM_BUFFER_SIZE]u8
	text := rv.disassemble(buffer[:], pc, instruction)
	mnemonic := strings.clone(first_word(text), context.temp_allocator)

	d := rv.register_name(rv.rd(instruction))
	s1 := rv.register_name(rv.rs1(instruction))
	s2 := rv.register_name(rv.rs2(instruction))
	v1 := rv.reg_read(cpu, rv.rs1(instruction))
	v2 := rv.reg_read(cpu, rv.rs2(instruction))

	switch rv.opcode(instruction) {
	case rv.OPCODE_LUI:
		return fmt.tprintf("%s = 0x%x << 12 (load upper immediate)", d, instruction >> 12)
	case rv.OPCODE_AUIPC:
		return fmt.tprintf(
			"%s = pc + (0x%x << 12) = 0x%x (address relative to this instruction)",
			d,
			instruction >> 12,
			pc + rv.imm_u(instruction),
		)
	case rv.OPCODE_JAL:
		return fmt.tprintf(
			"jump to 0x%x; %s = 0x%x (the return address)",
			pc + rv.imm_j(instruction),
			d,
			pc + rv.INSTRUCTION_SIZE,
		)
	case rv.OPCODE_JALR:
		target := (v1 + rv.imm_i(instruction)) & ~u64(1)
		return fmt.tprintf(
			"jump to %s (%s) + %s = 0x%x; %s = 0x%x (the return address)",
			s1,
			value_text(v1),
			signed_text(i64(rv.imm_i(instruction))),
			target,
			d,
			pc + rv.INSTRUCTION_SIZE,
		)
	case rv.OPCODE_BRANCH:
		comparison, taken := branch_comparison(mnemonic, v1, v2)
		return fmt.tprintf(
			"if %s (%s) %s %s (%s): jump to 0x%x. %s",
			s1,
			value_text(v1),
			comparison,
			s2,
			value_text(v2),
			pc + rv.imm_b(instruction),
			"Taken." if taken else "Not taken: continue to the next instruction.",
		)
	case rv.OPCODE_LOAD:
		address := v1 + rv.imm_i(instruction)
		size := u64(1) << (rv.funct3(instruction) & 0b11)
		extension := "zero-extended" if rv.funct3(instruction) >= 0b100 else "sign-extended"
		if size == 8 {
			extension = "all 64 bits"
		}
		loaded := "outside memory: will raise Load_Access_Fault"
		if raw_value, in_memory := rv.bus_load(&session.machine.bus, address, size); in_memory {
			loaded = fmt.tprintf("which holds %s, %s", value_text(raw_value), extension)
		}
		return fmt.tprintf(
			"%s = %d-byte load from %s (0x%x) + %s = address 0x%x, %s",
			d,
			size,
			s1,
			v1,
			signed_text(i64(rv.imm_i(instruction))),
			address,
			loaded,
		)
	case rv.OPCODE_STORE:
		address := v1 + rv.imm_s(instruction)
		size := u64(1) << (rv.funct3(instruction) & 0b11)
		return fmt.tprintf(
			"store the low %d bytes of %s (%s) to %s (0x%x) + %s = address 0x%x",
			size,
			s2,
			value_text(v2),
			s1,
			v1,
			signed_text(i64(rv.imm_s(instruction))),
			address,
		)
	case rv.OPCODE_OP_IMM, rv.OPCODE_OP_IMM_32:
		operand := signed_text(i64(rv.imm_i(instruction)))
		if is_shift(mnemonic) {
			shift_mask: u32 = 0x3F if rv.opcode(instruction) == rv.OPCODE_OP_IMM else 0x1F
			operand = value_text(u64((instruction >> 20) & shift_mask))
		}
		if strings.has_prefix(mnemonic, "slt") {
			return set_less_than_text(mnemonic, d, s1, value_text(v1), operand)
		}
		return fmt.tprintf("%s = %s (%s) %s %s%s", d, s1, value_text(v1), operator(mnemonic), operand, word_note(mnemonic))
	case rv.OPCODE_OP, rv.OPCODE_OP_32:
		if strings.has_prefix(mnemonic, "slt") {
			operand := fmt.tprintf("%s (%s)", s2, value_text(v2))
			return set_less_than_text(mnemonic, d, s1, value_text(v1), operand)
		}
		return fmt.tprintf(
			"%s = %s (%s) %s %s (%s)%s",
			d,
			s1,
			value_text(v1),
			operator(mnemonic),
			s2,
			value_text(v2),
			word_note(mnemonic),
		)
	case rv.OPCODE_MISC_MEM:
		return "memory-ordering fence: nothing to do on one in-order hart"
	case rv.OPCODE_SYSTEM:
		if rv.funct3(instruction) != 0 {
			return explain_csr_instruction(cpu, mnemonic, instruction, d, s1, v1)
		}
		switch instruction {
		case rv.ENCODING_ECALL:
			if rv.trap_has_handler(cpu) {
				return fmt.tprintf("system call: raises an environment-call trap -> handler at 0x%x", cpu.csr.mtvec &~ 0b11)
			}
			return "system call: raises an environment-call trap; no handler is set up (mtvec = 0), so the machine stops"
		case rv.ENCODING_EBREAK:
			if rv.trap_has_handler(cpu) {
				return fmt.tprintf("breakpoint: raises a breakpoint trap -> handler at 0x%x", cpu.csr.mtvec &~ 0b11)
			}
			return "breakpoint: raises a breakpoint trap; no handler is set up (mtvec = 0), so the program ends here"
		case rv.ENCODING_MRET:
			return fmt.tprintf(
				"return from trap: pc = mepc (0x%x); interrupts back to MPIE; privilege = MPP (machine)",
				cpu.csr.mepc,
			)
		}
	}
	return fmt.tprintf("unknown instruction 0x%08x: will raise Illegal_Instruction", instruction)
}

// CSRRW / CSRRS / CSRRC and their immediate forms, with the CSR's
// current value.
@(private = "file")
explain_csr_instruction :: proc(
	cpu: ^rv.Cpu,
	mnemonic: string,
	instruction: u32,
	d: string,
	s1: string,
	v1: u64,
) -> string {
	address := rv.csr_address(instruction)
	csr := rv.csr_name(address)
	if csr == "" {
		return fmt.tprintf("CSR 0x%03x is not implemented: raises Illegal_Instruction", address)
	}
	old, _ := rv.csr_read(cpu, address)

	// The value written: rs1's value, or the 5-bit immediate in the rs1 field.
	immediate_form := strings.has_suffix(mnemonic, "i")
	source := fmt.tprintf("%s (%s)", s1, value_text(v1))
	source_is_zero := rv.rs1(instruction) == 0
	if immediate_form {
		source = value_text(u64(rv.rs1(instruction)))
	}

	read := fmt.tprintf("%s = old %s (%s)", d, csr, value_text(old))
	switch mnemonic {
	case "csrrw", "csrrwi":
		if rv.rd(instruction) == 0 {
			return fmt.tprintf("%s = %s (rd is zero, so the old value isn't read)", csr, source)
		}
		return fmt.tprintf("swap: %s; %s = %s", read, csr, source)
	case "csrrs", "csrrsi":
		if source_is_zero {
			return fmt.tprintf("read: %s (nothing to set, so no write)", read)
		}
		return fmt.tprintf("%s; set bits: %s |= %s", read, csr, source)
	case "csrrc", "csrrci":
		if source_is_zero {
			return fmt.tprintf("read: %s (nothing to clear, so no write)", read)
		}
		return fmt.tprintf("%s; clear bits: %s &= ~%s", read, csr, source)
	}
	return "?"
}

// What the most recent Next changed, e.g. "t0 <- 0x5 (5)".
explain_last_step :: proc(session: ^Session) -> string {
	record, has_record := session.last_step.?
	if !has_record {
		return "-"
	}

	builder := strings.builder_make(context.temp_allocator)
	if record.trap_taken {
		csr := &session.machine.cpu.csr
		fmt.sbprintf(
			&builder,
			"trap %v: mepc <- 0x%x, mcause <- %s, mtval <- %s; jumped to the handler at 0x%x",
			rv.Trap_Cause(csr.mcause),
			csr.mepc,
			value_text(csr.mcause),
			value_text(csr.mtval),
			session.machine.cpu.pc,
		)
		return strings.to_string(builder)
	}
	if record.register_changed {
		new_value := session.machine.cpu.regs[record.register_index]
		fmt.sbprintf(
			&builder,
			"%s <- %s (was %s)",
			rv.register_name(record.register_index),
			value_text(new_value),
			value_text(record.register_old),
		)
	}
	if record.memory_changed {
		new_value, _ := rv.bus_load(&session.machine.bus, record.memory_address, record.memory_size)
		if record.register_changed {
			strings.write_string(&builder, "; ")
		}
		fmt.sbprintf(
			&builder,
			"mem[0x%x] (%d bytes) <- %s (was %s)",
			record.memory_address,
			record.memory_size,
			value_text(new_value),
			value_text(record.memory_old),
		)
	}
	if record.csr_changed {
		new_value, _ := rv.csr_read(&session.machine.cpu, record.csr_address)
		if record.register_changed || record.memory_changed {
			strings.write_string(&builder, "; ")
		}
		fmt.sbprintf(
			&builder,
			"%s <- %s (was %s)",
			rv.csr_name(record.csr_address),
			value_text(new_value),
			value_text(record.csr_old),
		)
	}
	if !record.register_changed && !record.memory_changed && !record.csr_changed {
		strings.write_string(&builder, "no register or memory changed")
	}
	return strings.to_string(builder)
}

// One-line state of the program for the status row.
explain_status :: proc(session: ^Session) -> string {
	cpu := &session.machine.cpu
	if trap, stopped := session.stopped.?; stopped {
		if trap.cause == .Breakpoint {
			return fmt.tprintf(
				"Program finished (ebreak) after %d instructions. a0 = %s",
				cpu.instret,
				value_text(rv.reg_read(cpu, rv.REG_A0)),
			)
		}
		return fmt.tprintf("Stopped: %v (value 0x%x) at pc 0x%x", trap.cause, trap.value, cpu.pc)
	}
	if exit_code, exited := session.exited.?; exited {
		if exit_code == 0 {
			return fmt.tprintf("Program finished through tohost after %d instructions: exit code 0 (pass)", cpu.instret)
		}
		return fmt.tprintf("Program finished through tohost: exit code %s (riscv-tests: test %d failed)", value_text(u64(exit_code)), exit_code)
	}
	if cpu.instret == 0 {
		return "Ready. Press Next (or the right arrow key) to run the first instruction."
	}
	return fmt.tprintf("Paused after %d instructions.", cpu.instret)
}

@(private = "file")
first_word :: proc(text: string) -> string {
	if space := strings.index_byte(text, ' '); space >= 0 {
		return text[:space]
	}
	return text
}

@(private = "file")
is_shift :: proc(mnemonic: string) -> bool {
	return strings.has_prefix(mnemonic, "sll") || strings.has_prefix(mnemonic, "srl") || strings.has_prefix(mnemonic, "sra")
}

// The *W instructions compute on 32 bits and sign-extend the result.
@(private = "file")
word_note :: proc(mnemonic: string) -> string {
	return ", on the low 32 bits, then sign-extended" if strings.has_suffix(mnemonic, "w") else ""
}

// Maps an arithmetic mnemonic (any of its I / W variants) to an operator.
@(private = "file")
operator :: proc(mnemonic: string) -> string {
	switch mnemonic {
	case "add", "addi", "addw", "addiw":
		return "+"
	case "sub", "subw":
		return "-"
	case "and", "andi":
		return "&"
	case "or", "ori":
		return "|"
	case "xor", "xori":
		return "^"
	case "sll", "slli", "sllw", "slliw":
		return "<<"
	case "srl", "srli", "srlw", "srliw":
		return ">> (logical, fills with zeros)"
	case "sra", "srai", "sraw", "sraiw":
		return ">> (arithmetic, keeps the sign)"
	}
	return "?"
}

// SLT / SLTU / SLTI / SLTIU: "rd = 1 if a < b (signed), else 0".
@(private = "file")
set_less_than_text :: proc(mnemonic: string, d: string, s1: string, v1_text: string, operand: string) -> string {
	kind := "unsigned" if strings.has_suffix(mnemonic, "u") else "signed"
	return fmt.tprintf("%s = 1 if %s (%s) < %s (%s compare), else 0", d, s1, v1_text, operand, kind)
}

// The comparison a branch makes, and whether it will be taken now.
@(private = "file")
branch_comparison :: proc(mnemonic: string, a: u64, b: u64) -> (text: string, taken: bool) {
	switch mnemonic {
	case "beq":
		return "==", a == b
	case "bne":
		return "!=", a != b
	case "blt":
		return "< (signed)", i64(a) < i64(b)
	case "bge":
		return ">= (signed)", i64(a) >= i64(b)
	case "bltu":
		return "< (unsigned)", a < b
	case "bgeu":
		return ">= (unsigned)", a >= b
	}
	return "?", false
}
