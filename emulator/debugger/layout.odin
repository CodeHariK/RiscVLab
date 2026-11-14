package rvdbg

import "core:fmt"
import clay "../vendor/clay-odin"
import rv "../core"

// The debugger window, described with Clay:
//
//   +------------------------------------------------------------+
//   | [Start] [Prev] [Next]   program   step   pc                |  toolbar
//   +-----------------------------------+------------------------+
//   | Code: disassembly around the PC   | [Registers] [Program]  |
//   | (current instruction highlighted) | tab content, scrolls   |
//   +-----------------------------------+ with the mouse wheel   |
//   | Encoding: the current instruction |                        |
//   | as colour-coded bit fields        |                        |
//   +-----------------------------------+------------------------+
//   | Status / Next / Last step (small text)                     |  explanation
//   +------------------------------------------------------------+
//
// Built from scratch every frame from the session state; strings use the
// temp allocator, freed once the frame is drawn.

// The code panel shows as many instructions as fit, a third of them
// before the PC. Heights in pixels, matching the styles used below.
CODE_LINE_HEIGHT :: 24 // Code font (18) + line padding (4) + gap (2)
CODE_PANEL_OVERHEAD :: 60 // title, panel padding and border
CODE_LINES_DEFAULT :: 20 // first frame, before the panel has a size

build_layout :: proc(session: ^Session, frame_time: f32) -> clay.ClayArray(clay.RenderCommand) {
	colors := palette()
	clay.BeginLayout()
	if clay.UI(clay.ID("Root"))({
		layout = {
			sizing = {clay.SizingGrow(), clay.SizingGrow()},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(PANEL_GAP),
			childGap = PANEL_GAP,
		},
		backgroundColor = colors.background,
	}) {
		toolbar(session)
		toolbar_stripe()
		if clay.UI(clay.ID("Main"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, childGap = PANEL_GAP}}) {
			if clay.UI(clay.ID("LeftColumn"))({
				layout = {
					sizing = {clay.SizingPercent(0.58), clay.SizingGrow()},
					layoutDirection = .TopToBottom,
					childGap = PANEL_GAP,
				},
			}) {
				code_panel(session)
				encoding_panel(session)
			}
			side_panel(session)
		}
		explanation_panel(session)
	}
	return clay.EndLayout(frame_time)
}

@(private = "file")
toolbar :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("Toolbar"))({
		layout = {
			sizing = {width = clay.SizingGrow()},
			childGap = 8,
			childAlignment = {y = .Center},
		},
	}) {
		button(BUTTON_ID_START, "Start")
		button(BUTTON_ID_PREV, "< Prev")
		button(BUTTON_ID_NEXT, "Next >")

		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(16)}}}) {}
		cpu := &session.machine.cpu
		info := fmt.tprintf("%s    step %d    pc 0x%x", session.program_name, cpu.instret, cpu.pc)
		clay.TextDynamic(info, text_config(.Code, colors.text_dim))

		// Settings, pushed to the right edge.
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {}
		button(BUTTON_ID_THEME, settings_theme_label())
	}
}

