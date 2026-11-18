package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import ui "../ui"
import state "../state"

// The Stack tab: the words from just below sp up to the top of the stack,
// newest (lowest address) first, one 8-byte word per row.
//
//   sp ->  sp+0x0  800011e0  0x0000000000000004 (4)
//          sp+0x8  800011e8  0x0000000080000034  -> sum+0x18 (code)
//
// Values that point into code are named with their label: a saved return
// address looks like `-> sum+0x18`. Values that point into data or into
// the stack say so too.
//
// Frames: each time sp goes down, the step that moved it made a frame
// (e.g. `addi sp, sp, -16` at the start of a function); going back up
// frees it. The frames are worked out from the steps taken (the Steps
// tab's timeline), so they are exact for any program, without a frame
// pointer. A heading line marks where each frame starts.
//
// The top of the stack is the `stack_top` symbol if the program has one,
// otherwise the highest sp seen so far. Colours as in the Memory tab: the
// word the next instruction loads or stores is coloured, the word the last
// step wrote has the "changed" background.

STACK_SP :: 2 // x2
STACK_WORD :: 8
STACK_FREE_ROWS :: 2 // rows shown below sp (free space the next push uses)
STACK_MAX_ROWS :: 64
// An sp change bigger than this is setting up a stack, not a frame.
STACK_MAX_FRAME :: 0x10000

Stack_Frame :: struct {
	low:     u64, // sp after the step that made it
	high:    u64, // sp before it: the frame is [low, high)
	made_at: u64, // pc of that step
}

tab_stack :: proc(session: ^state.Session) {
	colors := ui.palette()
	sp := rv.reg_read(&session.machine.cpu, STACK_SP)
	if _, in_ram := rv.machine_peek(&session.machine, sp - 1, 1); !in_ram || sp == 0 {
		wrapped_text(
			fmt.tprintf("sp = 0x%x does not point into RAM yet: programs set it up first, e.g. la sp, stack_top (lesson 09).", sp),
			ui.text_config(.Code_Small, colors.text_dim),
		)
		return
	}

	frames := stack_frames(session)
	top := stack_top(session, sp, frames)
	used := top - sp if top > sp else 0
	wrapped_text(fmt.tprintf("sp = 0x%x, top = 0x%x", sp, top), ui.text_config(.Code_Small, colors.text_dim))
	usage := fmt.tprintf("%s bytes in use, %d frame(s)", value_text(used), len(frames))
	if reserved, ok := state.symbol_address(session, "stack"); ok && reserved < top {
		usage = fmt.tprintf("%s, %s bytes reserved", usage, value_text(top - reserved))
	}
	wrapped_text(usage, ui.text_config(.Code_Small, colors.text_dim))

	access := state.next_memory_access(session)
	changed: state.Memory_Access
	if record, has_record := session.last_step.?; has_record && record.memory_changed {
		changed = {.Store, record.memory_address, record.memory_size}
	}

	first := sp - STACK_FREE_ROWS * STACK_WORD
	rows := make([dynamic]ui.Table_Row, context.temp_allocator)
	row := 0
	for address := first; address < top && row < STACK_MAX_ROWS; address += STACK_WORD {
		if frame, starts := frame_starting_at(frames, address); starts {
			append(&rows, frame_heading(session, frame))
		}
		append(&rows, stack_row(session, address, sp, top, access, changed))
		row += 1
	}
	ui.table(clay.ID("StackTable"), rows[:], tab_table())
	if top > sp && (top - first) / STACK_WORD > STACK_MAX_ROWS {
		wrapped_text(fmt.tprintf("... %d more words up to the top", (top - first) / STACK_WORD - STACK_MAX_ROWS), ui.text_config(.Code_Small, colors.text_dim))
	}
	clay.TextDynamic(fmt.tprintf("%08x  top of the stack", top), ui.text_config(.Code_Small, colors.accent))
}

