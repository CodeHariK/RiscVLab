package rvdbg

import "core:fmt"
import clay "../vendor/clay-odin"
import rv "../core"

// The Memory tab: a dump of memory around the interesting address, which
// is (in order of preference):
//
//   1. the address the next instruction loads from or stores to
//   2. the memory the last step changed
//   3. the last load or store (so the view stays on the data in use)
//   4. the program's data (.data / .bss), if it has any
//   5. the stack pointer, if it points into RAM
//   6. the instruction at the PC: instructions live in the same memory as data
//
// Symbol names (labels and variables from the ELF) are shown on a line
// above the row they fall in.
//
// Two layouts (switch at the top of the tab):
//   Words: 4 x 32-bit words per row, each read as a little-endian value,
//          so code reads exactly like the Disassembly tab's hex column.
//   Bytes: 8 bytes per row in address order, which shows that RISC-V
//          stores the lowest byte of a value first (little-endian).
//
// The word (or bytes) the next instruction will load or store, and the
// instruction at the PC itself, get the current-line background used in
// the code views; the accessed bytes are also coloured (load: rs1 colour,
// store: rd colour). What the last step changed has the "changed"
// background.

MEMORY_ROWS :: 24
MEMORY_ROWS_BEFORE :: 4
WORDS_PER_ROW :: 4

Memory_Access_Kind :: enum {
	None,
	Load,
	Store,
}

Memory_Access :: struct {
	kind:    Memory_Access_Kind,
	address: u64,
	size:    u64,
}

// The load or store the instruction at the PC is about to do, if any.
next_memory_access :: proc(session: ^Session) -> Memory_Access {
	cpu := &session.machine.cpu
	raw, ok := rv.bus_load(&session.machine.bus, cpu.pc, 4)
	if !ok {
		return {}
	}
	instruction := u32(raw)
	base := rv.reg_read(cpu, rv.rs1(instruction))
	size := u64(1) << (rv.funct3(instruction) & 0b11)
	switch rv.opcode(instruction) {
	case rv.OPCODE_LOAD:
		return {.Load, base + rv.imm_i(instruction), size}
	case rv.OPCODE_STORE:
		return {.Store, base + rv.imm_s(instruction), size}
	}
	return {}
}

memory_list :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("MemoryLayoutTabs"))({layout = {childGap = 8, padding = {bottom = 6}}}) {
		tab(TAB_ID_MEMORY_WORDS, "Words", view.memory_layout == .Words)
		tab(TAB_ID_MEMORY_BYTES, "Bytes", view.memory_layout == .Bytes)
	}

	access := next_memory_access(session)
	changed: Memory_Access
	if record, has_record := session.last_step.?; has_record && record.memory_changed {
		changed = {.Store, record.memory_address, record.memory_size}
	}
	focus, reason := memory_focus(session, access, changed)
	clay.TextDynamic(reason, text_config(.Code_Small, colors.text_dim))

	row_bytes := u64(WORDS_PER_ROW * 4) if view.memory_layout == .Words else 8
	first := first_row_address(focus, row_bytes)
	for row in 0 ..< MEMORY_ROWS {
		row_address := first + u64(row) * row_bytes
		if names := symbol_names_in(session, row_address, row_address + row_bytes, true); names != "" {
			if clay.UI(clay.ID("MemoryLabel", u32(row)))({layout = {padding = {6, 6, 4, 0}}}) {
				clay.TextDynamic(names, text_config(.Code_Small, colors.accent))
			}
		}
		if clay.UI(clay.ID("MemoryRow", u32(row)))({layout = {padding = {6, 6, 1, 1}, childGap = 8}}) {
			clay.TextDynamic(fmt.tprintf("%08x", row_address), text_config(.Code_Small, colors.text_dim))
			switch view.memory_layout {
			case .Words:
				for column in 0 ..< WORDS_PER_ROW {
					memory_cell(session, row_address + u64(column) * 4, 4, access, changed, u32(row * WORDS_PER_ROW + column))
				}
			case .Bytes:
				for column in 0 ..< 8 {
					memory_cell(session, row_address + u64(column), 1, access, changed, u32(row * 8 + column))
				}
			}
		}
	}
}

// A few rows before the focus, but never starting below RAM when the
// focus is in RAM (there is nothing there to show).
@(private = "file")
first_row_address :: proc(focus: u64, row_bytes: u64) -> u64 {
	aligned := focus - focus % row_bytes
	before := MEMORY_ROWS_BEFORE * row_bytes
	if aligned < before {
		return 0
	}
	first := aligned - before
	if focus >= rv.RAM_BASE && first < rv.RAM_BASE {
		first = rv.RAM_BASE
	}
	return first
}

// Where to centre the dump, and a line saying why.
@(private = "file")
memory_focus :: proc(session: ^Session, access: Memory_Access, changed: Memory_Access) -> (address: u64, reason: string) {
	if access.kind == .Load {
		return access.address, fmt.tprintf("next instruction loads %d bytes from 0x%x", access.size, access.address)
	}
	if access.kind == .Store {
		return access.address, fmt.tprintf("next instruction stores %d bytes to 0x%x", access.size, access.address)
	}
	if changed.kind != .None {
		return changed.address, fmt.tprintf("last step wrote %d bytes at 0x%x", changed.size, changed.address)
	}
	if last := session.last_access; last.kind != .None {
		verb := "loaded" if last.kind == .Load else "stored"
		return last.address, fmt.tprintf("last memory access: %s %d bytes at 0x%x", verb, last.size, last.address)
	}
	program := session.program
	if program.data_end > program.data_start {
		return program.data_start, fmt.tprintf(
			"the program's data (.data / .bss): 0x%x - 0x%x",
			program.data_start,
			program.data_end,
		)
	}
	sp := rv.reg_read(&session.machine.cpu, 2)
	if _, in_ram := rv.bus_load(&session.machine.bus, sp, 1); in_ram {
		return sp, fmt.tprintf("around the stack pointer sp = 0x%x", sp)
	}
	return session.machine.cpu.pc, "the instruction at pc: instructions are stored in memory like any data"
}

// One word (size 4) or byte (size 1) in hex, "--" outside memory,
// coloured if the next access or the last change overlaps it.
@(private = "file")
memory_cell :: proc(session: ^Session, address: u64, size: u64, access: Memory_Access, changed: Memory_Access, id: u32) {
	colors := palette()
	value, in_ram := rv.bus_load(&session.machine.bus, address, size)
	text := "--------" if size == 4 else "--"
	if in_ram {
		text = fmt.tprintf("%08x", value) if size == 4 else fmt.tprintf("%02x", value)
	}

	color := colors.text
	background := COLOR_NONE
	instruction := Memory_Access{.Load, session.machine.cpu.pc, 4}
	if overlaps(address, size, instruction) {
		background = colors.current_line
	}
	if access.kind != .None && overlaps(address, size, access) {
		color = colors.fields[.Rs1] if access.kind == .Load else colors.fields[.Rd]
		background = colors.current_line
	}
	if changed.kind != .None && overlaps(address, size, changed) {
		background = colors.changed
	}
	if clay.UI(clay.ID("MemoryCell", id))({backgroundColor = background, cornerRadius = clay.CornerRadiusAll(2)}) {
		clay.TextDynamic(text, text_config(.Code_Small, color))
	}
}

// True if [address, address + size) and the access's range share a byte.
@(private = "file")
overlaps :: proc(address: u64, size: u64, access: Memory_Access) -> bool {
	return address < access.address + access.size && access.address < address + size
}
