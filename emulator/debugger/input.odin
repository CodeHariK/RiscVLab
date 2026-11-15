package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// The debugger's only controls:
//   Reset  (button)                     reload the program, back to the first instruction
//   Prev   (button or left arrow)       undo one instruction
//   Next   (button or right arrow)      run one instruction
// Holding an arrow key repeats it. The Theme button on the right of the
// toolbar switches between light and dark (see settings.odin), and the
// side panel's tabs pick what it shows (view.odin). In the Programs tab, a
// click on a program opens it. The mouse wheel
// scrolls the side panel (handled by Clay) and the code panel.
//
// Handled before the frame's layout is built, using the previous frame's
// layout for hover tests (the usual pattern with Clay).

CODE_SCROLL_LINES_PER_NOTCH :: 3

BUTTON_ID_RESET :: "ResetButton"
BUTTON_ID_PREV :: "PrevButton"
BUTTON_ID_NEXT :: "NextButton"
BUTTON_ID_THEME :: "ThemeButton"
TAB_ID_PROGRAMS :: "ProgramsTab"
TAB_ID_CSRS :: "CsrsTab"
TAB_ID_MEMORY :: "MemoryTab"
TAB_ID_ELF :: "ElfTab"
TAB_ID_MEMORY_WORDS :: "MemoryWordsTab"
TAB_ID_MEMORY_BYTES :: "MemoryBytesTab"
PROGRAM_ROW_ID :: "ProgramRow" // + catalog index
TAB_ID_SOURCE :: "SourceTab"
TAB_ID_DISASSEMBLY :: "DisassemblyTab"
TAB_ID_STEPS :: "StepsTab"

handle_input :: proc(session: ^Session) {
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
	if clay.PointerOver(clay.ID("CodePanel")) {
		view.code_scroll -= rl.GetMouseWheelMove() * CODE_SCROLL_LINES_PER_NOTCH
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
	if button_clicked(TAB_ID_PROGRAMS) {
		view.side_tab = .Programs
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
	if button_clicked(TAB_ID_ELF) {
		view.side_tab = .Elf
	}
	if view.side_tab == .Programs {
		handle_program_selection(session)
	}
}

// A click on a program in the Programs tab opens it.
@(private = "file")
handle_program_selection :: proc(session: ^Session) {
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	for entry, index in catalog.entries {
		if clay.PointerOver(clay.ID(PROGRAM_ROW_ID, u32(index))) {
			if session_open(session, entry.path) {
				view.selected_program = index
				view.code_scroll = 0
			}
			return
		}
	}
}

@(private = "file")
button_clicked :: proc(id: string) -> bool {
	return rl.IsMouseButtonPressed(.LEFT) && clay.PointerOver(clay.ID(id))
}

@(private = "file")
key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}
