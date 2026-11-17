package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Registers tab: the pc and x0..x31, with read / write tags and the
// last change highlighted.

// The pc, then all 32 registers with ABI names, as a table:
//
//   tag  name  abi   value
//        pc          0x0000000080000000
//   rs1  x5    t0    0x0000000000000004 (4)
//
// The tag shows what the next instruction does with each register (reads
// it as rs1 / rs2, writes it as rd), in the Encoding strip's colours; the
// register the last step wrote is marked.
@(private)
tab_registers :: proc(session: ^state.Session) {
	colors := ui.palette()
	cpu := &session.machine.cpu
	changed_index := -1
	if record, has_record := session.last_step.?; has_record && record.register_changed {
		changed_index = int(record.register_index)
	}
	next_instruction, fetched := rv.bus_peek(&session.machine.bus, cpu.pc, 4)

	rows := make([dynamic]ui.Table_Row, 0, rv.REGISTER_COUNT + 1, context.temp_allocator)
	// The pc is not one of x0-x31: no instruction names it as rd/rs1/rs2,
	// it just moves on by 4 (or jumps) after every instruction.
	append(&rows, ui.Table_Row{cells = ui.cells({}, {text = "pc"}, {}, {text = register_value_text(cpu.pc)}), color = colors.accent})
	for index in 0 ..< rv.REGISTER_COUNT {
		use := Register_Use.None
		if fetched {
			use = register_use(u32(next_instruction), u32(index))
		}
		tag, tag_color := register_use_tag(use)
		append(&rows, ui.Table_Row{
			cells = ui.cells(
				{text = tag, color = tag_color},
				{text = fmt.tprintf("x%d", index)},
				{text = disasm.register_name(u32(index))},
				{text = register_value_text(cpu.regs[index])},
			),
			background = colors.changed if index == changed_index else ui.COLOR_NONE,
		})
	}
	// The tag column keeps its width when no register has a tag, so the
	// names don't shift from step to step.
	options := tab_table()
	options.min_columns = {"rs1"}
	ui.table(clay.ID("RegisterTable"), rows[:], options)
}

// "rs1" / "rs2" / "rd" in the field's colour, or nothing.
@(private)
register_use_tag :: proc(use: Register_Use) -> (string, clay.Color) {
	switch use {
	case .Read_Rs1:
		return "rs1", field_color(.Rs1)
	case .Read_Rs2:
		return "rs2", field_color(.Rs2)
	case .Write_Rd:
		return "rd", field_color(.Rd)
	case .None:
	}
	return "", ui.COLOR_NONE
}
