package view

import "core:fmt"
import "core:strings"
import clay "../../vendor/clay-odin"
import rv "../../core"
import disasm "../../disasm"
import ui "../ui"
import state "../state"

// The Source tab: the program's .s file with its comments, the current
// line highlighted, long comments wrapped.

// The source file around the current instruction's line: line numbers,
// code, and comments in a dimmer colour.
@(private)
tab_source :: proc(session: ^state.Session) {
	colors := ui.palette()
	source := &session.source
	current, known := state.source_line_at(source, session.machine.cpu.pc)
	if !known {
		clay.TextDynamic(
			fmt.tprintf("pc 0x%x has no source line (see the Disassembly tab)", session.machine.cpu.pc),
			ui.text_config(.Text, colors.text_dim),
		)
		return
	}

	lines := visible_lines(SOURCE_LINE_HEIGHT)
	total := len(source.lines)
	first := 1 + first_visible_index(current - 1, lines, total)
	// The panel clips, and in Clay a clipping element lets its children be
	// as wide as they like, so long lines would run off the edge. Giving
	// each line the tab area's width (from last frame) makes them wrap:
	// a long comment continues below itself, lined up with its start.
	width := clay.SizingGrow()
	if area_width, found := tab_area_width(); found {
		width = clay.SizingFixed(max(0, area_width))
	}
	for number in first ..< min(first + lines, total + 1) {
		text := source.lines[number - 1]
		code, comment := split_comment(text)
		is_current := number == current
		if clay.UI(clay.ID("SourceLine", u32(number - first)))({
			layout = {sizing = {width = width}, padding = {6, 6, 2, 2}},
			backgroundColor = colors.current_line if is_current else ui.COLOR_NONE,
			cornerRadius = clay.CornerRadiusAll(3),
		}) {
			// The line number and the code keep their width; only the
			// comment (or a long line without one) wraps.
			marker := ">" if is_current else " "
			clay.TextDynamic(fmt.tprintf("%s%4d  ", marker, number), no_wrap(ui.text_config(.Code_Small, colors.text_dim)))
			if code != "" {
				config := ui.text_config(.Code_Small, colors.text)
				if comment != "" {
					config = no_wrap(config)
				}
				clay.TextDynamic(code, config)
			}
			if comment != "" {
				clay.TextDynamic(comment, ui.text_config(.Code_Small, colors.accent))
			}
		}
	}
}

// The same text style, never wrapped.
@(private)
no_wrap :: proc(config: clay.TextElementConfig) -> clay.TextElementConfig {
	result := config
	result.wrapMode = .None
	return result
}

// Splits an assembly line at its "#" comment: ("addi t0, zero, 5   ", "# t0 = 5").
@(private)
split_comment :: proc(line: string) -> (code: string, comment: string) {
	if hash := strings.index_byte(line, '#'); hash >= 0 {
		return line[:hash], line[hash:]
	}
	return line, ""
}
