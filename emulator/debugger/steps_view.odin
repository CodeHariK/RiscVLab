package rvdbg

import "core:fmt"
import "core:strings"
import clay "../vendor/clay-odin"
import rv "../core"
import disasm "../disasm"

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

steps_view :: proc(session: ^Session) {
	if clay.UI(clay.ID("StepsMode"))({layout = {childGap = 8, padding = {bottom = 6}}}) {
		tab(TAB_ID_STEPS_COMPACT, "Compact", !view.steps_detailed)
		tab(TAB_ID_STEPS_DETAILED, "Detailed", view.steps_detailed)
	}
	if view.steps_detailed {
		detailed_steps(session)
	} else {
		compact_steps(session)
	}
}

// Scrolling skips the newest `view.code_scroll` lines (the coming step
// counts as one).
@(private = "file")
compact_steps :: proc(session: ^Session) {
	colors := palette()
	count := len(session.timeline)
	lines := count + 1 // the coming step, then every step run
	shown := visible_lines(SOURCE_LINE_HEIGHT) - 2 // the mode switch is about two lines
	view.code_scroll = clamp(view.code_scroll, 0, f32(max(0, lines - shown)))
	skip := int(view.code_scroll)

	row := 0
	if skip == 0 {
		if clay.UI(clay.ID("StepNext"))({
			layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}},
			backgroundColor = colors.current_line,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			clay.TextDynamic(next_step_text(session, count + 1), text_config(.Code_Small, colors.text))
		}
		row += 1
	}
	for index := count - 1 - max(0, skip - 1); index >= 0 && row < shown; index -= 1 {
		if clay.UI(clay.ID("StepLine", u32(row)))({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}}}) {
			clay.TextDynamic(timeline_text(index + 1, session.timeline[index]), text_config(.Code_Small, colors.text))
		}
		row += 1
	}
}

// The line for the instruction at the PC, not run yet: what it will do
// (from the preview), or why there is nothing to run.
@(private = "file")
next_step_text :: proc(session: ^Session, number: int) -> string {
	if session.stopped != nil || session.exited != nil {
		return "(program finished: press Prev to step back or Reset to run again)"
	}
	if entry, has_preview := session.preview.?; has_preview {
		return timeline_text(number, entry, coming = true)
	}
	pc := session.machine.cpu.pc
	raw, ok := rv.bus_load(&session.machine.bus, pc, 4)
	if !ok {
		return fmt.tprintf("next: pc 0x%x is outside memory", pc)
	}
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], pc, u32(raw))
	return fmt.tprintf(">%-4d %08x  %-24s (next: press Next to run it)", number, pc, text)
}

// Newest first: the coming step, then the steps already run. Scrolling
// skips the newest `view.code_scroll` blocks (the coming one counts too).
@(private = "file")
detailed_steps :: proc(session: ^Session) {
	count := len(session.timeline)
	blocks := count + 1 // the coming step, or the "finished" line
	view.code_scroll = clamp(view.code_scroll, 0, f32(blocks - 1))
	skip := int(view.code_scroll)
	// Every block is at least one line tall, so this many always fill the
	// panel; the panel clips whatever doesn't fit.
	shown := visible_lines(SOURCE_LINE_HEIGHT)

	block := 0
	if skip == 0 {
		next_step_block(session, count + 1)
		block += 1
	}
	for index := count - 1 - max(0, skip - 1); index >= 0 && block < shown; index -= 1 {
		step_block(session, index + 1, session.timeline[index], false)
		block += 1
	}
}

// The step Next will run, from the preview (session.preview).
@(private = "file")
next_step_block :: proc(session: ^Session, number: int) {
	entry, has_preview := session.preview.?
	if !has_preview {
		colors := palette()
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {6, 6, 2, 2}}}) {
			clay.TextDynamic(next_step_text(session, number), text_config(.Code_Small, colors.text))
		}
		return
	}
	step_block(session, number, entry, true)
}

// One step: a heading line, then its source line and stages.
@(private = "file")
step_block :: proc(session: ^Session, number: int, entry: Timeline_Entry, coming: bool) {
	colors := palette()
	if clay.UI()({
		layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = {6, 6, 4, 6}, childGap = 1},
		backgroundColor = colors.current_line if coming else COLOR_NONE,
		cornerRadius = clay.CornerRadiusAll(3),
	}) {
		buffer: [disasm.BUFFER_SIZE]u8
		text := disasm.disassemble(buffer[:], entry.pc, entry.instruction)
		marker := ">" if coming else "#"
		note := "  (next: press Next to run it)" if coming else ""
		heading := fmt.tprintf("%s%-4d %08x  %s%s", marker, number, entry.pc, text, note)
		clay.TextDynamic(heading, text_config(.Code_Small, colors.text))

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

@(private = "file")
stage_row :: proc(label: string, text: string, color: clay.Color) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {left = 24}, childGap = 8}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(STAGE_LABEL_WIDTH)}}}) {
			clay.TextDynamic(label, text_config(.Code_Small, colors.text_dim))
		}
		clay.TextDynamic(text, text_config(.Code_Small, color))
	}
}

// "0022  lw t2, 0(t0)  # t2 = ..." for the source line of `address`, or "".
@(private = "file")
source_text_at :: proc(session: ^Session, address: u64) -> string {
	if !session.has_source {
		return ""
	}
	line, known := source_line_at(&session.source, address)
	if !known || line < 1 || line > len(session.source.lines) {
		return ""
	}
	return fmt.tprintf("%04d  %s", line, strings.trim_space(session.source.lines[line - 1]))
}
