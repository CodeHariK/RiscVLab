package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// The panel layout: resizing and rearranging the panels.
//
// Below the toolbar, the window is a row of up to three columns, with a
// bottom row of one or two panels. Each column holds one panel, or two
// stacked with a divider between them:
//
//   +-----------+--------+--------+
//   | column 0  | col. 1 | col. 2 |     | between columns
//   |  top      |        |        |     - between a column's two panels
//   +-----------+        |        |     - above the bottom row
//   |  bottom   |        |        |     | between the two bottom panels
//   +-----------+--------+--------+
//   | bottom 0     | bottom 1     |
//   +--------------+--------------+
//
// The layout is three columns (Code, Registers, the side panel) above a
// bottom row with Encoding and Explanation. Drag a divider to resize, or
// drag a panel by its grip (the "::" in its header) onto another panel to
// swap the two.
//
// Handled before the frame's layout is built, using last frame's layout
// for hit tests and container sizes.

Panel :: enum {
	Code,
	Encoding,
	Side,      // tabbed: Programs, CSRs, Memory, ELF
	Registers, // the register list (the middle column)
	Explanation,
}

panel_names := [Panel]string {
	.Code        = "Code",
	.Encoding    = "Encoding",
	.Side        = "Side panel",
	.Registers   = "Registers",
	.Explanation = "Explanation",
}

MAX_COLUMNS :: 3

Column :: struct {
	top:        Panel,
	bottom:     Panel,
	has_bottom: bool,
	// Fraction of the row's width (the last column takes what is left).
	width:      f32,
	// Fraction of the column's height for the top panel.
	split:      f32,
}

// Where a panel sits: a column's top or lower half, or the bottom row.
Slot :: struct {
	column: int, // -1 = the bottom row
	lower:  bool, // in a column: the lower panel; in the bottom row: the second (right) panel
}

Divider_Kind :: enum {
	None,
	Column_Edge, // right edge of `column`
	Column_Rows, // between `column`'s top and bottom panels
	Main_Bottom, // above the bottom row
	Bottom_Edge, // between the two bottom panels
}

Divider :: struct {
	kind:   Divider_Kind,
	column: int,
}

Panel_Layout :: struct {
	columns:          [MAX_COLUMNS]Column,
	column_count:     int,
	bottom:           [2]Panel,
	bottom_count:     int,
	// Fraction of the bottom row's width for its first panel.
	bottom_split:     f32,
	// Fraction of the area below the toolbar for the columns.
	main_height:      f32,
	dragging_divider: Divider,
	dragging_panel:   Maybe(Panel),
}

panel_layout: Panel_Layout

// Splits stay between these, so no panel can be squeezed away entirely.
SPLIT_MIN :: 0.12
SPLIT_MAX :: 0.85

DIVIDER_THICKNESS :: PANEL_GAP

// The starting layout:
//
//   +-------------+-----------+------------------+
//   | Code        | Registers | Side panel       |
//   |             |           | (CSRs, Memory..) |
//   +-------------+-----------+------------------+
//   | Encoding    | Explanation                  |
//   +-------------+------------------------------+
reset_panel_layout :: proc() {
	layout := &panel_layout
	layout^ = {}
	layout.column_count = 3
	layout.columns[0] = {top = .Code, width = 0.44}
	layout.columns[1] = {top = .Registers, width = 0.26}
	layout.columns[2] = {top = .Side}
	layout.bottom_count = 2
	layout.bottom = {.Encoding, .Explanation}
	layout.bottom_split = 0.42
	layout.main_height = 0.74
}

// ---------------------------------------------------------------- ids

slot_id :: proc(slot: Slot) -> clay.ElementId {
	if slot.column < 0 {
		return clay.ID("SlotBottom", u32(slot.lower))
	}
	return clay.ID("Slot", u32(slot.column * 2 + int(slot.lower)))
}

column_id :: proc(column: int) -> clay.ElementId {
	return clay.ID("Column", u32(column))
}

grip_id :: proc(panel: Panel) -> clay.ElementId {
	return clay.ID("Grip", u32(panel))
}

divider_id :: proc(divider: Divider) -> clay.ElementId {
	return clay.ID("Divider", u32(int(divider.kind) * MAX_COLUMNS + divider.column))
}

// ---------------------------------------------------------------- slots

panel_in :: proc(slot: Slot) -> Panel {
	if slot.column < 0 {
		return panel_layout.bottom[int(slot.lower)]
	}
	column := &panel_layout.columns[slot.column]
	return column.bottom if slot.lower else column.top
}

// The slot showing `panel`, if it is shown.
slot_of :: proc(panel: Panel) -> Maybe(Slot) {
	layout := &panel_layout
	for shown, index in layout.bottom[:layout.bottom_count] {
		if shown == panel {
			return Slot{column = -1, lower = index == 1}
		}
	}
	for column, index in layout.columns[:layout.column_count] {
		if column.top == panel {
			return Slot{column = index}
		}
		if column.has_bottom && column.bottom == panel {
			return Slot{column = index, lower = true}
		}
	}
	return nil
}

