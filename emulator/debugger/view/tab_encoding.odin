package view

import clay "../../vendor/clay-odin"
import rv "../../core"
import ui "../ui"
import state "../state"

// The Encoding tab: the next instruction's 32 bits as colour-coded
// fields (encoding.odin), then what it reads, computes and writes.

// The instruction at the PC as 32 bits split into colour-coded fields
// (see encoding.odin), each with its name and meaning underneath, then
// what it reads, computes and writes.
@(private)
tab_encoding :: proc(session: ^state.Session) {
	colors := ui.palette()
	pc := session.machine.cpu.pc
	raw, ok := rv.machine_peek(&session.machine, pc, 4)
	if !ok {
		clay.TextDynamic("pc is outside memory", ui.text_config(.Text, colors.text_dim))
		return
	}
	instruction := u32(raw)
	encoding := encoding_of(instruction)

	if clay.UI(clay.ID("EncodingFields"))({layout = {childGap = 16, padding = {top = 4, bottom = 6}}}) {
		for field, index in encoding.fields[:encoding.field_count] {
			encoding_field(instruction, field, u32(index))
		}
	}
	clay.TextDynamic(encoding_summary(pc, instruction, encoding), ui.text_config(.Text, colors.text))
	instruction_effect(session)
}

// What the next instruction reads, computes, moves to or from memory and
// writes, results included: those stages of the preview (step_detail.odin).
// All its stages, and those of every earlier step, are in Steps -> Detailed.
@(private)
instruction_effect :: proc(session: ^state.Session) {
	colors := ui.palette()
	entry, has_preview := session.preview.?
	if !has_preview {
		return
	}
	if clay.UI(clay.ID("InstructionEffect"))({layout = {layoutDirection = .TopToBottom, padding = {top = 8}}}) {
		detail := step_detail(session, entry)
		for stage in ([]Stage{.Read, .Execute, .Memory, .Write}) {
			if detail[stage] != "" {
				detail_line(stage_names[stage], detail[stage], colors.text)
			}
		}
	}
}

// One field as a small column: bits (in the field's colour), name, meaning.
@(private)
encoding_field :: proc(instruction: u32, field: Encoding_Field, index: u32) {
	colors := ui.palette()
	if clay.UI(clay.ID("EncodingField", index))({layout = {layoutDirection = .TopToBottom, childGap = 2}}) {
		clay.TextDynamic(field_bits_text(instruction, field), ui.text_config(.Code, field_color(field.kind)))
		clay.TextDynamic(field.label, ui.text_config(.Code_Small, field_color(field.kind)))
		clay.TextDynamic(field_value_text(instruction, field), ui.text_config(.Code_Small, colors.text_dim))
	}
}

@(private)
detail_line :: proc(label: string, text: string, color: clay.Color) {
	colors := ui.palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 10, padding = {top = 2, bottom = 2}}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(80)}}}) {
			clay.TextDynamic(label, ui.text_config(.Text, colors.accent))
		}
		clay.TextDynamic(text, ui.text_config(.Text, color))
	}
}
