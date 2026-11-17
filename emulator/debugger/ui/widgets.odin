package ui

import clay "../../vendor/clay-odin"

// Small widgets shared by every panel and window. Each is just a Clay box
// with an id; the caller checks for clicks on that id (with last frame's
// layout, the usual Clay pattern).

// A toolbar button: label in a bordered box, lighter while hovered.
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

// A tab: like a button, but the selected one has the current-line colour.
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
