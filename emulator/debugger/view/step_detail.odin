package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import disasm "../../disasm"
import state "../state"

// The detailed view of one step: what each part of the CPU did and why,
// with every value that led to it.
//
//   fetch    mem[pc 0x80000010] -> 0x0002a383
//   decode   I-type lw (opcode LOAD 0x03): rd t2 (x7), rs1 t0 (x5), imm 0x0
//   read     t0 = 0x80001000
//   execute  address = t0 0x80001000 + 0x0 = 0x80001000 (numbers)
//   memory   load 4 bytes @ 0x80001000 (numbers) -> 0xa (10), sign-extended
//   write    t2: 0x0 -> 0xa (10)
//
// The emulator is not pipelined: each instruction finishes all of these
// before the next one starts. They are the stages every instruction goes
// through, in the order a simple textbook CPU does them. A stage the
// instruction doesn't use is left empty. The text is built from a
// Timeline_Entry's raw values, only for steps on screen. The execute stage
// (the part with the decisions) is in step_execute.odin.

Stage :: enum {
	Fetch,
	Decode,
	Read,
	Execute,
	Memory,
	Write,
}

stage_names := [Stage]string {
	.Fetch   = "fetch",
	.Decode  = "decode",
	.Read    = "read",
	.Execute = "execute",
	.Memory  = "memory",
	.Write   = "write",
}

// One text per stage; "" for a stage the instruction doesn't use.
Step_Detail :: [Stage]string

step_detail :: proc(session: ^state.Session, entry: state.Timeline_Entry) -> Step_Detail {
	detail: Step_Detail
	detail[.Fetch] = fmt.tprintf("mem[pc 0x%x] -> 0x%08x", entry.pc, entry.instruction)
	detail[.Decode] = decode_text(entry)
	detail[.Read] = read_text(entry)
	detail[.Execute] = execute_text(session, entry)
	detail[.Memory] = memory_text(session, entry)
	detail[.Write] = write_text(entry)
	return detail
}

// The instruction's mnemonic, e.g. "lw".
step_mnemonic :: proc(entry: state.Timeline_Entry) -> string {
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], entry.pc, entry.instruction)
	return strings.clone(first_word(text), context.temp_allocator)
}

// ECALL / EBREAK / MRET: SYSTEM with funct3 = 0. Their rd and rs1 fields
// are zero and mean nothing, so no registers are shown for them.
is_system_call :: proc(instruction: u32) -> bool {
	return rv.opcode(instruction) == rv.OPCODE_SYSTEM && rv.funct3(instruction) == 0
}

// "I-type lw (opcode LOAD 0x03): rd t2 (x7), rs1 t0 (x5), imm 0x0"
@(private)
decode_text :: proc(entry: state.Timeline_Entry) -> string {
	instruction := entry.instruction
	encoding := encoding_of(instruction)
	opcode := rv.opcode(instruction)
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "%s %s (opcode %s 0x%02x)", encoding.format, step_mnemonic(entry), opcode_name(opcode), opcode)
	if encoding.format == "unknown" || is_system_call(instruction) {
		return strings.to_string(builder)
	}

	separator := ": "
	for field in encoding.fields[:encoding.field_count] {
		value := field_value(instruction, field)
		part: string
		#partial switch field.kind {
		case .Rd, .Rs1, .Rs2:
			part = fmt.tprintf("%s %s (x%d)", field.label, disasm.register_name(value), value)
		case .Csr:
			part = fmt.tprintf("csr %s (0x%03x)", disasm.csr_name(value), value)
		case:
			continue
		}
		strings.write_string(&builder, separator)
		strings.write_string(&builder, part)
		separator = ", "
	}
	if immediate := immediate_text(entry.pc, instruction, encoding.format); immediate != "" {
		strings.write_string(&builder, separator)
		strings.write_string(&builder, immediate)
	}
	return strings.to_string(builder)
}

// The assembled immediate, as the execute stage will use it.
@(private)
immediate_text :: proc(pc: u64, instruction: u32, format: string) -> string {
	switch format {
	case "I-type":
		return fmt.tprintf("imm %s", signed_text(i64(rv.imm_i(instruction))))
	case "I-type (shift)":
		return fmt.tprintf("shamt %s", value_text(u64((instruction >> 20) & 0x3F)))
	case "I-type (CSR)":
		if rv.funct3(instruction) & 0b100 != 0 {
			return fmt.tprintf("uimm %s", value_text(u64(rv.rs1(instruction))))
		}
	case "S-type":
		return fmt.tprintf("imm %s", signed_text(i64(rv.imm_s(instruction))))
	case "B-type":
		return fmt.tprintf("offset %s", signed_text(i64(rv.imm_b(instruction))))
	case "U-type":
		return fmt.tprintf("imm 0x%x", instruction >> 12)
	case "J-type":
		return fmt.tprintf("offset %s", signed_text(i64(rv.imm_j(instruction))))
	}
	return ""
}

// The registers (and CSR) the instruction reads, with their values then.
@(private)
read_text :: proc(entry: state.Timeline_Entry) -> string {
	instruction := entry.instruction
	if is_system_call(instruction) {
		return ""
	}
	encoding := encoding_of(instruction)
	builder := strings.builder_make(context.temp_allocator)
	for field in encoding.fields[:encoding.field_count] {
		part: string
		#partial switch field.kind {
		case .Rs1:
			part = fmt.tprintf("%s = %s", disasm.register_name(rv.rs1(instruction)), value_text(entry.rs1_value))
		case .Rs2:
			part = fmt.tprintf("%s = %s", disasm.register_name(rv.rs2(instruction)), value_text(entry.rs2_value))
		case .Csr:
			part = fmt.tprintf("%s = %s", disasm.csr_name(rv.csr_address(instruction)), value_text(entry.csr_value))
		case:
			continue
		}
		append_part(&builder, part)
	}
	return strings.to_string(builder)
}

