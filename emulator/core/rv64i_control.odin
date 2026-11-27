package rv

// Control transfer: JAL, JALR and the conditional branches.

// Moves execution to `target`. Without the C extension every instruction
// is 4 bytes, so a target that isn't 4-byte aligned raises a trap.
@(private = "file")
jump_to :: proc(cpu: ^Cpu, target: u64) -> Step_Result {
	if target & 0b11 != 0 {
		return trap_make(.Instruction_Address_Misaligned, target)
	}
	cpu.next_pc = target
	return nil
}

// JAL rd, offset: rd = pc + 4; pc += offset.
exec_jal :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Jal)
	}
	target := cpu.pc + imm_j(instruction)
	if trap := jump_to(cpu, target); trap != nil {
		return trap
	}
	reg_write(cpu, rd(instruction), cpu.pc + INSTRUCTION_SIZE)
	return nil
}

// JALR rd, offset(rs1): rd = pc + 4; pc = (rs1 + offset) with bit 0 cleared.
// The target is computed before writing rd, because rd may equal rs1.
exec_jalr :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Jalr)
	}
	if funct3(instruction) != 0 {
		return illegal_instruction(instruction)
	}
	target := (reg_read(cpu, rs1(instruction)) + imm_i(instruction)) & ~u64(1)
	if trap := jump_to(cpu, target); trap != nil {
		return trap
	}
	reg_write(cpu, rd(instruction), cpu.pc + INSTRUCTION_SIZE)
	return nil
}

// BEQ / BNE / BLT / BGE / BLTU / BGEU rs1, rs2, offset.
// If the comparison holds, pc += offset.
exec_branch :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	when DEBUG_RECORD_STEPS {
		step_path_push(cpu, .Exec_Branch)
	}
	a := reg_read(cpu, rs1(instruction))
	b := reg_read(cpu, rs2(instruction))

	taken: bool
	switch funct3(instruction) {
	case 0b000:
		taken = a == b // BEQ
	case 0b001:
		taken = a != b // BNE
	case 0b100:
		taken = i64(a) < i64(b) // BLT
	case 0b101:
		taken = i64(a) >= i64(b) // BGE
	case 0b110:
		taken = a < b // BLTU
	case 0b111:
		taken = a >= b // BGEU
	case:
		return illegal_instruction(instruction)
	}

	if !taken {
		return nil
	}
	return jump_to(cpu, cpu.pc + imm_b(instruction))
}
