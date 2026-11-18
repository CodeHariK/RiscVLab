package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Disassembly tab: the instructions decoded from memory, with labels.

// Disassembly of the instructions around the PC, current one highlighted.
@(private)
tab_disassembly :: proc(session: ^state.Session) {
	colors := ui.palette()
	lines := visible_lines(CODE_LINE_HEIGHT)
	pc := session.machine.cpu.pc
	code_start, end := state.session_code_range(session)
	first := code_start
	if pc >= code_start && pc < end {
		pc_index := int((pc - code_start) / rv.INSTRUCTION_SIZE)
		total := int((end - code_start) / rv.INSTRUCTION_SIZE)
		first = code_start + u64(first_visible_index(pc_index, lines, total)) * rv.INSTRUCTION_SIZE
		// first_visible_index counts instructions, but labels take lines
		// too: start later until the pc's line is back above the bottom
		// third. (Not while scrolled with the wheel: then the pc may be
		// out of view on purpose.)
		if display.code_scroll == 0 {
			keep_below := lines / 3
			for first < pc && disassembly_lines(session, first, pc) > lines - keep_below {
				first += rv.INSTRUCTION_SIZE
			}
		}
	}

	// Symbol labels (e.g. "test_2:") take a line of their own, so count
	// lines drawn rather than instructions.
	buffer: [disasm.BUFFER_SIZE]u8
	drawn := 0
	for line := 0; drawn < lines; line += 1 {
		address := first + u64(line) * rv.INSTRUCTION_SIZE
		if address + rv.INSTRUCTION_SIZE > end {
			break
		}
		if label := state.symbol_names_at(session, address); label != "" {
			if clay.UI(clay.ID("CodeLabel", u32(line)))({layout = {padding = {6, 6, 4, 0}}}) {
				clay.TextDynamic(fmt.tprintf("%s:", label), ui.text_config(.Code, colors.title))
			}
			drawn += 1
		}
		drawn += 1
		raw, _ := rv.machine_peek(&session.machine, address, 4)
		instruction := u32(raw)
		text := fmt.tprintf(
			"%s %08x  %08x  %s",
			">" if address == pc else " ",
			address,
			instruction,
			disasm.disassemble(buffer[:], address, instruction),
		)
		highlight := colors.current_line if address == pc else ui.COLOR_NONE
		if clay.UI(clay.ID("CodeLine", u32(line)))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
			backgroundColor = highlight,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			clay.TextDynamic(text, ui.text_config(.Code, colors.text))
		}
	}
}

// Lines the listing takes from `first` up to and including the
// instruction at `last`: one per instruction, one per label line.
@(private)
disassembly_lines :: proc(session: ^state.Session, first: u64, last: u64) -> int {
	count := 0
	for address := first; address <= last; address += rv.INSTRUCTION_SIZE {
		count += 1
		if state.symbol_names_at(session, address) != "" {
			count += 1
		}
	}
	return count
}
