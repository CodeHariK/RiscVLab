package rvdbg

import "core:fmt"
import clay "../vendor/clay-odin"
import rv "../core"

// The debugger window, described with Clay:
//
//   +------------------------------------------------------------+
//   | [Start] [Prev] [Next]   program   step   pc                |  toolbar
//   +-----------------------------------+------------------------+
//   | Code: disassembly around the PC   | Registers: x0..x31     |
//   | (current instruction highlighted) | (last change marked)   |
//   +-----------------------------------+------------------------+
//   | Status / Next / Last step (small text)                     |  explanation
//   +------------------------------------------------------------+
//
// Built from scratch every frame from the session state; strings use the
// temp allocator, freed once the frame is drawn.

// Instructions shown in the code panel, and how many come before the PC.
CODE_LINES :: 30
CODE_LINES_BEFORE_PC :: 10

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
			code_panel(session)
			register_panel(session)
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

// Look shared by the three panels.
@(private = "file")
panel_style :: proc(sizing: clay.Sizing) -> clay.ElementDeclaration {
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
		clip = {horizontal = true, vertical = true},
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
	if clay.UI(clay.ID("CodePanel"))(panel_style({clay.SizingPercent(0.58), clay.SizingGrow()})) {
		panel_title("Code")

		pc := session.machine.cpu.pc
		first := pc - CODE_LINES_BEFORE_PC * rv.INSTRUCTION_SIZE
		if pc < rv.RAM_BASE + CODE_LINES_BEFORE_PC * rv.INSTRUCTION_SIZE {
			first = rv.RAM_BASE
		}
		end := session_program_end(session)

		buffer: [rv.DISASM_BUFFER_SIZE]u8
		for line in 0 ..< CODE_LINES {
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

// All 32 registers with ABI names; the one the last step wrote is marked.
@(private = "file")
register_panel :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("RegisterPanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()})) {
		panel_title("Registers")

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
