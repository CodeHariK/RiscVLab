package ui

import clay "../../vendor/clay-odin"
import rl "vendor:raylib"

// The frame shared by the Programs and Docs windows: the rest of the
// window dimmed, and a large panel on top with a title, optional header
// buttons, Close, and the window's own content. Clicks only reach the
// window while it is open (pointer capture).

MODAL_MARGIN :: 48 // space left around the window
MODAL_OVERLAY_COLOR :: clay.Color{20, 10, 40, 110}

// Draws the window's content; `data` is whatever the caller passed to
// modal_window (the debugger passes its session).
Modal_Content :: #type proc(data: rawptr)

// `header` (may be nil) adds buttons after the title; `close_id` is the
// Close button's id, which the caller checks for clicks.
modal_window :: proc(id: string, title: string, close_id: string, header: proc(), content: Modal_Content, data: rawptr) {
	colors := palette()
	if clay.UI(clay.ID(id, 0))({
		layout = {
			sizing = {clay.SizingFixed(f32(rl.GetScreenWidth())), clay.SizingFixed(f32(rl.GetScreenHeight()))},
			padding = clay.PaddingAll(MODAL_MARGIN),
		},
		floating = {attachTo = .Root, zIndex = 100, pointerCaptureMode = .Capture},
		backgroundColor = MODAL_OVERLAY_COLOR,
	}) {
		if clay.UI(clay.ID(id, 1))({
			layout = {
				sizing = {clay.SizingGrow(), clay.SizingGrow()},
				layoutDirection = .TopToBottom,
				padding = clay.PaddingAll(PANEL_PADDING),
				childGap = 10,
			},
			backgroundColor = colors.panel,
			cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
			border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
		}) {
			if clay.UI(clay.ID(id, 2))({layout = {sizing = {width = clay.SizingGrow()}, childGap = 10, childAlignment = {y = .Center}}}) {
				clay.TextDynamic(title, text_config(.Title, colors.title))
				if header != nil {
					header()
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {}
				modal_button(close_id, "Close (Esc)")
			}
			content(data)
		}
	}
}

modal_button :: proc(id: string, label: string) {
	colors := palette()
	element_id := clay.ID(id)
	if clay.UI(element_id)({
		layout = {padding = {10, 10, 4, 4}},
		backgroundColor = colors.button_hover if clay.PointerOver(element_id) else colors.button,
		cornerRadius = clay.CornerRadiusAll(CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(BORDER_WIDTH)},
	}) {
		clay.TextDynamic(label, text_config(.Code_Small, colors.button_text))
	}
}

// A dim line of keyboard hints.
modal_hint :: proc(text: string) {
	colors := palette()
	clay.TextDynamic(text, text_config(.Code_Small, colors.text_dim))
}

// Where a window's scrolling areas were, so reopening the window puts
// them back. Clay forgets a scrolling area's position once it is no
// longer drawn, so the caller keeps its own copy (the debugger: view/display_state.odin).
Saved_Scroll :: struct {
	position:        clay.Vector2,
	restore_pending: bool, // set on reopening, until the area exists again
}

// Every frame while the window is open: remember the area's position
// (from last frame's layout), or put the saved one back after reopening.
scroll_keep :: proc(saved: ^Saved_Scroll, area: clay.ElementId) {
	scroll := clay.GetScrollContainerData(area)
	if !scroll.found {
		return
	}
	if saved.restore_pending {
		scroll.scrollPosition^ = saved.position
		saved.restore_pending = false
	} else {
		saved.position = scroll.scrollPosition^
	}
}

// Scrolls a scrolling list so `row` is fully visible, using last frame's
// layout. Returns false if either wasn't laid out last frame.
scroll_into_view :: proc(list: clay.ElementId, row: clay.ElementId) -> bool {
	scroll := clay.GetScrollContainerData(list)
	list_box := clay.GetElementData(list)
	row_box := clay.GetElementData(row)
	if !scroll.found || !list_box.found || !row_box.found {
		return false
	}
	top := row_box.boundingBox.y - list_box.boundingBox.y
	bottom := top + row_box.boundingBox.height
	if top < 0 {
		scroll.scrollPosition.y -= top
	} else if bottom > list_box.boundingBox.height {
		scroll.scrollPosition.y -= bottom - list_box.boundingBox.height
	}
	return true
}
