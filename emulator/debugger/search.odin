package rvdbg

import "core:strings"
import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// The search box of the Programs and Docs windows. While a window is open
// its box always has the keyboard: typed characters go in, Backspace takes
// the last one out. A query matches when every word in it appears in the
// text (ignoring case), so "csr read" finds "CSR read and set bits".

SEARCH_MAX :: 64

Search_Field :: struct {
	buffer: [SEARCH_MAX]u8,
	length: int,
}

search_text :: proc(field: ^Search_Field) -> string {
	return string(field.buffer[:field.length])
}

// Takes this frame's typed characters and Backspace presses. Returns true
// if the text changed. Only printable ASCII is kept (the font has nothing
// else).
search_type :: proc(field: ^Search_Field) -> (changed: bool) {
	for {
		char := rl.GetCharPressed()
		if char == 0 {
			break
		}
		if char >= ' ' && char <= '~' && field.length < SEARCH_MAX {
			field.buffer[field.length] = u8(char)
			field.length += 1
			changed = true
		}
	}
	if (rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE)) && field.length > 0 {
		field.length -= 1
		changed = true
	}
	return changed
}

// Throws away characters typed this frame, e.g. the "d" of the key that
// opened a window, so it doesn't land in the search box.
search_discard_typed :: proc() {
	for rl.GetCharPressed() != 0 {}
}

// True if every word of `query` appears in `text`. `text` must already be
// lower case.
search_matches :: proc(query: string, text: string) -> bool {
	for word in strings.fields(query, context.temp_allocator) {
		if !strings.contains(text, strings.to_lower(word, context.temp_allocator)) {
			return false
		}
	}
	return true
}

// The box: the query and a caret, or a hint in dim text when empty.
search_box :: proc(id: string, field: ^Search_Field, hint: string) {
	colors := palette()
	if clay.UI(clay.ID(id))({
		layout = {sizing = {width = clay.SizingGrow()}, padding = {10, 10, 6, 6}},
		backgroundColor = colors.background,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		if field.length == 0 {
			clay.TextDynamic(hint, text_config(.Code_Small, colors.text_dim))
		} else {
			text := strings.concatenate({search_text(field), "_"}, context.temp_allocator)
			clay.TextDynamic(text, text_config(.Code_Small, colors.text))
		}
	}
}
