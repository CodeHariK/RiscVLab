package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
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

		program_line("format", format)
		program_line("entry", fmt.tprintf("0x%x", program.entry))
		program_line(
			"code",
			fmt.tprintf("0x%x - 0x%x (%d instructions)", program.code_start, program.code_end, instruction_count),
		)
		data := "none"
		if program.data_end > program.data_start {
			data = fmt.tprintf("0x%x - 0x%x (%d bytes)", program.data_start, program.data_end, program.data_end - program.data_start)
		}
		program_line("data", data)
		program_line("tohost", tohost)
	}
}

@(private)
program_line :: proc(label: string, value: string) {
	colors := ui.palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 1}}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(80)}}}) {
			clay.TextDynamic(label, ui.text_config(.Code_Small, colors.text_dim))
		}
		clay.TextDynamic(value, ui.text_config(.Code_Small, colors.text))
	}
}
