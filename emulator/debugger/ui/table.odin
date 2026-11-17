package ui

import "core:slice"
import clay "../../vendor/clay-odin"

// A table: rows of text cells in columns that line up. Not tied to any
// content: the Docs window uses it for Markdown tables (markdown.odin) and
// the debugger's tabs for registers, CSRs, memory, the stack and the ELF.
//
// Every column is as wide as its widest cell, so short columns never
// wrap. When that is wider than the space the table had last frame, the
// last column gets what is left (at least TABLE_MIN_LAST_COLUMN) and its
// text wraps.
//
// Each cell and each row can have its own colours (a changed register,
// the word the next store writes). A `span` row is one cell across the
// whole table: a heading above the rows it names, or a note under a row.

TABLE_LINE_WIDTH :: 1
TABLE_MIN_LAST_COLUMN :: 120

Table_Cell :: struct {
	text:       string,
	color:      clay.Color, // COLOR_NONE: the options' text colour
	background: clay.Color, // COLOR_NONE: the row's
}

Table_Row :: struct {
	cells:      []Table_Cell,
	color:      clay.Color, // for cells without their own; COLOR_NONE: the text colour
	background: clay.Color,
	span:       bool, // one cell across the whole table
}

Table_Options :: struct {
	header:    bool, // the first row is the header (shaded)
	lines:     bool, // a border and lines between the cells
	style:     Font_Style,
	padding_x: u16, // inside each cell, left and right
	padding_y: u16,
	// The space the table has, if the caller knows it; 0: the table's own
	// width last frame. Inside an element that clips sideways, pass it:
	// there a box can grow past its parent and never shrink back.
	width:     f32,
}

// A grid with lines, as in the docs.
TABLE_GRID :: Table_Options{header = true, lines = true, style = .Code_Small, padding_x = 8, padding_y = 3}
// No lines, tight rows: a list whose columns line up, as in the tabs.
TABLE_LIST :: Table_Options{style = .Code_Small, padding_x = 4, padding_y = 1}

table :: proc(id: clay.ElementId, rows: []Table_Row, options := TABLE_LIST) {
	if len(rows) == 0 {
		return
	}
	colors := palette()
	widths := table_column_widths(rows, options)
	if len(widths) == 0 {
		return
	}
	last := len(widths) - 1
	gap: u16 = TABLE_LINE_WIDTH if options.lines else 0

	// The outer box takes the width it is given, so last frame's size says
	// how much room there is; the table inside is only as wide as it needs.
	used := f32(gap) * f32(len(widths) + 1)
	for width in widths[:last] {
		used += width
	}
	space := options.width
	if space <= 0 {
		if area := clay.GetElementData(id); area.found {
			space = area.boundingBox.width
		}
	}
	if space > 0 && used + widths[last] > space {
		widths[last] = max(TABLE_MIN_LAST_COLUMN, space - used)
	}
	total := used + widths[last] - 2 * f32(gap)
	// Without lines, rows are as wide as the space, so a row's highlight
	// runs across the whole panel, and span rows wrap at its edge.
	if !options.lines {
		total = max(total, space)
	}

	border: clay.BorderElementConfig
	if options.lines {
		border = {colors.border, clay.BorderAll(TABLE_LINE_WIDTH)}
	}
	if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow()}}}) {
		if clay.UI()({layout = {layoutDirection = .TopToBottom, childGap = gap, padding = clay.PaddingAll(gap)}, border = border}) {
			for row, index in rows {
				table_row(row, widths, total, options.header && index == 0, options)
			}
		}
	}
}

// The same from plain text, every cell in the default colours.
table_text :: proc(id: clay.ElementId, rows: [][]string, options := TABLE_GRID) {
	styled := make([]Table_Row, len(rows), context.temp_allocator)
	for row, index in rows {
		cells := make([]Table_Cell, len(row), context.temp_allocator)
		for text, column in row {
			cells[column] = {text = text}
		}
		styled[index] = {cells = cells}
	}
	table(id, styled, options)
}

// A row's cells, kept past the call (variadic arguments are not).
cells :: proc(items: ..Table_Cell) -> []Table_Cell {
	return slice.clone(items, context.temp_allocator)
}

@(private)
table_row :: proc(row: Table_Row, widths: []f32, total: f32, is_header: bool, options: Table_Options) {
	colors := palette()
	gap: u16 = TABLE_LINE_WIDTH if options.lines else 0
	background := row.background
	if is_header {
		background = colors.button
	}
	color := row.color
	if color == COLOR_NONE {
		color = colors.title if is_header else colors.text
	}
	border: clay.BorderElementConfig
	if options.lines {
		border = {colors.border, {betweenChildren = TABLE_LINE_WIDTH}}
	}
	// A list's rows are all `total` wide (see table); a grid's fit its cells.
	sizing: clay.Sizing
	if !options.lines {
		sizing.width = clay.SizingFixed(total)
	}
	if clay.UI()({layout = {sizing = sizing, childGap = gap}, backgroundColor = background, border = border}) {
		if row.span {
			cell := row.cells[0] if len(row.cells) > 0 else Table_Cell{}
			table_cell(cell, total, true, color, options)
			return
		}
		for width, column in widths {
			cell := row.cells[column] if column < len(row.cells) else Table_Cell{}
			table_cell(cell, width, column == len(widths) - 1, color, options)
		}
	}
}

// Each column's width: its widest cell plus padding. Span rows don't count.
@(private)
table_column_widths :: proc(rows: []Table_Row, options: Table_Options) -> []f32 {
	columns := 0
	for row in rows {
		if !row.span {
			columns = max(columns, len(row.cells))
		}
	}
	widths := make([]f32, columns, context.temp_allocator)
	for row in rows {
		if row.span {
			continue
		}
		for cell, column in row.cells {
			// +1: rounding must never make a cell wrap.
			widths[column] = max(widths[column], text_width(cell.text, options.style) + 2 * f32(options.padding_x) + 1)
		}
	}
	return widths
}

// One cell; only the last column's text (and a span row's) may wrap.
@(private)
table_cell :: proc(cell: Table_Cell, width: f32, wraps: bool, row_color: clay.Color, options: Table_Options) {
	padding := clay.Padding{options.padding_x, options.padding_x, options.padding_y, options.padding_y}
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(width)}, padding = padding}, backgroundColor = cell.background}) {
		if cell.text != "" {
			config := text_config(options.style, cell.color if cell.color != COLOR_NONE else row_color)
			if !wraps {
				config.wrapMode = .None
			}
			clay.TextDynamic(cell.text, config)
		}
	}
}

// How wide `text` is drawn in `style` (one line).
text_width :: proc(text: string, style: Font_Style) -> f32 {
	config := text_config(style, {})
	chars := clay.StringSlice{length = i32(len(text)), chars = raw_data(text), baseChars = raw_data(text)}
	return measure_text(chars, &config, nil).width
}
