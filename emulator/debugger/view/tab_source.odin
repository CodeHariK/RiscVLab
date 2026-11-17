package view

import "core:fmt"
import "core:strings"
import clay "../../vendor/clay-odin"
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
	area_width, has_width := tab_area_width()
	if has_width {
		width = clay.SizingFixed(max(0, area_width))
	}
	// first_visible_index counts source lines, but a wrapped line takes
	// several rows: start later until the current line is back above the
	// bottom third (not while scrolled with the wheel).
	if has_width && display.code_scroll == 0 {
		keep_below := lines / 3
		for first < current && source_rows(source, first, current, area_width) > lines - keep_below {
			first += 1
		}
	}
	rows := 0
	for number := first; number <= total && rows < lines; number += 1 {
		if has_width {
			rows += source_line_rows(source.lines[number - 1], area_width)
		} else {
			rows += 1
		}
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

// Rows the source lines `first` .. `last` take at `width` pixels.
@(private)
source_rows :: proc(source: ^state.Source_Map, first: int, last: int, width: f32) -> int {
	rows := 0
	for number in first ..= min(last, len(source.lines)) {
		rows += source_line_rows(source.lines[number - 1], width)
	}
	return rows
}

// Rows one source line takes when the tab area is `width` pixels wide,
// laid out as tab_source does it: the line number and code don't wrap,
// and the comment (or a line without one) wraps in the space left. The
// font is monospace, so this is a count of characters; word wrapping can
// use a little more, which the bottom third leaves room for.
@(private)
source_line_rows :: proc(text: string, width: f32) -> int {
	character := ui.text_width("0", .Code_Small)
	if character <= 0 {
		return 1
	}
	columns := int((width - 12) / character) // the line's padding: 6 + 6
	code, comment := split_comment(text)
	wrapping := comment if comment != "" else code
	used := 7 // "> 0012  ": marker, number, two spaces
	if comment != "" {
		used += len(code)
	}
	space := columns - used
	if space <= 0 || len(wrapping) <= space {
		return 1
	}
	return (len(wrapping) + space - 1) / space
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
