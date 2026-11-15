package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// The debugger's only controls:
//   Reset  (button)                     reload the program, back to the first instruction
//   Prev   (button or left arrow)       undo one instruction
//   Next   (button or right arrow)      run one instruction
// Holding an arrow key repeats it. The Theme button on the right of the
// toolbar switches between light and dark (see settings.odin), and the
// side panel's tabs pick what it shows (view.odin). The Programs (P) and
// Docs (D) buttons open their windows, which have their own keys
// (modal_input.odin). The mouse wheel scrolls the side panel (handled by
// Clay) and the code panel.
//
// Handled before the frame's layout is built, using the previous frame's
// layout for hover tests (the usual pattern with Clay).

CODE_SCROLL_LINES_PER_NOTCH :: 3

BUTTON_ID_RESET :: "ResetButton"
BUTTON_ID_PREV :: "PrevButton"
BUTTON_ID_NEXT :: "NextButton"
BUTTON_ID_THEME :: "ThemeButton"
BUTTON_ID_DOCS :: "DocsButton"
BUTTON_ID_PROGRAMS :: "ProgramsButton"
TAB_ID_CSRS :: "CsrsTab"
TAB_ID_MEMORY :: "MemoryTab"
TAB_ID_ELF :: "ElfTab"
TAB_ID_STACK :: "StackTab"
TAB_ID_MEMORY_WORDS :: "MemoryWordsTab"
TAB_ID_MEMORY_BYTES :: "MemoryBytesTab"
TAB_ID_SOURCE :: "SourceTab"
TAB_ID_DISASSEMBLY :: "DisassemblyTab"
TAB_ID_STEPS :: "StepsTab"

handle_input :: proc(session: ^Session) {
	// The Programs and Docs windows: while one is open it has the keyboard
	// and the mouse (modal_input.odin).
	if handle_windows(session) {
		return
	}

	// Dragging a divider or a panel (panel_layout.odin) takes the mouse.
	if handle_panel_input() {
		return
	}
	if button_clicked(BUTTON_ID_RESET) {
		session_reset(session)
		view.code_scroll = 0
	}
	if button_clicked(BUTTON_ID_PREV) || key_pressed(.LEFT) {
		session_prev(session)
		view.code_scroll = 0
	}
	if button_clicked(BUTTON_ID_NEXT) || key_pressed(.RIGHT) {
		session_next(session)
		view.code_scroll = 0
	}
	// The mouse wheel scrolls the code panel through the whole program.
	// Detailed steps are tall blocks, newest first: one step per notch,
	// and scrolling down goes back in time.
	if clay.PointerOver(clay.ID("CodePanel")) {
		if view.code_tab == .Steps && view.steps_detailed {
			view.code_scroll -= rl.GetMouseWheelMove()
		} else {
			view.code_scroll -= rl.GetMouseWheelMove() * CODE_SCROLL_LINES_PER_NOTCH
		}
	}
	if button_clicked(BUTTON_ID_THEME) {
		settings_next_theme()
	}
	if button_clicked(TAB_ID_SOURCE) {
		view.code_tab = .Source
	}
	if button_clicked(TAB_ID_DISASSEMBLY) {
		view.code_tab = .Disassembly
	}
	if button_clicked(TAB_ID_STEPS) {
		view.code_tab = .Steps
	}
	if button_clicked(TAB_ID_STEPS_COMPACT) {
		view.steps_detailed = false
		view.code_scroll = 0
	}
	if button_clicked(TAB_ID_STEPS_DETAILED) {
		view.steps_detailed = true
		view.code_scroll = 0
	}
	if button_clicked(TAB_ID_CSRS) {
		view.side_tab = .Csrs
	}
	if button_clicked(TAB_ID_MEMORY) {
		view.side_tab = .Memory
	}
	if button_clicked(TAB_ID_MEMORY_WORDS) {
		view.memory_layout = .Words
	}
	if button_clicked(TAB_ID_MEMORY_BYTES) {
		view.memory_layout = .Bytes
	}
	if button_clicked(TAB_ID_STACK) {
		view.side_tab = .Stack
	}
	if button_clicked(TAB_ID_ELF) {
		view.side_tab = .Elf
	}
}

button_clicked :: proc(id: string) -> bool {
	return rl.IsMouseButtonPressed(.LEFT) && clay.PointerOver(clay.ID(id))
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}
