package rv

import "core:fmt"

// Disassembler: turns instruction bits back into assembly text.
//
// The output matches `objdump -d -M no-aliases` (canonical instructions,
// ABI register names), with one space instead of objdump's tab after the
// mnemonic. That way `make test` can diff it against objdump's listing.
// Number styles also follow objdump:
//   - ordinary immediates and offsets: signed decimal     addi a0,zero,-1
//   - shift amounts and LUI/AUIPC fields: hex             slli t0,t0,0x1f
//   - branch and jump targets: absolute address in hex    bne t2,t3,80000154
//   - CSRs by name, or in hex if unnamed here             csrrs t0,mhartid,zero
//   - anything that isn't a valid instruction: raw data   .word 0xffffffff
//
// The text is written into `buffer`; the returned string points into it.
// 64 bytes is always enough.
DISASM_BUFFER_SIZE :: 64

disassemble :: proc(buffer: []u8, pc: u64, instruction: u32) -> string {
	d := register_name(rd(instruction))
	s1 := register_name(rs1(instruction))
	s2 := register_name(rs2(instruction))

	switch opcode(instruction) {
	case OPCODE_LUI:
		return fmt.bprintf(buffer, "lui %s,0x%x", d, instruction >> 12)
	case OPCODE_AUIPC:
		return fmt.bprintf(buffer, "auipc %s,0x%x", d, instruction >> 12)
	case OPCODE_JAL:
		return fmt.bprintf(buffer, "jal %s,%x", d, pc + imm_j(instruction))
	case OPCODE_JALR:
		if funct3(instruction) == 0 {
			return fmt.bprintf(buffer, "jalr %s,%d(%s)", d, i64(imm_i(instruction)), s1)
		}
	case OPCODE_BRANCH:
		if name := branch_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%x", name, s1, s2, pc + imm_b(instruction))
		}
	case OPCODE_LOAD:
		if name := load_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%d(%s)", name, d, i64(imm_i(instruction)), s1)
		}
	case OPCODE_STORE:
		if name := store_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%d(%s)", name, s2, i64(imm_s(instruction)), s1)
		}
	case OPCODE_OP_IMM:
		if name := op_imm_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%d", name, d, s1, i64(imm_i(instruction)))
		}
		if name := shift_imm_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,0x%x", name, d, s1, (instruction >> 20) & 0x3F)
		}
	case OPCODE_OP_IMM_32:
		if funct3(instruction) == 0b000 {
			return fmt.bprintf(buffer, "addiw %s,%s,%d", d, s1, i64(imm_i(instruction)))
		}
		if name := shift_imm_32_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,0x%x", name, d, s1, rs2(instruction))
		}
	case OPCODE_OP:
		if name := op_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, s1, s2)
		}
	case OPCODE_OP_32:
		if name := op_32_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, s1, s2)
		}
	case OPCODE_MISC_MEM:
		switch funct3(instruction) {
		case 0b000:
			predecessor, successor: [4]u8
			return fmt.bprintf(
				buffer,
				"fence %s,%s",
				fence_set_text(instruction >> 24, &predecessor),
				fence_set_text(instruction >> 20, &successor),
			)
		case 0b001:
			return fmt.bprintf(buffer, "fence.i")
		}
	case OPCODE_SYSTEM:
		if name := zicsr_mnemonic(instruction); name != "" {
			csr_buffer: [8]u8
			csr := csr_text(csr_address(instruction), csr_buffer[:])
			if funct3(instruction) & 0b100 != 0 {
				return fmt.bprintf(buffer, "%s %s,%s,%d", name, d, csr, rs1(instruction))
			}
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, csr, s1)
		}
		switch instruction {
		case ENCODING_ECALL:
			return fmt.bprintf(buffer, "ecall")
		case ENCODING_EBREAK:
			return fmt.bprintf(buffer, "ebreak")
		case ENCODING_MRET:
			return fmt.bprintf(buffer, "mret")
		}
	}
	return fmt.bprintf(buffer, ".word 0x%08x", instruction)
}

// The mnemonic helpers below return "" for encodings that don't exist;
// they mirror the decode checks in the rv64i_*.odin handlers.

@(private = "file")
branch_mnemonic :: proc(instruction: u32) -> string {
	switch funct3(instruction) {
	case 0b000: return "beq"
	case 0b001: return "bne"
	case 0b100: return "blt"
	case 0b101: return "bge"
	case 0b110: return "bltu"
	case 0b111: return "bgeu"
	}
	return ""
}

@(private = "file")
load_mnemonic :: proc(instruction: u32) -> string {
	switch funct3(instruction) {
	case 0b000: return "lb"
	case 0b001: return "lh"
	case 0b010: return "lw"
	case 0b011: return "ld"
	case 0b100: return "lbu"
	case 0b101: return "lhu"
	case 0b110: return "lwu"
	}
	return ""
}

@(private = "file")
store_mnemonic :: proc(instruction: u32) -> string {
	switch funct3(instruction) {
	case 0b000: return "sb"
	case 0b001: return "sh"
	case 0b010: return "sw"
	case 0b011: return "sd"
	}
	return ""
}

