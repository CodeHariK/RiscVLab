package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import disasm "../../disasm"

// Splits an instruction into its encoding fields (opcode, rd, rs1, rs2,
// funct3/funct7, immediate pieces) for the Encoding strip, following the
// R / I / S / B / U / J formats drawn at the top of core/decode.odin.
//
// B- and J-type immediates are split into the pieces the hardware
// scatters across the word, each labelled with the immediate bits it
// holds, so the strange-looking layout can be read off directly.

// What a field is; each kind has its own colour (see Palette).
Field_Kind :: enum {
	Opcode,
	Rd,
	Rs1,
	Rs2,
	Funct,
	Immediate,
	Csr,
	Unknown,
}

Encoding_Field :: struct {
	high:  u32, // highest bit of the field (31..0)
	low:   u32, // lowest bit
	label: string,
	kind:  Field_Kind,
}

MAX_FIELDS :: 8

Encoding :: struct {
	format:      string, // "R-type", ...
	fields:      [MAX_FIELDS]Encoding_Field,
	field_count: int,
}

encoding_of :: proc(instruction: u32) -> Encoding {
	encoding: Encoding
	switch rv.opcode(instruction) {
	case rv.OPCODE_OP, rv.OPCODE_OP_32:
		r_type(&encoding)
	case rv.OPCODE_OP_IMM:
		if funct := rv.funct3(instruction); funct == 0b001 || funct == 0b101 {
			shift_immediate(&encoding, 26, "funct6") // RV64: 6-bit shift amount
		} else {
			i_type(&encoding)
		}
	case rv.OPCODE_OP_IMM_32:
		if rv.funct3(instruction) != 0b000 {
			shift_immediate(&encoding, 25, "funct7") // *W shifts: 5-bit amount
		} else {
			i_type(&encoding)
		}
	case rv.OPCODE_SYSTEM:
		if rv.funct3(instruction) != 0 {
			csr_type(&encoding, rv.funct3(instruction) & 0b100 != 0)
		} else {
			system_type(&encoding)
		}
	case rv.OPCODE_AMO:
		encoding.format = "R-type (atomic)"
		add_field(&encoding, 31, 27, "funct5", .Funct)
		add_field(&encoding, 26, 26, "aq", .Funct)
		add_field(&encoding, 25, 25, "rl", .Funct)
		add_source_registers(&encoding) // rs2, rs1, funct3 (.w = 010, .d = 011)
		add_field(&encoding, 11, 7, "rd", .Rd)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	case rv.OPCODE_LOAD, rv.OPCODE_JALR, rv.OPCODE_MISC_MEM:
		i_type(&encoding)
	case rv.OPCODE_STORE:
		encoding.format = "S-type"
		add_field(&encoding, 31, 25, "imm[11:5]", .Immediate)
		add_source_registers(&encoding)
		add_field(&encoding, 11, 7, "imm[4:0]", .Immediate)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	case rv.OPCODE_BRANCH:
		encoding.format = "B-type"
		add_field(&encoding, 31, 31, "imm[12]", .Immediate)
		add_field(&encoding, 30, 25, "imm[10:5]", .Immediate)
		add_source_registers(&encoding)
		add_field(&encoding, 11, 8, "imm[4:1]", .Immediate)
		add_field(&encoding, 7, 7, "imm[11]", .Immediate)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	case rv.OPCODE_LUI, rv.OPCODE_AUIPC:
		encoding.format = "U-type"
		add_field(&encoding, 31, 12, "imm[31:12]", .Immediate)
		add_field(&encoding, 11, 7, "rd", .Rd)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	case rv.OPCODE_JAL:
		encoding.format = "J-type"
		add_field(&encoding, 31, 31, "imm[20]", .Immediate)
		add_field(&encoding, 30, 21, "imm[10:1]", .Immediate)
		add_field(&encoding, 20, 20, "imm[11]", .Immediate)
		add_field(&encoding, 19, 12, "imm[19:12]", .Immediate)
		add_field(&encoding, 11, 7, "rd", .Rd)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	case:
		encoding.format = "unknown"
		add_field(&encoding, 31, 7, "?", .Unknown)
		add_field(&encoding, 6, 0, "opcode", .Opcode)
	}
	return encoding
}

