package view

import clay "../../vendor/clay-odin"
import state "../state"

// How the code tabs (Source, Disassembly, Steps) scroll: they draw only
// the lines that fit, starting where the current instruction stays in
// view, shifted by the mouse wheel.

// Which line to start at so the `current` one (0-based) is on screen,
// scrolling as little as possible: start at the top, and only scroll once
// the current line would pass two thirds of the way down. Never scroll
// past the end, so a file that fits is always shown from its first line.
//
// The mouse wheel shifts that by display.code_scroll lines, to look at the
// rest of the program (the next step scrolls back).
@(private)
first_visible_index :: proc(current: int, lines: int, total: int) -> int {
	keep_below := lines / 3 // lines kept visible after the current one
	following := max(0, min(current - (lines - 1 - keep_below), total - lines))
	wanted := following + int(display.code_scroll)
	first := max(0, min(wanted, total - lines))
	// At the top or bottom, stop the scroll growing, so scrolling back
	// responds straight away. (Otherwise keep its fraction: a trackpad
	// sends small amounts.)
	if first != wanted {
		display.code_scroll = f32(first - following)
	}
	return first
}

// How many lines of `line_height` pixels fit in the tab area being drawn,
// from its height last frame.
visible_lines :: proc(line_height: int) -> int {
	area := clay.GetElementData(current_tab_area)
	if !area.found {
		return CODE_LINES_DEFAULT
	}
	return max(3, int(area.boundingBox.height) / line_height)
}

// The code tab under the mouse, if any (the wheel scrolls it).
code_tab_under_pointer :: proc(session: ^state.Session) -> (Tab, bool) {
	for panel in Panel {
		if _, shown := slot_of(panel).?; !shown {
			continue
		}
		tab := shown_tab(session, panel)
		if is_code_tab(tab) && clay.PointerOver(clay.ID("Panel", u32(panel))) {
			return tab, true
		}
	}
	return .Source, false
}