// Thin orange-to-red stripes under the toolbar, as on the Clay website.
@(private = "file")
toolbar_stripe :: proc() {
	colors := palette()
	if clay.UI(clay.ID("Stripe"))({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
		for color, index in colors.stripe {
			if clay.UI(clay.ID("StripeBand", u32(index)))({
				layout = {sizing = {clay.SizingGrow(), clay.SizingFixed(3)}},
				backgroundColor = color,
			}) {}
		}
	}
}

@(private = "file")
button :: proc(id: string, label: string) {
	colors := palette()
	element_id := clay.ID(id)
	hovered := clay.PointerOver(element_id)
	if clay.UI(element_id)({
		layout = {padding = {16, 16, 6, 6}},
		backgroundColor = colors.button_hover if hovered else colors.button,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic(label, text_config(.Text, colors.button_text))
	}
}

// Look shared by the panels. `clip` hides content that overflows the
// panel. A panel that contains its own scrolling area must not clip:
// in Clay a clipping element lets its children grow past it (so they can
// scroll), which would stop the inner area from being sized to the panel.
@(private = "file")
panel_style :: proc(sizing: clay.Sizing, clip := true) -> clay.ElementDeclaration {
	colors := palette()
	return clay.ElementDeclaration {
		layout = {
			sizing = sizing,
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(PANEL_PADDING),
			childGap = 2,
		},
		backgroundColor = colors.panel,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
		clip = {horizontal = clip, vertical = clip},
	}
}

@(private = "file")
panel_title :: proc(title: string) {
	colors := palette()
	if clay.UI()({layout = {padding = {bottom = 6}}}) {
		clay.TextDynamic(title, text_config(.Title, colors.title))
	}
}

// Disassembly of the instructions around the PC, current one highlighted.
@(private = "file")
code_panel :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("CodePanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()})) {
		panel_title("Code")

		lines := visible_code_lines()
		lines_before_pc := u64(lines / 3)

		pc := session.machine.cpu.pc
		code_start, end := session_code_range(session)
		first := pc - lines_before_pc * rv.INSTRUCTION_SIZE
		if pc < code_start + lines_before_pc * rv.INSTRUCTION_SIZE {
			first = code_start
		}

		buffer: [rv.DISASM_BUFFER_SIZE]u8
		for line in 0 ..< lines {
			address := first + u64(line) * rv.INSTRUCTION_SIZE
			if address + rv.INSTRUCTION_SIZE > end {
				break
			}
			raw, _ := rv.bus_load(&session.machine.bus, address, 4)
			instruction := u32(raw)
			text := fmt.tprintf(
				"%s %08x  %08x  %s",
				">" if address == pc else " ",
				address,
				instruction,
				rv.disassemble(buffer[:], address, instruction),
			)
			highlight := colors.current_line if address == pc else COLOR_NONE
			if clay.UI(clay.ID("CodeLine", u32(line)))({
				layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
				backgroundColor = highlight,
				cornerRadius = clay.CornerRadiusAll(3),
			}) {
				clay.TextDynamic(text, text_config(.Code, colors.text))
			}
		}
	}
}

// The instruction at the PC as 32 bits split into colour-coded fields
// (see encoding.odin), each with its name and meaning underneath.
@(private = "file")
encoding_panel :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("EncodingPanel"))(panel_style({clay.SizingGrow(), clay.SizingFit()})) {
		panel_title("Encoding")

		pc := session.machine.cpu.pc
		raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
		if !ok {
			clay.TextDynamic("pc is outside memory", text_config(.Text, colors.text_dim))
			return
		}
		instruction := u32(raw)
		encoding := encoding_of(instruction)

		if clay.UI(clay.ID("EncodingFields"))({layout = {childGap = 16, padding = {top = 4, bottom = 6}}}) {
			for field, index in encoding.fields[:encoding.field_count] {
				encoding_field(instruction, field, u32(index))
			}
		}
		clay.TextDynamic(encoding_summary(pc, instruction, encoding), text_config(.Text, colors.text))
	}
}

// One field as a small column: bits (in the field's colour), name, meaning.
@(private = "file")
encoding_field :: proc(instruction: u32, field: Encoding_Field, index: u32) {
	colors := palette()
	if clay.UI(clay.ID("EncodingField", index))({layout = {layoutDirection = .TopToBottom, childGap = 2}}) {
		clay.TextDynamic(field_bits_text(instruction, field), text_config(.Code, colors.fields[field.kind]))
		clay.TextDynamic(field.label, text_config(.Code_Small, colors.fields[field.kind]))
		clay.TextDynamic(field_value_text(instruction, field), text_config(.Code_Small, colors.text_dim))
	}
}