// The field's bits, as a number.
field_value :: proc(instruction: u32, field: Encoding_Field) -> u32 {
	width := field.high - field.low + 1
	mask := u32((u64(1) << width) - 1)
	return (instruction >> field.low) & mask
}

// The field's bits as a binary string, e.g. "00101".
field_bits_text :: proc(instruction: u32, field: Encoding_Field) -> string {
	builder := strings.builder_make(context.temp_allocator)
	for bit := int(field.high); bit >= int(field.low); bit -= 1 {
		digit: u8 = '1' if (instruction >> u32(bit)) & 1 != 0 else '0'
		strings.write_byte(&builder, digit)
	}
	return strings.to_string(builder)
}

// What the field means: register name, opcode name, or the number.
field_value_text :: proc(instruction: u32, field: Encoding_Field) -> string {
	value := field_value(instruction, field)
	switch field.kind {
	case .Opcode:
		return fmt.tprintf("%s (0x%02x)", opcode_name(value), value)
	case .Rd, .Rs1, .Rs2:
		return fmt.tprintf("%s (x%d)", disasm.register_name(value), value)
	case .Csr:
		if name := disasm.csr_name(value); name != "" {
			return name
		}
		return "not implemented"
	case .Funct, .Immediate, .Unknown:
	}
	return value_text(u64(value))
}

// The first line under the fields: the format, the instruction, and
// the fields that picked it. The opcode only names a group (SYSTEM holds
// ecall, mret and the six CSR instructions); funct3, and in some groups
// funct7 / funct6 / funct5, pick the instruction within it; ecall,
// ebreak, mret and wfi share opcode and funct3, and funct12 tells them
// apart.
encoding_name_line :: proc(pc: u64, instruction: u32, encoding: Encoding) -> string {
	buffer: [96]u8
	text := disasm.disassemble(buffer[:], pc, instruction)
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "%s: %s   (opcode %s", encoding.format, text, opcode_name(rv.opcode(instruction)))
	for index in 0 ..< encoding.field_count {
		field := encoding.fields[index]
		if field.kind != .Funct || field.label == "aq" || field.label == "rl" {
			continue // aq / rl are ordering hints, not part of the choice
		}
		fmt.sbprintf(&builder, " + %s %s", field.label, field_bits_text(instruction, field))
	}
	strings.write_string(&builder, ")")
	return strings.to_string(builder)
}

// The second line: what the immediate (or the CSR field) works out to.
// "" when the format has nothing more to say.
encoding_summary :: proc(pc: u64, instruction: u32, encoding: Encoding) -> string {
	switch encoding.format {
	case "R-type (atomic)":
		width := "32-bit (.w)" if rv.funct3(instruction) == rv.AMO_WORD else "64-bit (.d)"
		return fmt.tprintf("funct5 picks the operation, %s; aq / rl are ordering hints; address = rs1, no offset", width)
	case "I-type":
		return fmt.tprintf("imm = %s (12 bits, sign-extended)", signed_text(i64(rv.imm_i(instruction))))
	case "I-type (CSR)":
		return csr_field_text(instruction)
	case "I-type (system)":
		return "funct12 picks the instruction: 0x000 ecall, 0x001 ebreak, 0x102 sret, 0x302 mret, 0x105 wfi (rs1 and rd are 0)"
	case "I-type (shift)":
		return fmt.tprintf("shift amount = %s", value_text(u64((instruction >> 20) & 0x3F)))
	case "S-type":
		return fmt.tprintf(
			"imm = imm[11:5] imm[4:0] = %s %s = %s",
			bits_of(instruction, encoding, "imm[11:5]"),
			bits_of(instruction, encoding, "imm[4:0]"),
			signed_text(i64(rv.imm_s(instruction))),
		)
	case "B-type":
		offset := rv.imm_b(instruction)
		return fmt.tprintf(
			"offset = imm[12] imm[11] imm[10:5] imm[4:1] 0 = %s %s %s %s 0 = %s (bit 0 is always 0, so not stored) -> target 0x%x",
			bits_of(instruction, encoding, "imm[12]"),
			bits_of(instruction, encoding, "imm[11]"),
			bits_of(instruction, encoding, "imm[10:5]"),
			bits_of(instruction, encoding, "imm[4:1]"),
			signed_text(i64(offset)),
			pc + offset,
		)
	case "U-type":
		return fmt.tprintf("imm = 0x%x << 12 = 0x%x", instruction >> 12, rv.imm_u(instruction))
	case "J-type":
		offset := rv.imm_j(instruction)
		return fmt.tprintf(
			"offset = imm[20] imm[19:12] imm[11] imm[10:1] 0 = %s %s %s %s 0 = %s (bit 0 is always 0, so not stored) -> target 0x%x",
			bits_of(instruction, encoding, "imm[20]"),
			bits_of(instruction, encoding, "imm[19:12]"),
			bits_of(instruction, encoding, "imm[11]"),
			bits_of(instruction, encoding, "imm[10:1]"),
			signed_text(i64(offset)),
			pc + offset,
		)
	}
	return ""
}