// Loads and stores: the bytes moved, and which variable they belong to.
@(private)
memory_text :: proc(session: ^state.Session, entry: state.Timeline_Entry) -> string {
	instruction := entry.instruction
	if entry.trap != nil {
		return ""
	}
	size := u64(1) << (rv.funct3(instruction) & 0b11)
	switch rv.opcode(instruction) {
	case rv.OPCODE_LOAD:
		address := entry.rs1_value + rv.imm_i(instruction)
		if place, on_device := device_place(session, address, false); on_device {
			return fmt.tprintf("read %d byte from the device register %s -> %s", size, place, device_value_text(session, address, false, entry.load_value))
		}
		extension := "zero-extended" if rv.funct3(instruction) >= 0b100 else "sign-extended"
		if size == 8 {
			extension = "all 64 bits"
		}
		text := fmt.tprintf(
			"load %d bytes @ 0x%x%s -> 0x%s, %s",
			size,
			address,
			state.symbol_label(session, address),
			hex_digits(entry.load_value, size),
			extension,
		)
		if entry.record.register_changed {
			text = fmt.tprintf("%s -> %s", text, value_text(entry.register_new))
		}
		return text
	case rv.OPCODE_AMO:
		return atomic_memory_text(session, entry, size)
	case rv.OPCODE_STORE:
		record := entry.record
		if place, on_device := device_place(session, record.memory_address, true); on_device {
			return fmt.tprintf(
				"write %d byte of %s to the device register %s: %s",
				size,
				disasm.register_name(rv.rs2(instruction)),
				place,
				device_value_text(session, record.memory_address, true, entry.rs2_value),
			)
		}
		return fmt.tprintf(
			"store the low %d bytes of %s @ 0x%x%s: %s -> %s",
			size,
			disasm.register_name(rv.rs2(instruction)),
			record.memory_address,
			state.symbol_label(session, record.memory_address),
			value_text(record.memory_old),
			value_text(entry.memory_new),
		)
	}
	return ""
}

// LR: the load and the reservation; SC: the store, or why it didn't
// happen; AMO: the old value read and the new one written, in one step.
@(private)
atomic_memory_text :: proc(session: ^state.Session, entry: state.Timeline_Entry, size: u64) -> string {
	instruction := entry.instruction
	address := entry.rs1_value
	place := state.symbol_label(session, address)
	switch rv.funct5(instruction) {
	case rv.AMO_LR:
		return fmt.tprintf("load %d bytes @ 0x%x%s -> 0x%s, and reserve 0x%x for an SC", size, address, place, hex_digits(entry.load_value, size), address)
	case rv.AMO_SC:
		if !entry.record.memory_changed {
			return "nothing stored: the reservation didn't hold"
		}
		return fmt.tprintf("store %d bytes @ 0x%x%s: %s -> %s", size, address, place, value_text(entry.record.memory_old), value_text(entry.memory_new))
	}
	return fmt.tprintf(
		"in one step: read 0x%s @ 0x%x%s, write %s back",
		hex_digits(entry.load_value, size),
		address,
		place,
		value_text(entry.memory_new),
	)
}

// `size` bytes of `value` as hex, all digits shown: 0000000a.
@(private)
hex_digits :: proc(value: u64, size: u64) -> string {
	switch size {
	case 1:
		return fmt.tprintf("%02x", value)
	case 2:
		return fmt.tprintf("%04x", value)
	case 4:
		return fmt.tprintf("%08x", value)
	}
	return fmt.tprintf("%016x", value)
}

// The registers and CSRs the step changed: old -> new.
@(private)
write_text :: proc(entry: state.Timeline_Entry) -> string {
	record := entry.record
	if entry.stops {
		return "nothing: the machine stops"
	}
	if trap, took_trap := entry.trap.?; took_trap {
		return fmt.tprintf(
			"mepc <- 0x%x, mcause <- %s (%v), mtval <- %s, mstatus: MPIE <- MIE, MIE <- 0, MPP <- %v; privilege <- Machine; pc <- mtvec 0x%x",
			entry.pc,
			value_text(u64(trap.cause)),
			trap.cause,
			value_text(trap.value),
			entry.record.privilege,
			entry.next_pc,
		)
	}
	builder := strings.builder_make(context.temp_allocator)
	if record.register_changed {
		append_part(
			&builder,
			fmt.tprintf(
				"%s: %s -> %s",
				disasm.register_name(record.register_index),
				value_text(record.register_old),
				value_text(entry.register_new),
			),
		)
	} else if writes_rd(entry.instruction) && rv.rd(entry.instruction) == 0 {
		append_part(&builder, "nothing: rd is zero, so the result is dropped")
	}
	if record.csr_changed {
		append_part(
			&builder,
			fmt.tprintf("%s: %s -> %s", disasm.csr_name(record.csr_address), value_text(record.csr_old), value_text(entry.csr_new)),
		)
	}
	if strings.builder_len(builder) == 0 && !record.memory_changed {
		return "no register changed"
	}
	return strings.to_string(builder)
}

// True if the instruction format has an rd field.
@(private)
writes_rd :: proc(instruction: u32) -> bool {
	if is_system_call(instruction) {
		return false
	}
	encoding := encoding_of(instruction)
	for field in encoding.fields[:encoding.field_count] {
		if field.kind == .Rd {
			return true
		}
	}
	return false
}

// Joins parts with ", ".
append_part :: proc(builder: ^strings.Builder, text: string) {
	if strings.builder_len(builder^) > 0 {
		strings.write_string(builder, ", ")
	}
	strings.write_string(builder, text)
}