// How many code lines fit, from the code panel's height last frame.
@(private = "file")
visible_code_lines :: proc() -> int {
	panel := clay.GetElementData(clay.ID("CodePanel"))
	if !panel.found {
		return CODE_LINES_DEFAULT
	}
	return max(3, int(panel.boundingBox.height - CODE_PANEL_OVERHEAD) / CODE_LINE_HEIGHT)
}

// Tabs on top, the selected tab's content below. The content scrolls with
// the mouse wheel when it is taller than the panel.
@(private = "file")
side_panel :: proc(session: ^Session) {
	// No clip on the panel itself: SideContent is the scrolling area.
	if clay.UI(clay.ID("SidePanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()}, clip = false)) {
		if clay.UI(clay.ID("Tabs"))({layout = {childGap = 8, padding = {bottom = 8}}}) {
			tab(TAB_ID_REGISTERS, "Registers", view.side_tab == .Registers)
			tab(TAB_ID_PROGRAM, "Program", view.side_tab == .Program)
		}
		if clay.UI(clay.ID("SideContent"))({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
			clip = {horizontal = true, vertical = true, childOffset = clay.GetScrollOffset()},
		}) {
			switch view.side_tab {
			case .Registers:
				register_list(session)
			case .Program:
				program_info(session)
			}
		}
	}
}

@(private = "file")
tab :: proc(id: string, label: string, selected: bool) {
	colors := palette()
	element_id := clay.ID(id)
	background := colors.button
	if selected {
		background = colors.current_line
	} else if clay.PointerOver(element_id) {
		background = colors.button_hover
	}
	if clay.UI(element_id)({
		layout = {padding = {14, 14, 5, 5}},
		backgroundColor = background,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic(label, text_config(.Text, colors.button_text if selected else colors.text_dim))
	}
}

// What the loader found: format, entry point, code range, tohost.
@(private = "file")
program_info :: proc(session: ^Session) {
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
		program_line("tohost", tohost)
	}
}

@(private = "file")
program_line :: proc(label: string, value: string) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 1}}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(80)}}}) {
			clay.TextDynamic(label, text_config(.Code_Small, colors.text_dim))
		}
		clay.TextDynamic(value, text_config(.Code_Small, colors.text))
	}
}

// All 32 registers with ABI names; the one the last step wrote is marked.
@(private = "file")
register_list :: proc(session: ^Session) {
	colors := palette()
	{
		cpu := &session.machine.cpu
		changed_index := -1
		if record, has_record := session.last_step.?; has_record && record.register_changed {
			changed_index = int(record.register_index)
		}

		for index in 0 ..< rv.REGISTER_COUNT {
			value := cpu.regs[index]
			text := fmt.tprintf(
				"x%-2d %-4s 0x%016x  %s",
				index,
				rv.register_name(u32(index)),
				value,
				value_text(value),
			)
			highlight := colors.changed if index == changed_index else COLOR_NONE
			if clay.UI(clay.ID("RegisterLine", u32(index)))({
				layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 1}},
				backgroundColor = highlight,
				cornerRadius = clay.CornerRadiusAll(3),
			}) {
				clay.TextDynamic(text, text_config(.Code_Small, colors.text))
			}
		}
	}
}

// Status, what the next instruction will do, and what the last one did.
@(private = "file")
explanation_panel :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("ExplanationPanel"))(panel_style({clay.SizingGrow(), clay.SizingFit()})) {
		status_color := colors.stopped if session.stopped != nil else colors.text
		explanation_line("Status", explain_status(session), status_color)
		explanation_line("Next", explain_next(session), colors.text)
		explanation_line("Last", explain_last_step(session), colors.text)
	}
}

@(private = "file")
explanation_line :: proc(label: string, text: string, color: clay.Color) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 10, padding = {top = 2, bottom = 2}}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(80)}}}) {
			clay.TextDynamic(label, text_config(.Text, colors.accent))
		}
		clay.TextDynamic(text, text_config(.Text, color))
	}
}
