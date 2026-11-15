package rvdbg

import "core:fmt"
import "core:strings"
import clay "../vendor/clay-odin"
import rv "../core"
import rl "vendor:raylib"

// The debugger window, described with Clay:
//
//   +------------------------------------------------------------+
//   | [Reset] [Prev] [Next]   program   step   pc                |  toolbar
//   +-----------------------------------+------------------------+
//   | [Source][Disassembly][Steps]      | [Programs][Regs][CSRs].|
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

// The code panel shows as many lines as fit (see first_visible_index for
// how it scrolls). Heights in pixels, matching the styles used below.
CODE_LINE_HEIGHT :: 24 // Code font (18) + line padding (4) + gap (2)
SOURCE_LINE_HEIGHT :: 22 // Code_Small font (16) + line padding (4) + gap (2)
CODE_PANEL_OVERHEAD :: 76 // tabs, panel padding and border
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
		panel_area(session)
	}
	if panel, dragging := panel_layout.dragging_panel.?; dragging {
		drag_label(panel)
	}
	return clay.EndLayout(frame_time)
}

// The columns, the bottom panel and the dividers between them (see
// panel_layout.odin).
@(private = "file")
panel_area :: proc(session: ^Session) {
	layout := &panel_layout
	if clay.UI(clay.ID("Content"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
		if clay.UI(clay.ID("Main"))({layout = {sizing = {clay.SizingGrow(), clay.SizingPercent(layout.main_height)}}}) {
			for index in 0 ..< layout.column_count {
				column := layout.columns[index]
				is_last := index == layout.column_count - 1
				width := clay.SizingGrow() if is_last else clay.SizingPercent(column.width)
				if clay.UI(column_id(index))({layout = {sizing = {width, clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
					if column.has_bottom {
						slot(session, {column = index}, {clay.SizingGrow(), clay.SizingPercent(column.split)})
						divider({.Column_Rows, index})
						slot(session, {column = index, lower = true}, {clay.SizingGrow(), clay.SizingGrow()})
					} else {
						slot(session, {column = index}, {clay.SizingGrow(), clay.SizingGrow()})
					}
				}
				if !is_last {
					divider({.Column_Edge, index})
				}
			}
		}
		divider({.Main_Bottom, 0})
		if clay.UI(clay.ID("BottomRow"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}}}) {
			if layout.bottom_count == 2 {
				slot(session, {column = -1}, {clay.SizingPercent(layout.bottom_split), clay.SizingGrow()})
				divider({.Bottom_Edge, 0})
				slot(session, {column = -1, lower = true}, {clay.SizingGrow(), clay.SizingGrow()})
			} else {
				slot(session, {column = -1}, {clay.SizingGrow(), clay.SizingGrow()})
			}
		}
	}
}

// One slot, showing whichever panel is assigned to it. While a panel is
// dragged, the slot under the mouse is outlined as the drop target.
@(private = "file")
slot :: proc(session: ^Session, slot: Slot, sizing: clay.Sizing) {
	colors := palette()
	outline: clay.BorderElementConfig
	if dragged, dragging := panel_layout.dragging_panel.?; dragging && clay.PointerOver(slot_id(slot)) {
		if source, shown := slot_of(dragged).?; shown && source != slot {
			outline = {colors.accent, clay.BorderOutside(4)}
		}
	}
	if clay.UI(slot_id(slot))({layout = {sizing = sizing}, border = outline, cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS)}) {
		switch panel_in(slot) {
		case .Code:
			code_panel(session)
		case .Encoding:
			encoding_panel(session)
		case .Side:
			side_panel(session)
		case .Registers:
			registers_panel(session)
		case .Explanation:
			explanation_panel(session)
		}
	}
}

// The gap between two slots: a bar appears in it on hover or while
// dragging.
@(private = "file")
divider :: proc(divider: Divider) {
	colors := palette()
	vertical := divider.kind == .Column_Edge || divider.kind == .Bottom_Edge
	sizing := clay.Sizing{clay.SizingGrow(), clay.SizingFixed(DIVIDER_THICKNESS)}
	bar := clay.Sizing{clay.SizingGrow(), clay.SizingFixed(4)}
	if vertical {
		sizing = clay.Sizing{clay.SizingFixed(DIVIDER_THICKNESS), clay.SizingGrow()}
		bar = clay.Sizing{clay.SizingFixed(4), clay.SizingGrow()}
	}
	active := panel_layout.dragging_divider == divider || clay.PointerOver(divider_id(divider))
	if clay.UI(divider_id(divider))({layout = {sizing = sizing, childAlignment = {x = .Center, y = .Center}}}) {
		if active {
			if clay.UI()({layout = {sizing = bar}, backgroundColor = colors.accent, cornerRadius = clay.CornerRadiusAll(2)}) {}
		}
	}
}

// The register list as a panel of its own (the middle column),
// scrolling with the mouse wheel when it doesn't fit.
@(private = "file")
registers_panel :: proc(session: ^Session) {
	if clay.UI(clay.ID("RegistersPanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()}, clip = false)) {
		panel_header(.Registers, "Registers")
		if clay.UI(clay.ID("RegistersContent"))({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
			clip = {horizontal = true, vertical = true, childOffset = clay.GetScrollOffset()},
		}) {
			register_list(session)
		}
	}
}

// The handle a panel is dragged by: "::" at the start of its header.
@(private = "file")
panel_grip :: proc(panel: Panel) {
	colors := palette()
	color := colors.title if clay.PointerOver(grip_id(panel)) else colors.text_dim
	if clay.UI(grip_id(panel))({layout = {padding = {2, 8, 2, 2}, childAlignment = {y = .Center}}}) {
		clay.TextDynamic("::", text_config(.Title, color))
	}
}

// A panel's header: its grip and its title.
@(private = "file")
panel_header :: proc(panel: Panel, title: string) {
	colors := palette()
	if clay.UI()({layout = {padding = {bottom = 6}, childAlignment = {y = .Center}}}) {
		panel_grip(panel)
		clay.TextDynamic(title, text_config(.Title, colors.title))
	}
}

// Follows the mouse while a panel is dragged.
@(private = "file")
drag_label :: proc(panel: Panel) {
	colors := palette()
	mouse := rl.GetMousePosition()
	if clay.UI(clay.ID("DragLabel"))({
		layout = {padding = {10, 10, 6, 6}},
		floating = {attachTo = .Root, offset = {mouse.x + 16, mouse.y + 16}, zIndex = 100},
		backgroundColor = colors.panel,
		border = {colors.accent, clay.BorderOutside(BORDER_WIDTH)},
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
	}) {
		clay.TextDynamic(fmt.tprintf("Move %s: drop it on another panel to swap", panel_names[panel]), text_config(.Text, colors.text))
	}
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
		button(BUTTON_ID_RESET, "Reset")
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

// The code panel: the program's source (with its comments), its
// disassembly or the steps taken, whichever tab is selected.
@(private = "file")
code_panel :: proc(session: ^Session) {
	if clay.UI(clay.ID("CodePanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()})) {
		// Without a source map, the Source tab falls back to Disassembly.
		shown := view.code_tab
		if shown == .Source && !session.has_source {
			shown = .Disassembly
		}
		if clay.UI(clay.ID("CodeTabs"))({layout = {childGap = 8, padding = {bottom = 8}, childAlignment = {y = .Center}}}) {
			panel_grip(.Code)
			if session.has_source {
				tab(TAB_ID_SOURCE, "Source", shown == .Source)
			}
			tab(TAB_ID_DISASSEMBLY, "Disassembly", shown == .Disassembly)
			tab(TAB_ID_STEPS, "Steps", shown == .Steps)
		}
		switch shown {
		case .Source:
			source_view(session)
		case .Disassembly:
			disassembly_view(session)
		case .Steps:
			steps_view(session)
		}
	}
}

// The source file around the current instruction's line: line numbers,
// code, and comments in a dimmer colour.
@(private = "file")
source_view :: proc(session: ^Session) {
	colors := palette()
	source := &session.source
	current, known := source_line_at(source, session.machine.cpu.pc)
	if !known {
		clay.TextDynamic(
			fmt.tprintf("pc 0x%x has no source line (see the Disassembly tab)", session.machine.cpu.pc),
			text_config(.Text, colors.text_dim),
		)
		return
	}

	lines := visible_lines(SOURCE_LINE_HEIGHT)
	total := len(source.lines)
	first := 1 + first_visible_index(current - 1, lines, total)
	for number in first ..< min(first + lines, total + 1) {
		text := source.lines[number - 1]
		code, comment := split_comment(text)
		is_current := number == current
		if clay.UI(clay.ID("SourceLine", u32(number - first)))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
			backgroundColor = colors.current_line if is_current else COLOR_NONE,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			marker := ">" if is_current else " "
			clay.TextDynamic(fmt.tprintf("%s%4d  ", marker, number), text_config(.Code_Small, colors.text_dim))
			if code != "" {
				clay.TextDynamic(code, text_config(.Code_Small, colors.text))
			}
			if comment != "" {
				clay.TextDynamic(comment, text_config(.Code_Small, colors.accent))
			}
		}
	}
}

// The steps taken so far (as many as fit, oldest at the top), then the
// instruction that Next will run, highlighted like the current line in
// the other views.
@(private = "file")
steps_view :: proc(session: ^Session) {
	colors := palette()
	count := len(session.timeline)
	lines := visible_lines(SOURCE_LINE_HEIGHT) - 1 // keep a line for "next"
	newest_first := max(0, count - lines)
	wanted := newest_first + int(view.code_scroll)
	first := max(0, min(wanted, newest_first))
	if first != wanted {
		view.code_scroll = f32(first - newest_first)
	}
	for index in first ..< count {
		if clay.UI(clay.ID("StepLine", u32(index - first)))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}}}) {
			clay.TextDynamic(timeline_text(index + 1, session.timeline[index]), text_config(.Code_Small, colors.text))
		}
	}

	if clay.UI(clay.ID("StepNext"))({
		layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
		backgroundColor = colors.current_line,
		cornerRadius = clay.CornerRadiusAll(3),
	}) {
		clay.TextDynamic(next_step_text(session, count + 1), text_config(.Code_Small, colors.text))
	}
}

