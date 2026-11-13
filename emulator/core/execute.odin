package rv

// Major opcodes (instruction bits 6..0), from the "RV32/64G Instruction Set
// Listings" chapter of the unprivileged spec.
OPCODE_LOAD :: 0b000_0011
OPCODE_MISC_MEM :: 0b000_1111
OPCODE_OP_IMM :: 0b001_0011
OPCODE_AUIPC :: 0b001_0111
OPCODE_OP_IMM_32 :: 0b001_1011
OPCODE_STORE :: 0b010_0011
OPCODE_OP :: 0b011_0011
OPCODE_LUI :: 0b011_0111
OPCODE_OP_32 :: 0b011_1011
OPCODE_BRANCH :: 0b110_0011
OPCODE_JALR :: 0b110_0111
OPCODE_JAL :: 0b110_1111
OPCODE_SYSTEM :: 0b111_0011

INSTRUCTION_SIZE :: u64(4)

// Fetches, decodes and executes one instruction.
//
// On success the PC moves to `next_pc` and `instret` counts the
// instruction. On a trap the PC stays on the faulting instruction, which is
// where `mepc` must point once trap handling exists.
cpu_step :: proc(cpu: ^Cpu, bus: ^Bus) -> Step_Result {
	cpu.last_write = {}

	raw, fetched := bus_load(bus, cpu.pc, 4)
	if !fetched {
		return trap_make(.Instruction_Access_Fault, cpu.pc)
	}
	instruction := u32(raw)

	cpu.next_pc = cpu.pc + INSTRUCTION_SIZE
	if trap, has_trap := execute(cpu, bus, instruction).?; has_trap {
		return trap
	}

	cpu.pc = cpu.next_pc
	cpu.instret += 1
	return nil
}

// Sends the instruction to the handler for its major opcode.
// Each handler lives in the file for its instruction group.
@(private = "file")
execute :: proc(cpu: ^Cpu, bus: ^Bus, instruction: u32) -> Step_Result {
	switch opcode(instruction) {
	case OPCODE_LUI:
		return exec_lui(cpu, instruction)
	case OPCODE_AUIPC:
		return exec_auipc(cpu, instruction)
	case OPCODE_JAL:
		return exec_jal(cpu, instruction)
	case OPCODE_JALR:
		return exec_jalr(cpu, instruction)
	case OPCODE_BRANCH:
		return exec_branch(cpu, instruction)
	case OPCODE_LOAD:
		return exec_load(cpu, bus, instruction)
	case OPCODE_STORE:
		return exec_store(cpu, bus, instruction)
	case OPCODE_OP_IMM:
		return exec_op_imm(cpu, instruction)
	case OPCODE_OP:
		return exec_op(cpu, instruction)
	case OPCODE_OP_IMM_32:
		return exec_op_imm_32(cpu, instruction)
	case OPCODE_OP_32:
		return exec_op_32(cpu, instruction)
	case OPCODE_MISC_MEM:
		return exec_misc_mem(instruction)
	case OPCODE_SYSTEM:
		return exec_system(instruction)
	}
	return illegal_instruction(instruction)
}