// The frames still in use, oldest first, from every change to sp so far.
@(private)
stack_frames :: proc(session: ^state.Session) -> []Stack_Frame {
	frames := make([dynamic]Stack_Frame, context.temp_allocator)
	for entry in session.timeline {
		record := entry.record
		if !record.register_changed || record.register_index != STACK_SP {
			continue
		}
		old, new := record.register_old, entry.register_new
		if new < old && old - new <= STACK_MAX_FRAME {
			append(&frames, Stack_Frame{low = new, high = old, made_at = entry.pc})
			continue
		}
		// sp went up (or jumped): frames below the new sp are freed.
		for len(frames) > 0 && frames[len(frames) - 1].low < new {
			pop(&frames)
		}
	}
	return frames[:]
}

@(private)
stack_top :: proc(session: ^state.Session, sp: u64, frames: []Stack_Frame) -> u64 {
	if address, ok := state.symbol_address(session, "stack_top"); ok && address >= sp {
		return address
	}
	top := sp
	if len(frames) > 0 {
		top = max(top, frames[0].high)
	}
	return top
}

@(private)
frame_starting_at :: proc(frames: []Stack_Frame, address: u64) -> (Stack_Frame, bool) {
	for frame in frames {
		if frame.low == address {
			return frame, true
		}
	}
	return {}, false
}

// "frame made at sum+0x4: 0x10 bytes": where the step that made it was.
@(private)
frame_heading :: proc(session: ^state.Session, frame: Stack_Frame) -> ui.Table_Row {
	place := state.symbol_place(session, frame.made_at)
	if place == "" {
		place = fmt.tprintf("0x%x", frame.made_at)
	}
	text := fmt.tprintf("frame made at %s: %s bytes", place, value_text(frame.high - frame.low))
	return {cells = ui.cells({text = text}), color = ui.palette().accent, span = true}
}

// marker | offset from sp | address | value | what the value points at
@(private)
stack_row :: proc(session: ^state.Session, address: u64, sp: u64, top: u64, access: state.Memory_Access, changed: state.Memory_Access) -> ui.Table_Row {
	colors := ui.palette()
	value, _ := rv.machine_peek(&session.machine, address, STACK_WORD)
	free := address < sp

	offset: string
	if free {
		offset = fmt.tprintf("sp-0x%x", sp - address)
	} else {
		offset = fmt.tprintf("sp+0x%x", address - sp)
	}
	meaning := value_meaning(session, value, sp, top)
	if free {
		meaning = "(free)" if meaning == "" else fmt.tprintf("%s (free)", meaning)
	}

	color := colors.text_dim if free else colors.text
	word := state.Memory_Access{.Load, address, STACK_WORD}
	background := ui.COLOR_NONE
	if access.kind != .None && overlaps_access(word, access) {
		color = field_color(.Rs1) if access.kind == .Load else field_color(.Rd)
		background = colors.current_line
	}
	if changed.kind != .None && overlaps_access(word, changed) {
		background = colors.changed
	}
	return {
		cells = ui.cells(
			{text = "sp ->" if address == sp else ""},
			{text = offset},
			{text = fmt.tprintf("%08x", address)},
			{text = register_value_text(value)},
			{text = meaning},
		),
		color = color,
		background = background,
	}
}

// "-> sum+0x20 (code)" when the value is an address we can name.
@(private)
value_meaning :: proc(session: ^state.Session, value: u64, sp: u64, top: u64) -> string {
	program := session.program
	if value >= program.code_start && value < program.code_end {
		return fmt.tprintf("-> %s (code)", symbol_place_or_address(session, value))
	}
	// Before the data check: the stack itself is usually in .bss.
	if value >= sp && value <= top {
		return fmt.tprintf("-> stack sp+0x%x", value - sp)
	}
	if value >= program.data_start && value < program.data_end {
		return fmt.tprintf("-> %s (data)", symbol_place_or_address(session, value))
	}
	return ""
}

@(private)
symbol_place_or_address :: proc(session: ^state.Session, address: u64) -> string {
	if place := state.symbol_place(session, address); place != "" {
		return place
	}
	return fmt.tprintf("0x%x", address)
}

@(private)
overlaps_access :: proc(a: state.Memory_Access, b: state.Memory_Access) -> bool {
	return a.address < b.address + b.size && b.address < a.address + a.size
}