// The line for the instruction at the PC, not run yet.
@(private = "file")
next_step_text :: proc(session: ^Session, number: int) -> string {
	if session.stopped != nil || session.exited != nil {
		return "(program finished: press Prev to step back or Reset to run again)"
	}
	pc := session.machine.cpu.pc
	raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
	if !ok {
		return fmt.tprintf("next: pc 0x%x is outside memory", pc)
	}
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	text := rv.disassemble(buffer[:], pc, u32(raw))
	return fmt.tprintf(">%-4d %08x  %-24s (next: press Next to run it)", number, pc, text)
}

// Splits an assembly line at its "#" comment: ("addi t0, zero, 5   ", "# t0 = 5").
@(private = "file")
split_comment :: proc(line: string) -> (code: string, comment: string) {
	if hash := strings.index_byte(line, '#'); hash >= 0 {
		return line[:hash], line[hash:]
	}
	return line, ""
}

// Disassembly of the instructions around the PC, current one highlighted.
@(private = "file")
disassembly_view :: proc(session: ^Session) {
	colors := palette()
	lines := visible_lines(CODE_LINE_HEIGHT)
	pc := session.machine.cpu.pc
	code_start, end := session_code_range(session)
	first := code_start
	if pc >= code_start && pc < end {
		pc_index := int((pc - code_start) / rv.INSTRUCTION_SIZE)
		total := int((end - code_start) / rv.INSTRUCTION_SIZE)
		first = code_start + u64(first_visible_index(pc_index, lines, total)) * rv.INSTRUCTION_SIZE
	}

	// Symbol labels (e.g. "test_2:") take a line of their own, so count
	// lines drawn rather than instructions.
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	drawn := 0
	for line := 0; drawn < lines; line += 1 {
		address := first + u64(line) * rv.INSTRUCTION_SIZE
		if address + rv.INSTRUCTION_SIZE > end {
			break
		}
		if label := symbol_names_at(session, address); label != "" {
			if clay.UI(clay.ID("CodeLabel", u32(line)))({layout = {padding = {6, 6, 4, 0}}}) {
				clay.TextDynamic(fmt.tprintf("%s:", label), text_config(.Code, colors.title))
			}
			drawn += 1
		}
		drawn += 1
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

// The instruction at the PC as 32 bits split into colour-coded fields
// (see encoding.odin), each with its name and meaning underneath.
@(private = "file")
encoding_panel :: proc(session: ^Session) {
	colors := palette()
	if clay.UI(clay.ID("EncodingPanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()})) {
		panel_header(.Encoding, "Encoding")

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

// Which line to start at so the `current` one (0-based) is on screen,
// scrolling as little as possible: start at the top, and only scroll once
// the current line would pass two thirds of the way down. Never scroll
// past the end, so a file that fits is always shown from its first line.
//
// The mouse wheel shifts that by view.code_scroll lines, to look at the
// rest of the program (the next step scrolls back).
@(private = "file")
first_visible_index :: proc(current: int, lines: int, total: int) -> int {
	keep_below := lines / 3 // lines kept visible after the current one
	following := max(0, min(current - (lines - 1 - keep_below), total - lines))
	wanted := following + int(view.code_scroll)
	first := max(0, min(wanted, total - lines))
	// At the top or bottom, stop the scroll growing, so scrolling back
	// responds straight away. (Otherwise keep its fraction: a trackpad
	// sends small amounts.)
	if first != wanted {
		view.code_scroll = f32(first - following)
	}
	return first
}

// How many lines of `line_height` pixels fit in the code panel, from its
// height last frame.
@(private = "file")
visible_lines :: proc(line_height: int) -> int {
	panel := clay.GetElementData(clay.ID("CodePanel"))
	if !panel.found {
		return CODE_LINES_DEFAULT
	}
	return max(3, int(panel.boundingBox.height - CODE_PANEL_OVERHEAD) / line_height)
}

// Tabs on top, the selected tab's content below. The content scrolls with
// the mouse wheel when it is taller than the panel.
@(private = "file")
side_panel :: proc(session: ^Session) {
	// No clip on the panel itself: SideContent is the scrolling area.
	if clay.UI(clay.ID("SidePanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()}, clip = false)) {
		if clay.UI(clay.ID("Tabs"))({layout = {childGap = 8, padding = {bottom = 8}, childAlignment = {y = .Center}}}) {
			panel_grip(.Side)
			tab(TAB_ID_PROGRAMS, "Programs", view.side_tab == .Programs)
			tab(TAB_ID_CSRS, "CSRs", view.side_tab == .Csrs)
			tab(TAB_ID_MEMORY, "Memory", view.side_tab == .Memory)
			tab(TAB_ID_ELF, "ELF", view.side_tab == .Elf)
		}
		if clay.UI(clay.ID("SideContent"))({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
			clip = {horizontal = true, vertical = true, childOffset = clay.GetScrollOffset()},
		}) {
			switch view.side_tab {
			case .Csrs:
				csr_list(session)
			case .Memory:
				memory_list(session)
			case .Elf:
				program_info(session)
			case .Programs:
				program_list()
			}
		}
	}
}

// A tab button (also used by the Memory tab's Words / Bytes switch).
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
		layout = {padding = {10, 10, 5, 5}},
		backgroundColor = background,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic(label, text_config(.Text, colors.button_text if selected else colors.text_dim))
	}
}

// The program selector: every program in the catalog, grouped, with its
// title and one-line description. Clicking one opens it (input.odin).
@(private = "file")
program_list :: proc() {
	colors := palette()
	if len(catalog.entries) == 0 {
		clay.TextDynamic("No program list: start rvdbg with --tests <tests folder>.", text_config(.Text, colors.text_dim))
		return
	}

	previous_group := -1
	for entry, index in catalog.entries {
		if int(entry.group) != previous_group {
			previous_group = int(entry.group)
			if clay.UI(clay.ID("ProgramGroup", u32(entry.group)))({layout = {padding = {4, 4, 10, 4}}}) {
				clay.TextDynamic(catalog_group_names[entry.group], text_config(.Title, colors.title))
			}
		}

		element_id := clay.ID(PROGRAM_ROW_ID, u32(index))
		background := COLOR_NONE
		if index == view.selected_program {
			background = colors.current_line
		} else if clay.PointerOver(element_id) {
			background = colors.button_hover
		}
		if clay.UI(element_id)({
			layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {8, 8, 4, 4}, childGap = 2},
			backgroundColor = background,
			cornerRadius = clay.CornerRadiusAll(4),
		}) {
			clay.TextDynamic(entry.title, text_config(.Text, colors.text))
			if entry.description != "" {
				clay.TextDynamic(entry.description, text_config(.Code_Small, colors.text_dim))
			}
		}
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
		data := "none"
		if program.data_end > program.data_start {
			data = fmt.tprintf("0x%x - 0x%x (%d bytes)", program.data_start, program.data_end, program.data_end - program.data_start)
		}
		program_line("data", data)
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

// The privilege level and every implemented CSR (see csr_view.odin),
// with whatever the last step changed highlighted.
@(private = "file")
csr_list :: proc(session: ^Session) {
	colors := palette()
	cpu := &session.machine.cpu

	privilege_text := fmt.tprintf("%-9s %v", "privilege", cpu.privilege)
	if clay.UI(clay.ID("PrivilegeLine"))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 6}}}) {
		clay.TextDynamic(privilege_text, text_config(.Code_Small, colors.text))
	}

	for address, index in csr_view_order {
		value, _ := rv.csr_read(cpu, address)
		// Two lines per CSR, so the panel doesn't need to be wide:
		//   mstatus   0x300 0x0000000000001880
		//             MIE=0 MPIE=1 MPP=Machine
		text := fmt.tprintf("%-9s 0x%03x 0x%016x", rv.csr_name(address), address, value)
		meaning := fmt.tprintf("%-9s %s", "", csr_meaning(cpu, address, value))
		highlight := colors.changed if csr_changed_by_last_step(session, address) else COLOR_NONE
		if clay.UI(clay.ID("CsrLine", u32(index)))({
			layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {6, 6, 2, 2}},
			backgroundColor = highlight,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			clay.TextDynamic(text, text_config(.Code_Small, colors.text))
			clay.TextDynamic(meaning, text_config(.Code_Small, colors.text_dim))
		}
	}
}

// The pc, then all 32 registers with ABI names. A tag shows what the next instruction
// does with each register (reads it as rs1 / rs2, writes it as rd), in the
// Encoding strip's colours; the register the last step wrote is marked.
@(private = "file")
register_list :: proc(session: ^Session) {
	colors := palette()
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
		clay.TextDynamic(fmt.tprintf("%-3s %-4s %s", "pc", "", register_value_text(cpu.pc)), text_config(.Code_Small, colors.accent))
	}

	for index in 0 ..< rv.REGISTER_COUNT {
		value := cpu.regs[index]
		text := fmt.tprintf("x%-2d %-4s %s", index, rv.register_name(u32(index)), register_value_text(value))
		use := Register_Use.None
		if fetched {
			use = register_use(u32(next_instruction), u32(index))
		}
		highlight := colors.changed if index == changed_index else COLOR_NONE
		if clay.UI(clay.ID("RegisterLine", u32(index)))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 1, 1}},
			backgroundColor = highlight,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			register_use_tag(use)
			clay.TextDynamic(text, text_config(.Code_Small, colors.text))
		}
	}
}

