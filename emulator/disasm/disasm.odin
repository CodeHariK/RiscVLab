package disasm

import "core:fmt"
import rv "../core"

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
BUFFER_SIZE :: 64

disassemble :: proc(buffer: []u8, pc: u64, instruction: u32) -> string {
	d := register_name(rv.rd(instruction))
	s1 := register_name(rv.rs1(instruction))
	s2 := register_name(rv.rs2(instruction))

	switch rv.opcode(instruction) {
	case rv.OPCODE_LUI:
		return fmt.bprintf(buffer, "lui %s,0x%x", d, instruction >> 12)
	case rv.OPCODE_AUIPC:
		return fmt.bprintf(buffer, "auipc %s,0x%x", d, instruction >> 12)
	case rv.OPCODE_JAL:
		return fmt.bprintf(buffer, "jal %s,%x", d, pc + rv.imm_j(instruction))
	case rv.OPCODE_JALR:
		if rv.funct3(instruction) == 0 {
			return fmt.bprintf(buffer, "jalr %s,%d(%s)", d, i64(rv.imm_i(instruction)), s1)
		}
	case rv.OPCODE_BRANCH:
		if name := branch_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%x", name, s1, s2, pc + rv.imm_b(instruction))
		}
	case rv.OPCODE_LOAD:
		if name := load_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%d(%s)", name, d, i64(rv.imm_i(instruction)), s1)
		}
	case rv.OPCODE_STORE:
		if name := store_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%d(%s)", name, s2, i64(rv.imm_s(instruction)), s1)
		}
	case rv.OPCODE_OP_IMM:
		if name := op_imm_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%d", name, d, s1, i64(rv.imm_i(instruction)))
		}
		if name := shift_imm_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,0x%x", name, d, s1, (instruction >> 20) & 0x3F)
		}
	case rv.OPCODE_OP_IMM_32:
		if rv.funct3(instruction) == 0b000 {
			return fmt.bprintf(buffer, "addiw %s,%s,%d", d, s1, i64(rv.imm_i(instruction)))
		}
		if name := shift_imm_32_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,0x%x", name, d, s1, rv.rs2(instruction))
		}
	case rv.OPCODE_OP:
		if name := op_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, s1, s2)
		}
	case rv.OPCODE_OP_32:
		if name := op_32_mnemonic(instruction); name != "" {
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, s1, s2)
		}
	case rv.OPCODE_MISC_MEM:
		switch rv.funct3(instruction) {
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
	case rv.OPCODE_AMO:
		if name := amo_mnemonic(instruction); name != "" {
			order := amo_order_suffix(instruction)
			switch rv.funct5(instruction) {
			case rv.AMO_LR:
				return fmt.bprintf(buffer, "%s%s %s,(%s)", name, order, d, s1)
			case:
				return fmt.bprintf(buffer, "%s%s %s,%s,(%s)", name, order, d, s2, s1)
			}
		}
	case rv.OPCODE_SYSTEM:
		if name := zicsr_mnemonic(instruction); name != "" {
			csr_buffer: [8]u8
			csr := csr_text(rv.csr_address(instruction), csr_buffer[:])
			if rv.funct3(instruction) & 0b100 != 0 {
				return fmt.bprintf(buffer, "%s %s,%s,%d", name, d, csr, rv.rs1(instruction))
			}
			return fmt.bprintf(buffer, "%s %s,%s,%s", name, d, csr, s1)
		}
		switch instruction {
		case rv.ENCODING_ECALL:
			return fmt.bprintf(buffer, "ecall")
		case rv.ENCODING_EBREAK:
			return fmt.bprintf(buffer, "ebreak")
		case rv.ENCODING_MRET:
			return fmt.bprintf(buffer, "mret")
		}
	}
	return fmt.bprintf(buffer, ".word 0x%08x", instruction)
}

// The mnemonic helpers below return "" for encodings that don't exist;
// they mirror the decode checks in the rv64i_*.odin handlers.

