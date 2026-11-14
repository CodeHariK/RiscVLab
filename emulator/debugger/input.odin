package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// The debugger's only controls:
//   Start  (button)                     reload the program, back to the first instruction
//   Prev   (button or left arrow)       undo one instruction
//   Next   (button or right arrow)      run one instruction
// Holding an arrow key repeats it. The Theme button on the right of the
// toolbar switches between light and dark (see settings.odin), and the
// side panel's tabs pick what it shows (view.odin). The mouse wheel
// scrolls the side panel (handled by Clay).
//
// Handled before the frame's layout is built, using the previous frame's
// layout for hover tests (the usual pattern with Clay).

BUTTON_ID_START :: "StartButton"
BUTTON_ID_PREV :: "PrevButton"
BUTTON_ID_NEXT :: "NextButton"
BUTTON_ID_THEME :: "ThemeButton"
TAB_ID_REGISTERS :: "RegistersTab"
TAB_ID_PROGRAM :: "ProgramTab"

handle_input :: proc(session: ^Session) {
	if button_clicked(BUTTON_ID_START) {
		session_start(session)
	}
	if button_clicked(BUTTON_ID_PREV) || key_pressed(.LEFT) {
		session_prev(session)
	}
	if button_clicked(BUTTON_ID_NEXT) || key_pressed(.RIGHT) {
		session_next(session)
	}
	if button_clicked(BUTTON_ID_THEME) {
		settings_next_theme()
	}
	if button_clicked(TAB_ID_REGISTERS) {
		view.side_tab = .Registers
	}
	if button_clicked(TAB_ID_PROGRAM) {
		view.side_tab = .Program
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
