package view

import "core:fmt"
import "core:strings"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Steps tab of the code panel, in one of two modes (switch at the top):
//
// Both modes list the newest step first: the instruction Next will run
// (highlighted like the current line in the other views), then the step
// just run, and so on back to step #1. The steps that matter most are
// always at the top, and the wheel scrolls back in time.
//
// Compact: one line per step, 3 lines per wheel notch.
//
// Detailed: every step with all its stages (step_detail.odin): the source
// line, fetch, decode, read, execute, memory and write. One step
// per wheel notch.

TAB_ID_STEPS_COMPACT :: "StepsCompactTab"
TAB_ID_STEPS_DETAILED :: "StepsDetailedTab"

// Width of the stage names ("execute", "next pc") in detailed mode.
STAGE_LABEL_WIDTH :: 80

tab_steps :: proc(session: ^state.Session) {
	if clay.UI(clay.ID("StepsMode"))({layout = {childGap = 8, padding = {bottom = 6}}}) {
		ui.tab(TAB_ID_STEPS_COMPACT, "Compact", !display.steps_detailed)
		ui.tab(TAB_ID_STEPS_DETAILED, "Detailed", display.steps_detailed)
	}
	if display.steps_detailed {
		detailed_steps(session)
	} else {
		compact_steps(session)
	}
}

// Scrolling skips the newest `display.code_scroll` lines (the coming step
// counts as one).
@(private)
compact_steps :: proc(session: ^state.Session) {
	colors := ui.palette()
	count := len(session.timeline)
	lines := count + 1 // the coming step, then every step run
	shown := visible_lines(SOURCE_LINE_HEIGHT) - 2 // the mode switch is about two lines
	display.code_scroll = clamp(display.code_scroll, 0, f32(max(0, lines - shown)))
	skip := int(display.code_scroll)

	row := 0
	if skip == 0 {
		if clay.UI(clay.ID("StepNext"))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
			backgroundColor = colors.current_line,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			clay.TextDynamic(next_step_text(session, session.timeline_dropped + count + 1), ui.text_config(.Code_Small, colors.text))
		}
		row += 1
	}
	for index := count - 1 - max(0, skip - 1); index >= 0 && row < shown; index -= 1 {
		if clay.UI(clay.ID("StepLine", u32(row)))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}}}) {
			clay.TextDynamic(timeline_text(session.timeline_dropped + index + 1, session.timeline[index]), ui.text_config(.Code_Small, colors.text))
		}
		row += 1
	}
}

// The line for the instruction at the PC, not run yet: what it will do
// (from the preview), or why there is nothing to run.
@(private)
next_step_text :: proc(session: ^state.Session, number: int) -> string {
	if session.stopped != nil || session.exited != nil {
		return "(program finished: press Prev to step back or Reset to run again)"
	}
	if entry, has_preview := session.preview.?; has_preview {
		return timeline_text(number, entry, coming = true)
	}
	pc := session.machine.cpu.pc
	raw, ok := rv.bus_peek(&session.machine.bus, pc, 4)
	if !ok {
		return fmt.tprintf("next: pc 0x%x is outside memory", pc)
	}
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], pc, u32(raw))
	return fmt.tprintf(">%-4d %08x  %-24s (next: press Next to run it)", number, pc, text)
}

// Newest first: the coming step, then the steps already run. Scrolling
// skips the newest `display.code_scroll` blocks (the coming one counts too).
@(private)
detailed_steps :: proc(session: ^state.Session) {
	count := len(session.timeline)
	blocks := count + 1 // the coming step, or the "finished" line
	display.code_scroll = clamp(display.code_scroll, 0, f32(blocks - 1))
	skip := int(display.code_scroll)
	// Every block is at least one line tall, so this many always fill the
	// panel; the panel clips whatever doesn't fit.
	shown := visible_lines(SOURCE_LINE_HEIGHT)

	block := 0
	if skip == 0 {
		next_step_block(session, session.timeline_dropped + count + 1)
		block += 1
	}
	for index := count - 1 - max(0, skip - 1); index >= 0 && block < shown; index -= 1 {
		step_block(session, session.timeline_dropped + index + 1, session.timeline[index], false)
		block += 1
	}
}

// The step Next will run, from the preview (session.preview).
@(private)
next_step_block :: proc(session: ^state.Session, number: int) {
	entry, has_preview := session.preview.?
	if !has_preview {
		colors := ui.palette()
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}}}) {
			clay.TextDynamic(next_step_text(session, number), ui.text_config(.Code_Small, colors.text))
		}
		return
	}
	step_block(session, number, entry, true)
}

// One step: a heading line, then its source line and stages.
@(private)
step_block :: proc(session: ^state.Session, number: int, entry: state.Timeline_Entry, coming: bool) {
	colors := ui.palette()
	if clay.UI()({
		layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {6, 6, 4, 6}, childGap = 1},
		backgroundColor = colors.current_line if coming else ui.COLOR_NONE,
		cornerRadius = clay.CornerRadiusAll(3),
	}) {
		buffer: [disasm.BUFFER_SIZE]u8
		text := disasm.disassemble(buffer[:], entry.pc, entry.instruction)
		marker := ">" if coming else "#"
		note := "  (next: press Next to run it)" if coming else ""
		heading := fmt.tprintf("%s%-4d %08x  %s%s", marker, number, entry.pc, text, note)
		clay.TextDynamic(heading, ui.text_config(.Code_Small, colors.text))

		if source := source_text_at(session, entry.pc); source != "" {
			stage_row("source", source, colors.accent)
		}
		detail := step_detail(session, entry)
		for stage in Stage {
			if detail[stage] != "" {
				stage_row(stage_names[stage], detail[stage], colors.text)
			}
		}
	}
}

@(private)
stage_row :: proc(label: string, text: string, color: clay.Color) {
	colors := ui.palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {left = 24}, childGap = 8}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(STAGE_LABEL_WIDTH)}}}) {
			clay.TextDynamic(label, ui.text_config(.Code_Small, colors.text_dim))
		}
		clay.TextDynamic(text, ui.text_config(.Code_Small, color))
	}
}

// "0022  lw t2, 0(t0)  # t2 = ..." for the source line of `address`, or "".
@(private)
source_text_at :: proc(session: ^state.Session, address: u64) -> string {
	if !session.has_source {
		return ""
	}
	line, known := state.source_line_at(&session.source, address)
	if !known || line < 1 || line > len(session.source.lines) {
		return ""
	}
	return fmt.tprintf("%04d  %s", line, strings.trim_space(session.source.lines[line - 1]))
}