// OP-IMM instructions with a normal 12-bit immediate (not the shifts).
@(private = "file")
op_imm_mnemonic :: proc(instruction: u32) -> string {
	switch funct3(instruction) {
	case 0b000: return "addi"
	case 0b010: return "slti"
	case 0b011: return "sltiu"
	case 0b100: return "xori"
	case 0b110: return "ori"
	case 0b111: return "andi"
	}
	return ""
}

// SLLI / SRLI / SRAI: bits 31..26 pick the kind, bits 25..20 are the amount.
@(private = "file")
shift_imm_mnemonic :: proc(instruction: u32) -> string {
	shift_type := instruction >> 26
	switch funct3(instruction) {
	case 0b001:
		if shift_type == 0b00_0000 { return "slli" }
	case 0b101:
		if shift_type == 0b00_0000 { return "srli" }
		if shift_type == 0b01_0000 { return "srai" }
	}
	return ""
}

@(private = "file")
shift_imm_32_mnemonic :: proc(instruction: u32) -> string {
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b001: return "slliw"
	case (FUNCT7_BASE << 3) | 0b101: return "srliw"
	case (FUNCT7_ALT << 3) | 0b101: return "sraiw"
	}
	return ""
}

@(private = "file")
op_mnemonic :: proc(instruction: u32) -> string {
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b000: return "add"
	case (FUNCT7_ALT << 3) | 0b000: return "sub"
	case (FUNCT7_BASE << 3) | 0b001: return "sll"
	case (FUNCT7_BASE << 3) | 0b010: return "slt"
	case (FUNCT7_BASE << 3) | 0b011: return "sltu"
	case (FUNCT7_BASE << 3) | 0b100: return "xor"
	case (FUNCT7_BASE << 3) | 0b101: return "srl"
	case (FUNCT7_ALT << 3) | 0b101: return "sra"
	case (FUNCT7_BASE << 3) | 0b110: return "or"
	case (FUNCT7_BASE << 3) | 0b111: return "and"
	case (FUNCT7_MULDIV << 3) | 0b000: return "mul"
	case (FUNCT7_MULDIV << 3) | 0b001: return "mulh"
	case (FUNCT7_MULDIV << 3) | 0b010: return "mulhsu"
	case (FUNCT7_MULDIV << 3) | 0b011: return "mulhu"
	case (FUNCT7_MULDIV << 3) | 0b100: return "div"
	case (FUNCT7_MULDIV << 3) | 0b101: return "divu"
	case (FUNCT7_MULDIV << 3) | 0b110: return "rem"
	case (FUNCT7_MULDIV << 3) | 0b111: return "remu"
	}
	return ""
}

@(private = "file")
op_32_mnemonic :: proc(instruction: u32) -> string {
	switch (funct7(instruction) << 3) | funct3(instruction) {
	case (FUNCT7_BASE << 3) | 0b000: return "addw"
	case (FUNCT7_ALT << 3) | 0b000: return "subw"
	case (FUNCT7_BASE << 3) | 0b001: return "sllw"
	case (FUNCT7_BASE << 3) | 0b101: return "srlw"
	case (FUNCT7_ALT << 3) | 0b101: return "sraw"
	case (FUNCT7_MULDIV << 3) | 0b000: return "mulw"
	case (FUNCT7_MULDIV << 3) | 0b100: return "divw"
	case (FUNCT7_MULDIV << 3) | 0b101: return "divuw"
	case (FUNCT7_MULDIV << 3) | 0b110: return "remw"
	case (FUNCT7_MULDIV << 3) | 0b111: return "remuw"
	}
	return ""
}

@(private = "file")
zicsr_mnemonic :: proc(instruction: u32) -> string {
	switch funct3(instruction) {
	case ZICSR_CSRRW: return "csrrw"
	case ZICSR_CSRRS: return "csrrs"
	case ZICSR_CSRRC: return "csrrc"
	case ZICSR_CSRRWI: return "csrrwi"
	case ZICSR_CSRRSI: return "csrrsi"
	case ZICSR_CSRRCI: return "csrrci"
	}
	return ""
}

// A CSR's name, or its address in hex (e.g. "0x7c0") if it has none here.
@(private = "file")
csr_text :: proc(address: u32, storage: []u8) -> string {
	if name := csr_name(address); name != "" {
		return name
	}
	return fmt.bprintf(storage, "0x%x", address)
}

// FENCE ordering sets: 4 bits = device Input, device Output, memory Read,
// memory Write. Prints e.g. "iorw" or "rw"; "0" for the empty set.
@(private = "file")
fence_set_text :: proc(bits: u32, storage: ^[4]u8) -> string {
	letters := "iorw"
	count := 0
	for i in 0 ..< 4 {
		if bits & (0b1000 >> u32(i)) != 0 {
			storage[count] = letters[i]
			count += 1
		}
	}
	if count == 0 {
		return "0"
	}
	return string(storage[:count])
}
