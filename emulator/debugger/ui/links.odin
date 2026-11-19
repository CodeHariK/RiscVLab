package ui

import clay "../../vendor/clay-odin"

// Link rows: a label, then clickable text links, in as many rows as they
// need (a new row starts when the next link won't fit). Not tied to any
// content: the Docs window uses them for an entry's Related entries and
// the lessons about it (view/docs_related.odin).
//
//   Related   mepc  mcause  trap  handler  .balign
//   Lessons   12: Traps: ecall and a handler  21: A timer interrupt
//
// The rows line up with ui.markdown's: the label sits in a column
// `label_width` wide. A link is underlined and lights up under the mouse; the caller finds
// out what was clicked from the ids it gave (clay.PointerOver, with last
// frame's layout, like every click).

LINK_GAP :: 4 // between two links in a row
LINK_PADDING :: 5 // left and right of a link's text
LINK_LABEL_GAP :: 8 // between the label column and the links, as in markdown rows
LINK_UNDERLINE :: 1 // the underline's thickness

// One link. `leads` = false: drawn as plain, dimmed text (nowhere to go).
Link :: struct {
	text:  string,
	id:    clay.ElementId,
	leads: bool,
}

// Draws `label` and `links`. `width` is how wide the rows may be, label
// column included: worked out by the caller rather than read from the
// layout, since a parent that grows to fit its content can't say how much
// room there is (the same as tables, table.odin).
link_rows :: proc(label: string, links: []Link, label_width: f32, width: f32) {
	room := width - label_width - LINK_LABEL_GAP

	// The same small gap ui.markdown leaves above a labelled line.
	if clay.UI()({layout = {sizing = {height = clay.SizingFixed(4)}}}) {}

	row_start := 0
	for row_start < len(links) {
		// Take links until the next one would go past the room (but always
		// at least one, so a very long link gets a row of its own).
		row_end := row_start
		used: f32 = 0
		for row_end < len(links) {
			link_width := text_width(links[row_end].text, .Code_Small) + 2 * LINK_PADDING
			if row_end > row_start {
				link_width += LINK_GAP
			}
			if row_end > row_start && used + link_width > room {
				break
			}
			used += link_width
			row_end += 1
		}
		link_row(label if row_start == 0 else "", links[row_start:row_end], label_width)
		row_start = row_end
	}
}

// One row of links, with the label (first row only) in its column.
@(private = "file")
link_row :: proc(label: string, links: []Link, label_width: f32) {
	colors := palette()
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childGap = LINK_LABEL_GAP}}) {
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(label_width)}}}) {
			if label != "" {
				clay.TextDynamic(label, text_config(.Code_Small, colors.accent))
			}
		}
		if clay.UI()({layout = {childGap = LINK_GAP}}) {
			for link in links {
				if link.leads {
					link_button(link.text, link.id)
				} else {
					clay.TextDynamic(link.text, text_config(.Code_Small, colors.text_dim))
				}
			}
		}
	}
}

// One link: underlined, accent-coloured text that lights up under the
// mouse. Clay has no underlined text, so the underline is a 1-pixel box
// under the text, as wide as it (both in a column inside the padding).
@(private = "file")
link_button :: proc(text: string, id: clay.ElementId) {
	colors := palette()
	if clay.UI(id)({
		layout = {padding = {LINK_PADDING, LINK_PADDING, 1, 1}},
		backgroundColor = colors.button_hover if clay.PointerOver(id) else COLOR_NONE,
		cornerRadius = clay.CornerRadiusAll(4),
	}) {
		if clay.UI()({layout = {layoutDirection = .TopToBottom}}) {
			clay.TextDynamic(text, text_config(.Code_Small, colors.accent))
			if clay.UI()({layout = {sizing = {clay.SizingGrow(), clay.SizingFixed(LINK_UNDERLINE)}}, backgroundColor = colors.accent}) {}
		}
	}
}
