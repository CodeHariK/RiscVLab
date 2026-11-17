package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"
import ui "ui"
import view "view"
import state "state"

// The debugger's only controls:
//   Reset  (button)                     reload the program, back to the first instruction
//   Prev   (button or left arrow)       undo one instruction
//   Next   (button or right arrow)      run one instruction
// Holding an arrow key repeats it. The Theme button on the right of the
// toolbar switches between light and dark (see settings.odin), and the
// panels' tabs pick what each shows (view/panel.odin). The Programs (P) and
// Docs (D) buttons open their windows, which have their own keys
// (modal_input.odin). The mouse wheel scrolls the side panel (handled by
// Clay) and the code panel.
//
// Handled before the frame's layout is built, using the previous frame's
// layout for hover tests (the usual pattern with Clay).

CODE_SCROLL_LINES_PER_NOTCH :: 3


handle_input :: proc(session: ^state.Session) {
	// The Programs and Docs windows: while one is open it has the keyboard
	// and the mouse (modal_input.odin).
	if handle_windows(session) {
		return
	}

	// Dragging a divider or a panel (panel_layout.odin) takes the mouse.
	if view.handle_panel_input() {
		return
	}
	if button_clicked(view.BUTTON_ID_RESET) {
		state.session_reset(session)
		view.display.code_scroll = 0
	}
	if button_clicked(view.BUTTON_ID_PREV) || key_pressed(.LEFT) {
		state.session_prev(session)
		view.display.code_scroll = 0
	}
	if button_clicked(view.BUTTON_ID_NEXT) || key_pressed(.RIGHT) {
		state.session_next(session)
		view.display.code_scroll = 0
	}
	// The mouse wheel scrolls the code panel through the whole program.
	// Detailed steps are tall blocks, newest first: one step per notch,
	// and scrolling down goes back in time.
	if tab, over := view.code_tab_under_pointer(session); over {
		if tab == .Steps && view.display.steps_detailed {
			view.display.code_scroll -= rl.GetMouseWheelMove()
		} else {
			view.display.code_scroll -= rl.GetMouseWheelMove() * CODE_SCROLL_LINES_PER_NOTCH
		}
	}
	if button_clicked(view.BUTTON_ID_THEME) {
		ui.settings_next_theme()
	}
	// A tab button selects that tab in its panel.
	for panel in view.Panel {
		for tab in view.panel_tabs[panel] {
			if button_clicked(view.tab_ids[tab]) {
				view.display.selected_tab[panel] = tab
			}
		}
	}
	if button_clicked(view.TAB_ID_STEPS_COMPACT) {
		view.display.steps_detailed = false
		view.display.code_scroll = 0
	}
	if button_clicked(view.TAB_ID_STEPS_DETAILED) {
		view.display.steps_detailed = true
		view.display.code_scroll = 0
	}
	if button_clicked(view.TAB_ID_MEMORY_WORDS) {
		view.display.memory_layout = .Words
	}
	if button_clicked(view.TAB_ID_MEMORY_BYTES) {
		view.display.memory_layout = .Bytes
	}
}

button_clicked :: proc(id: string) -> bool {
	return rl.IsMouseButtonPressed(.LEFT) && clay.PointerOver(clay.ID(id))
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}