// "rs1" / "rs2" / "rd" in the field's colour, or blank, in a fixed width.
@(private = "file")
register_use_tag :: proc(use: Register_Use) {
	colors := palette()
	label, color := "", colors.text
	switch use {
	case .Read_Rs1:
		label, color = "rs1", colors.fields[.Rs1]
	case .Read_Rs2:
		label, color = "rs2", colors.fields[.Rs2]
	case .Write_Rd:
		label, color = "rd", colors.fields[.Rd]
	case .None:
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(36)}}}) {
		if label != "" {
			clay.TextDynamic(label, text_config(.Code_Small, color))
		}
	}
}

// Status, what the last step did (one line), and every stage of the
// instruction Next will run, results included (step_detail.odin, from
// session.preview). Scrolls when it doesn't fit.
@(private = "file")
explanation_panel :: proc(session: ^Session) {
	colors := palette()
	// No clip on the panel itself: ExplanationContent is the scrolling area.
	if clay.UI(clay.ID("ExplanationPanel"))(panel_style({clay.SizingGrow(), clay.SizingGrow()}, clip = false)) {
		panel_header(.Explanation, "Explanation")
		if clay.UI(clay.ID("ExplanationContent"))({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom},
			clip = {horizontal = true, vertical = true, childOffset = clay.GetScrollOffset()},
		}) {
			status_color := colors.stopped if session.stopped != nil || session.exited != nil else colors.text
			explanation_line("Status", explain_status(session), status_color)
			last_step_line(session)
			next_step_details(session)
		}
	}
}

// The newest step in one line, as in the Steps tab.
@(private = "file")
last_step_line :: proc(session: ^Session) {
	colors := palette()
	if len(session.timeline) == 0 {
		explanation_line("Last", "-", colors.text)
		return
	}
	number := len(session.timeline)
	explanation_line("Last", timeline_text(number, session.timeline[number - 1]), colors.text_dim)
}

// The stages of the instruction Next will run.
@(private = "file")
next_step_details :: proc(session: ^Session) {
	colors := palette()
	entry, has_preview := session.preview.?
	if !has_preview {
		explanation_line("Next", "-", colors.text)
		return
	}
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	heading := fmt.tprintf("step #%d: %s", len(session.timeline) + 1, rv.disassemble(buffer[:], entry.pc, entry.instruction))
	explanation_line("Next", heading, colors.text)
	detail := step_detail(session, entry)
	for stage in Stage {
		if detail[stage] != "" {
			explanation_line(stage_names[stage], detail[stage], colors.text)
		}
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
