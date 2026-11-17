package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Registers tab: the pc and x0..x31, with read / write tags and the
// last change highlighted.

// The pc, then all 32 registers with ABI names. A tag shows what the next instruction
// does with each register (reads it as rs1 / rs2, writes it as rd), in the
// Encoding strip's colours; the register the last step wrote is marked.
@(private)
tab_registers :: proc(session: ^state.Session) {
	colors := ui.palette()
	cpu := &session.machine.cpu
	changed_index := -1
	if record, has_record := session.last_step.?; has_record && record.register_changed {
		changed_index = int(record.register_index)
	}
	next_instruction, fetched := rv.bus_load(&session.machine.bus, cpu.pc, 4)

	// The pc is not one of x0-x31: no instruction names it as rd/rs1/rs2,
	// it just moves on by 4 (or jumps) after every instruction.
	if clay.UI(clay.ID("PcLine"))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 4}}}) {
		register_use_tag(.None)
		clay.TextDynamic(fmt.tprintf("%-3s %-4s %s", "pc", "", register_value_text(cpu.pc)), ui.text_config(.Code_Small, colors.accent))
	}

	for index in 0 ..< rv.REGISTER_COUNT {
		value := cpu.regs[index]
		text := fmt.tprintf("x%-2d %-4s %s", index, disasm.register_name(u32(index)), register_value_text(value))
		use := Register_Use.None
		if fetched {
			use = register_use(u32(next_instruction), u32(index))
		}
		highlight := colors.changed if index == changed_index else ui.COLOR_NONE
		if clay.UI(clay.ID("RegisterLine", u32(index)))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 1}},
			backgroundColor = highlight,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			register_use_tag(use)
			clay.TextDynamic(text, ui.text_config(.Code_Small, colors.text))
		}
	}
}

// "rs1" / "rs2" / "rd" in the field's colour, or blank, in a fixed width.
@(private)
register_use_tag :: proc(use: Register_Use) {
	colors := ui.palette()
	label, color := "", colors.text
	switch use {
	case .Read_Rs1:
		label, color = "rs1", field_color(.Rs1)
	case .Read_Rs2:
		label, color = "rs2", field_color(.Rs2)
	case .Write_Rd:
		label, color = "rd", field_color(.Rd)
	case .None:
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(36)}}}) {
		if label != "" {
			clay.TextDynamic(label, ui.text_config(.Code_Small, color))
		}
	}
}