@(private = "file")
panel_pointer :: proc(slot: Slot) -> ^Panel {
	if slot.column < 0 {
		return &panel_layout.bottom[int(slot.lower)]
	}
	column := &panel_layout.columns[slot.column]
	return &column.bottom if slot.lower else &column.top
}

@(private = "file")
all_slots :: proc() -> [dynamic]Slot {
	slots := make([dynamic]Slot, context.temp_allocator)
	for column, index in panel_layout.columns[:panel_layout.column_count] {
		append(&slots, Slot{column = index})
		if column.has_bottom {
			append(&slots, Slot{column = index, lower = true})
		}
	}
	append(&slots, Slot{column = -1})
	if panel_layout.bottom_count == 2 {
		append(&slots, Slot{column = -1, lower = true})
	}
	return slots
}

@(private = "file")
all_dividers :: proc() -> [dynamic]Divider {
	dividers := make([dynamic]Divider, context.temp_allocator)
	for column, index in panel_layout.columns[:panel_layout.column_count] {
		if index < panel_layout.column_count - 1 {
			append(&dividers, Divider{.Column_Edge, index})
		}
		if column.has_bottom {
			append(&dividers, Divider{.Column_Rows, index})
		}
	}
	append(&dividers, Divider{.Main_Bottom, 0})
	if panel_layout.bottom_count == 2 {
		append(&dividers, Divider{.Bottom_Edge, 0})
	}
	return dividers
}

// ---------------------------------------------------------------- input

// Starts, continues and ends divider and panel drags, and sets the mouse
// cursor. Returns true while a drag is in progress (other clicks are
// then ignored).
handle_panel_input :: proc() -> bool {
	layout := &panel_layout

	if rl.IsMouseButtonPressed(.LEFT) {
		for divider in all_dividers() {
			if clay.PointerOver(divider_id(divider)) {
				layout.dragging_divider = divider
			}
		}
		for panel in Panel {
			if clay.PointerOver(grip_id(panel)) {
				layout.dragging_panel = panel
			}
		}
	}

	if layout.dragging_divider.kind != .None {
		if rl.IsMouseButtonDown(.LEFT) {
			drag_divider(layout.dragging_divider)
		} else {
			layout.dragging_divider = {}
		}
	}

	if panel, dragging := layout.dragging_panel.?; dragging && !rl.IsMouseButtonDown(.LEFT) {
		source, shown := slot_of(panel).?
		if target, over := hovered_slot().?; over && shown {
			a, b := panel_pointer(source), panel_pointer(target)
			a^, b^ = b^, a^
		}
		layout.dragging_panel = nil
	}

	update_cursor()
	return layout.dragging_divider.kind != .None || layout.dragging_panel != nil
}

// The slot under the mouse, if any.
hovered_slot :: proc() -> Maybe(Slot) {
	for slot in all_slots() {
		if clay.PointerOver(slot_id(slot)) {
			return slot
		}
	}
	return nil
}

@(private = "file")
drag_divider :: proc(divider: Divider) {
	mouse := rl.GetMousePosition()
	switch divider.kind {
	case .Column_Edge:
		row := clay.GetElementData(clay.ID("Main")).boundingBox
		column := clay.GetElementData(column_id(divider.column)).boundingBox
		panel_layout.columns[divider.column].width = split_fraction(mouse.x - column.x, row.width)
	case .Column_Rows:
		column := clay.GetElementData(column_id(divider.column)).boundingBox
		panel_layout.columns[divider.column].split = split_fraction(mouse.y - column.y, column.height)
	case .Main_Bottom:
		content := clay.GetElementData(clay.ID("Content")).boundingBox
		panel_layout.main_height = split_fraction(mouse.y - content.y, content.height)
	case .Bottom_Edge:
		row := clay.GetElementData(clay.ID("BottomRow")).boundingBox
		panel_layout.bottom_split = split_fraction(mouse.x - row.x, row.width)
	case .None:
	}
}

@(private = "file")
split_fraction :: proc(position: f32, size: f32) -> f32 {
	if size <= 0 {
		return 0.5
	}
	return clamp(position / size, SPLIT_MIN, SPLIT_MAX)
}

// Resize arrows over (or while dragging) a divider, a move cursor over a
// grip or while dragging a panel, the normal pointer otherwise.
@(private = "file")
update_cursor :: proc() {
	layout := &panel_layout
	divider := layout.dragging_divider
	if divider.kind == .None {
		for candidate in all_dividers() {
			if clay.PointerOver(divider_id(candidate)) {
				divider = candidate
			}
		}
	}
	switch divider.kind {
	case .Column_Edge, .Bottom_Edge:
		rl.SetMouseCursor(.RESIZE_EW)
		return
	case .Column_Rows, .Main_Bottom:
		rl.SetMouseCursor(.RESIZE_NS)
		return
	case .None:
	}
	over_grip := false
	for panel in Panel {
		over_grip = over_grip || clay.PointerOver(grip_id(panel))
	}
	rl.SetMouseCursor(.RESIZE_ALL if over_grip || layout.dragging_panel != nil else .DEFAULT)
}
