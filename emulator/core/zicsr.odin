package rv

// Zicsr: the six instructions that read and write CSRs. All are I-type
// under the SYSTEM opcode, with the 12-bit immediate holding the CSR
// address:
//
//   funct3  instruction          new CSR value      source
//   001     CSRRW  rd, csr, rs1  rs1                register
//   010     CSRRS  rd, csr, rs1  csr | rs1          register
//   011     CSRRC  rd, csr, rs1  csr & ~rs1         register
//   101     CSRRWI rd, csr, uimm uimm               5-bit immediate (rs1 field)
//   110     CSRRSI rd, csr, uimm csr | uimm
//   111     CSRRCI rd, csr, uimm csr & ~uimm
//
// Each one puts the CSR's old value in rd. Two details from the spec
// matter because reads and writes can have side effects:
//   - CSRRW / CSRRWI with rd = x0 don't read the CSR at all.
//   - CSRRS / CSRRC with rs1 = x0 (or the I forms with uimm = 0) don't
//     write it, so they can read a read-only CSR. This is `csrr`.
//
// Accessing a CSR that doesn't exist or needs more privilege, or writing
// a read-only one, raises Illegal_Instruction and changes nothing.

ZICSR_CSRRW :: 0b001
ZICSR_CSRRS :: 0b010
ZICSR_CSRRC :: 0b011
ZICSR_CSRRWI :: 0b101
ZICSR_CSRRSI :: 0b110
ZICSR_CSRRCI :: 0b111

// The CSR address: the instruction's top 12 bits, not sign-extended.
csr_address :: #force_inline proc(instruction: u32) -> u32 {
	return instruction >> 20
}

exec_zicsr :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	kind := funct3(instruction)
	address := csr_address(instruction)
	destination := rd(instruction)
	source_index := rs1(instruction)

	// Too little privilege for this CSR: illegal, read or write.
	if !csr_allowed(cpu, address) {
		return illegal_instruction(instruction)
	}

	// The value to write: a register, or the rs1 field itself as a 5-bit
	// unsigned immediate for the I forms (funct3 bit 2 set).
	uses_immediate := kind & 0b100 != 0
	source := u64(source_index) if uses_immediate else reg_read(cpu, source_index)

	// Read the old value, except for CSRRW(I) with rd = x0 (no read).
	// csr_read has no side effects, so reading it anyway for undo is safe;
	// what matters is that a missing CSR is still detected by the write.
	old, readable := csr_read(cpu, address)
	is_swap := kind == ZICSR_CSRRW || kind == ZICSR_CSRRWI
	if !readable && !(is_swap && destination == 0) {
		return illegal_instruction(instruction)
	}

	new_value: u64
	writes := true
	switch kind {
	case ZICSR_CSRRW, ZICSR_CSRRWI:
		new_value = source
	case ZICSR_CSRRS, ZICSR_CSRRSI:
		new_value = old | source
		writes = source_index != 0
	case ZICSR_CSRRC, ZICSR_CSRRCI:
		new_value = old & ~source
		writes = source_index != 0
	case:
		return illegal_instruction(instruction) // funct3 = 100 is reserved
	}

	// The old value goes into the undo record first; csr_write applies the
	// CSR's own rules (WARL fix-ups, and for mcycle, moving clock_offset
	// so the step clock doesn't jump: csr.odin). A read-only CSR refuses
	// the write: illegal, and nothing to undo.
	if writes {
		when DEBUG_RECORD_STEPS {
			cpu.undo.csr_changed = true
			cpu.undo.csr_address = address
			cpu.undo.csr_old = old
		}
		if !csr_write(cpu, address, new_value) {
			when DEBUG_RECORD_STEPS {
				cpu.undo.csr_changed = false
			}
			return illegal_instruction(instruction)
		}
	}
	// rd gets the value from before the write (reg_write drops it for x0).
	reg_write(cpu, destination, old)
	return nil
}