// The bits of the field labelled `label`, as a binary string: the
// pieces of a scattered immediate, put back in order by the summary.
@(private)
bits_of :: proc(instruction: u32, encoding: Encoding, label: string) -> string {
	for index in 0 ..< encoding.field_count {
		if encoding.fields[index].label == label {
			return field_bits_text(instruction, encoding.fields[index])
		}
	}
	return "?"
}

// A CSR instruction's csr field read as the CSR's number: its name, and
// the two rules in its top bits (docs: csr-addresses). For the i forms,
// also the 5-bit constant in the rs1 field.
//   csr = 0x300 (mstatus): bits 11..10 = 00 read/write, bits 9..8 = 11 machine only
@(private)
csr_field_text :: proc(instruction: u32) -> string {
	LEVELS := [4]string{"any level", "supervisor and up", "reserved", "machine only"}
	address := rv.csr_address(instruction)
	name := disasm.csr_name(address)
	access := (address >> 10) & 0b11
	level := rv.csr_level(address)
	text := fmt.tprintf(
		"csr = 0x%03x (%s): bits 11..10 = %02b %s, bits 9..8 = %02b %s",
		address,
		name if name != "" else "not implemented",
		access,
		"read-only" if access == 0b11 else "read/write",
		level,
		LEVELS[level],
	)
	if rv.funct3(instruction) & 0b100 != 0 {
		text = fmt.tprintf("%s; uimm = %d (a constant, not a register)", text, (instruction >> 15) & 0x1f)
	}
	return text
}

// ------------------------------------------------------------- builders

@(private)
add_field :: proc(encoding: ^Encoding, high: u32, low: u32, label: string, kind: Field_Kind) {
	encoding.fields[encoding.field_count] = Encoding_Field{high, low, label, kind}
	encoding.field_count += 1
}

// rs2 [24:20], rs1 [19:15], funct3 [14:12]: the same place in R/S/B.
@(private)
add_source_registers :: proc(encoding: ^Encoding) {
	add_field(encoding, 24, 20, "rs2", .Rs2)
	add_field(encoding, 19, 15, "rs1", .Rs1)
	add_field(encoding, 14, 12, "funct3", .Funct)
}

@(private)
r_type :: proc(encoding: ^Encoding) {
	encoding.format = "R-type"
	add_field(encoding, 31, 25, "funct7", .Funct)
	add_source_registers(encoding)
	add_field(encoding, 11, 7, "rd", .Rd)
	add_field(encoding, 6, 0, "opcode", .Opcode)
}

@(private)
i_type :: proc(encoding: ^Encoding) {
	encoding.format = "I-type"
	add_field(encoding, 31, 20, "imm[11:0]", .Immediate)
	add_field(encoding, 19, 15, "rs1", .Rs1)
	add_field(encoding, 14, 12, "funct3", .Funct)
	add_field(encoding, 11, 7, "rd", .Rd)
	add_field(encoding, 6, 0, "opcode", .Opcode)
}

