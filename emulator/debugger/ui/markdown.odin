package ui

import "core:fmt"
import "core:strings"
import clay "../../vendor/clay-odin"

// The small Markdown subset the reference docs are written in, drawn with
// Clay, one line at a time:
//   "Does: ..."         a section label (one of `labels`) and its first text
//   "- ..." / "1. ..."  a bullet or numbered step, wrapped under itself
//   ``` ... ```         a code block, in the code colour
//   "| a | b |"         a table (table.odin); a "|---|" line after the
//                       first row makes that row the header
//   "*U-type, RV64I*"   a whole line in stars: a note, dimmed
//   blank line          a small gap
//   anything else       text, wrapped
// Backticks (code marks) are left out. Headings, links and inline styles
// are not supported.
//
// With a `label_width`, every row has a label column that wide, so the
// text under a label reads as one block.

MARKDOWN_MARKER_WIDTH :: 28 // "-" or "1." in front of a bullet or step

// `id` keeps the ids of tables apart when more than one Markdown text is
// on screen.
markdown :: proc(id: string, lines: []string, labels: []string = nil, label_width: f32 = 0) {
	colors := palette()
	in_code := false
	tables: u32 = 0
	for index := 0; index < len(lines); index += 1 {
		line := lines[index]
		if strings.has_prefix(strings.trim_space(line), "```") {
			in_code = !in_code
			continue
		}
		if in_code {
			markdown_row(label_width, "", "", line, colors.accent)
			continue
		}
		if is_table_line(line) {
			end := index
			for end < len(lines) && is_table_line(lines[end]) {
				end += 1
			}
			markdown_table(clay.ID(fmt.tprintf("%sTable", id), tables), lines[index:end], label_width)
			tables += 1
			index = end - 1
			continue
		}
		markdown_line(line, labels, label_width)
	}
}

// One line outside code blocks and tables.
@(private)
markdown_line :: proc(line: string, labels: []string, label_width: f32) {
	colors := palette()
	if strings.trim_space(line) == "" {
		if clay.UI()({layout = {sizing = {height = clay.SizingFixed(6)}}}) {}
		return
	}
	text, _ := strings.remove_all(line, "`", context.temp_allocator)
	if strings.has_prefix(text, "*") && strings.has_suffix(text, "*") && len(text) > 1 {
		clay.TextDynamic(text[1:len(text) - 1], text_config(.Code_Small, colors.text_dim))
		return
	}
	for label in labels {
		if strings.has_prefix(text, label) && strings.has_prefix(text[len(label):], ":") {
			if clay.UI()({layout = {sizing = {height = clay.SizingFixed(4)}}}) {}
			markdown_row(label_width, label, "", strings.trim_space(text[len(label) + 1:]), colors.text)
			return
		}
	}
	if strings.has_prefix(text, "- ") {
		markdown_row(label_width, "", "-", text[2:], colors.text)
		return
	}
	if marker, rest, numbered := numbered_step(text); numbered {
		markdown_row(label_width, "", marker, rest, colors.text)
		return
	}
	markdown_row(label_width, "", "", text, colors.text)
}

// "1. text" -> ("1.", "text", true).
@(private)
numbered_step :: proc(text: string) -> (marker: string, rest: string, ok: bool) {
	digits := 0
	for digits < len(text) && text[digits] >= '0' && text[digits] <= '9' {
		digits += 1
	}
	if digits == 0 || !strings.has_prefix(text[digits:], ". ") {
		return "", "", false
	}
	return text[:digits + 1], text[digits + 2:], true
}

// A row: the label column (when there is one) with `label` or nothing,
// then an optional bullet / step marker, then the text, which wraps within
// its own column so continued lines stay lined up.
@(private)
markdown_row :: proc(label_width: f32, label: string, marker: string, text: string, color: clay.Color) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 8}}) {
		label_column(label_width, label)
		if marker != "" {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(MARKDOWN_MARKER_WIDTH)}}}) {
				clay.TextDynamic(marker, text_config(.Code_Small, colors.text_dim))
			}
		}
		if text != "" {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {
				clay.TextDynamic(text, text_config(.Code_Small, color))
			}
		}
	}
}

@(private)
label_column :: proc(label_width: f32, label: string) {
	if label_width <= 0 {
		return
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(label_width)}}}) {
		if label != "" {
			clay.TextDynamic(label, text_config(.Code_Small, palette().accent))
		}
	}
}

// ---------------------------------------------------------------- tables

@(private)
is_table_line :: proc(line: string) -> bool {
	return strings.has_prefix(strings.trim_space(line), "|")
}

// A run of "| a | b |" lines as a table in the text column.
@(private)
markdown_table :: proc(id: clay.ElementId, lines: []string, label_width: f32) {
	rows := make([dynamic][]string, 0, len(lines), context.temp_allocator)
	header := false
	for line, index in lines {
		cells := table_cells(line)
		if is_separator_row(cells) {
			header = header || index == 1
			continue
		}
		append(&rows, cells)
	}
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = 8, padding = {top = 4, bottom = 4}}}) {
		label_column(label_width, "")
		options := TABLE_GRID
		options.header = header
		table_text(id, rows[:], options)
	}
}

// "| a | `b` |" -> {"a", "b"}.
@(private)
table_cells :: proc(line: string) -> []string {
	text := strings.trim_space(line)
	text = strings.trim_prefix(text, "|")
	text = strings.trim_suffix(text, "|")
	cells := strings.split(text, "|", context.temp_allocator)
	for &cell in cells {
		cell, _ = strings.remove_all(strings.trim_space(cell), "`", context.temp_allocator)
	}
	return cells
}

// "|---|:--:|" : only dashes, colons and spaces in every cell.
@(private)
is_separator_row :: proc(cells: []string) -> bool {
	for cell in cells {
		if cell == "" || strings.trim(cell, "-: ") != "" {
			return false
		}
	}
	return len(cells) > 0
}