@(private = "file")
branch_mnemonic :: proc(instruction: u32) -> string {
	switch rv.funct3(instruction) {
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
	switch rv.funct3(instruction) {
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
	switch rv.funct3(instruction) {
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
	switch rv.funct3(instruction) {
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
	switch rv.funct3(instruction) {
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
	switch (rv.funct7(instruction) << 3) | rv.funct3(instruction) {
	case (rv.FUNCT7_BASE << 3) | 0b001: return "slliw"
	case (rv.FUNCT7_BASE << 3) | 0b101: return "srliw"
	case (rv.FUNCT7_ALT << 3) | 0b101: return "sraiw"
	}
	return ""
}

@(private = "file")
op_mnemonic :: proc(instruction: u32) -> string {
	switch (rv.funct7(instruction) << 3) | rv.funct3(instruction) {
	case (rv.FUNCT7_BASE << 3) | 0b000: return "add"
	case (rv.FUNCT7_ALT << 3) | 0b000: return "sub"
	case (rv.FUNCT7_BASE << 3) | 0b001: return "sll"
	case (rv.FUNCT7_BASE << 3) | 0b010: return "slt"
	case (rv.FUNCT7_BASE << 3) | 0b011: return "sltu"
	case (rv.FUNCT7_BASE << 3) | 0b100: return "xor"
	case (rv.FUNCT7_BASE << 3) | 0b101: return "srl"
	case (rv.FUNCT7_ALT << 3) | 0b101: return "sra"
	case (rv.FUNCT7_BASE << 3) | 0b110: return "or"
	case (rv.FUNCT7_BASE << 3) | 0b111: return "and"
	case (rv.FUNCT7_MULDIV << 3) | 0b000: return "mul"
	case (rv.FUNCT7_MULDIV << 3) | 0b001: return "mulh"
	case (rv.FUNCT7_MULDIV << 3) | 0b010: return "mulhsu"
	case (rv.FUNCT7_MULDIV << 3) | 0b011: return "mulhu"
	case (rv.FUNCT7_MULDIV << 3) | 0b100: return "div"
	case (rv.FUNCT7_MULDIV << 3) | 0b101: return "divu"
	case (rv.FUNCT7_MULDIV << 3) | 0b110: return "rem"
	case (rv.FUNCT7_MULDIV << 3) | 0b111: return "remu"
	}
	return ""
}

@(private = "file")
op_32_mnemonic :: proc(instruction: u32) -> string {
	switch (rv.funct7(instruction) << 3) | rv.funct3(instruction) {
	case (rv.FUNCT7_BASE << 3) | 0b000: return "addw"
	case (rv.FUNCT7_ALT << 3) | 0b000: return "subw"
	case (rv.FUNCT7_BASE << 3) | 0b001: return "sllw"
	case (rv.FUNCT7_BASE << 3) | 0b101: return "srlw"
	case (rv.FUNCT7_ALT << 3) | 0b101: return "sraw"
	case (rv.FUNCT7_MULDIV << 3) | 0b000: return "mulw"
	case (rv.FUNCT7_MULDIV << 3) | 0b100: return "divw"
	case (rv.FUNCT7_MULDIV << 3) | 0b101: return "divuw"
	case (rv.FUNCT7_MULDIV << 3) | 0b110: return "remw"
	case (rv.FUNCT7_MULDIV << 3) | 0b111: return "remuw"
	}
	return ""
}

// "amoadd.w", "lr.d", ...; "" if it doesn't exist (LR with rs2 != 0
// included).
@(private = "file")
amo_mnemonic :: proc(instruction: u32) -> string {
	word := rv.funct3(instruction) == rv.AMO_WORD
	if !word && rv.funct3(instruction) != rv.AMO_DOUBLE {
		return ""
	}
	switch rv.funct5(instruction) {
	case rv.AMO_LR:
		if rv.rs2(instruction) != 0 {
			return ""
		}
		return "lr.w" if word else "lr.d"
	case rv.AMO_SC: return "sc.w" if word else "sc.d"
	case rv.AMO_SWAP: return "amoswap.w" if word else "amoswap.d"
	case rv.AMO_ADD: return "amoadd.w" if word else "amoadd.d"
	case rv.AMO_XOR: return "amoxor.w" if word else "amoxor.d"
	case rv.AMO_AND: return "amoand.w" if word else "amoand.d"
	case rv.AMO_OR: return "amoor.w" if word else "amoor.d"
	case rv.AMO_MIN: return "amomin.w" if word else "amomin.d"
	case rv.AMO_MAX: return "amomax.w" if word else "amomax.d"
	case rv.AMO_MINU: return "amominu.w" if word else "amominu.d"
	case rv.AMO_MAXU: return "amomaxu.w" if word else "amomaxu.d"
	}
	return ""
}

// The ordering bits as objdump writes them: ".aq", ".rl", ".aqrl" or "".
@(private = "file")
amo_order_suffix :: proc(instruction: u32) -> string {
	acquire := (instruction >> 26) & 1 != 0
	release := (instruction >> 25) & 1 != 0
	switch {
	case acquire && release: return ".aqrl"
	case acquire: return ".aq"
	case release: return ".rl"
	}
	return ""
}

@(private = "file")
zicsr_mnemonic :: proc(instruction: u32) -> string {
	switch rv.funct3(instruction) {
	case rv.ZICSR_CSRRW: return "csrrw"
	case rv.ZICSR_CSRRS: return "csrrs"
	case rv.ZICSR_CSRRC: return "csrrc"
	case rv.ZICSR_CSRRWI: return "csrrwi"
	case rv.ZICSR_CSRRSI: return "csrrsi"
	case rv.ZICSR_CSRRCI: return "csrrci"
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