// ecall, ebreak, mret, wfi: I-type whose 12 top bits are not an
// immediate but a code (funct12) saying which of them it is; rs1 and rd
// are 0.
@(private)
system_type :: proc(encoding: ^Encoding) {
	encoding.format = "I-type (system)"
	add_field(encoding, 31, 20, "funct12", .Funct)
	add_field(encoding, 19, 15, "rs1", .Rs1)
	add_field(encoding, 14, 12, "funct3", .Funct)
	add_field(encoding, 11, 7, "rd", .Rd)
	add_field(encoding, 6, 0, "opcode", .Opcode)
}

// CSR instructions: I-type whose immediate is the CSR address; the
// immediate forms (CSRRWI, ...) use the rs1 field as a 5-bit value.
@(private)
csr_type :: proc(encoding: ^Encoding, immediate_form: bool) {
	encoding.format = "I-type (CSR)"
	add_field(encoding, 31, 20, "csr", .Csr)
	if immediate_form {
		add_field(encoding, 19, 15, "uimm", .Immediate)
	} else {
		add_field(encoding, 19, 15, "rs1", .Rs1)
	}
	add_field(encoding, 14, 12, "funct3", .Funct)
	add_field(encoding, 11, 7, "rd", .Rd)
	add_field(encoding, 6, 0, "opcode", .Opcode)
}

// I-type whose immediate is really a shift type (funct6 / funct7) plus a
// shift amount: `split` is the lowest bit of the shift-type field.
@(private)
shift_immediate :: proc(encoding: ^Encoding, split: u32, type_label: string) {
	encoding.format = "I-type (shift)"
	add_field(encoding, 31, split, type_label, .Funct)
	add_field(encoding, split - 1, 20, "shamt", .Immediate)
	add_field(encoding, 19, 15, "rs1", .Rs1)
	add_field(encoding, 14, 12, "funct3", .Funct)
	add_field(encoding, 11, 7, "rd", .Rd)
	add_field(encoding, 6, 0, "opcode", .Opcode)
}

opcode_name :: proc(opcode: u32) -> string {
	switch opcode {
	case rv.OPCODE_LOAD: return "LOAD"
	case rv.OPCODE_MISC_MEM: return "MISC-MEM"
	case rv.OPCODE_OP_IMM: return "OP-IMM"
	case rv.OPCODE_AUIPC: return "AUIPC"
	case rv.OPCODE_OP_IMM_32: return "OP-IMM-32"
	case rv.OPCODE_STORE: return "STORE"
	case rv.OPCODE_OP: return "OP"
	case rv.OPCODE_LUI: return "LUI"
	case rv.OPCODE_OP_32: return "OP-32"
	case rv.OPCODE_BRANCH: return "BRANCH"
	case rv.OPCODE_JALR: return "JALR"
	case rv.OPCODE_JAL: return "JAL"
	case rv.OPCODE_SYSTEM: return "SYSTEM"
	case rv.OPCODE_AMO: return "AMO"
	}
	return "?"
}

// Which registers an instruction reads and writes, from its encoding
// fields (rs1 / rs2 read, rd written). x0 is left out: reading it always
// gives 0 and writing it does nothing.
Register_Use :: enum {
	None,
	Read_Rs1,
	Read_Rs2,
	Write_Rd,
}

register_use :: proc(instruction: u32, register: u32) -> Register_Use {
	if register == 0 {
		return .None
	}
	encoding := encoding_of(instruction)
	use := Register_Use.None
	for field in encoding.fields[:encoding.field_count] {
		if field_value(instruction, field) != register {
			continue
		}
		#partial switch field.kind {
		case .Rd:
			return .Write_Rd // a write matters most when rd is also a source
		case .Rs1:
			use = .Read_Rs1
		case .Rs2:
			if use == .None {
				use = .Read_Rs2
			}
		}
	}
	return use
}
