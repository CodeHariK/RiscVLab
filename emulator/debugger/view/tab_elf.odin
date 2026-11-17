package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import ui "../ui"
import state "../state"

// The ELF tab: what the loader found in the program file.

// What the loader found: format, entry point, code range, tohost.
@(private)
tab_elf :: proc(session: ^state.Session) {
	{
		program := session.program
		format := "ELF" if program.format == .Elf else "raw binary"
		instruction_count := (program.code_end - program.code_start) / rv.INSTRUCTION_SIZE
		tohost := "not present"
		if address, has_tohost := program.tohost.?; has_tohost {
			value, _ := rv.bus_load(&session.machine.bus, address, 8)
			tohost = fmt.tprintf("0x%x (value %s)", address, value_text(value))
		}

		data := "none"
		if program.data_end > program.data_start {
			data = fmt.tprintf("0x%x - 0x%x (%d bytes)", program.data_start, program.data_end, program.data_end - program.data_start)
		}
		rows := [?]ui.Table_Row {
			program_line("format", format),
			program_line("entry", fmt.tprintf("0x%x", program.entry)),
			program_line("code", fmt.tprintf("0x%x - 0x%x (%d instructions)", program.code_start, program.code_end, instruction_count)),
			program_line("data", data),
			program_line("tohost", tohost),
		}
		ui.table(clay.ID("ElfTable"), rows[:], tab_table())
	}
}

// A label (dimmed) and its value.
@(private)
program_line :: proc(label: string, value: string) -> ui.Table_Row {
	return {cells = ui.cells({text = label, color = ui.palette().text_dim}, {text = value})}
}
