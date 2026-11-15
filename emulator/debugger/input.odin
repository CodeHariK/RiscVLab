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
BUTTON_ID_DOCS :: "DocsButton"
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
	// The Docs window: D or the toolbar button opens and closes it, Esc
	// closes it. While it is open it takes the mouse; the arrow keys still
	// step.
	if rl.IsKeyPressed(.D) || button_clicked(BUTTON_ID_DOCS) {
		view.docs_open = !view.docs_open
	} else if view.docs_open && (rl.IsKeyPressed(.ESCAPE) || button_clicked(BUTTON_ID_DOCS_CLOSE)) {
		view.docs_open = false
	}
	if view.docs_open {
		handle_docs_input(session)
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

// While the Docs window is open: stepping with the arrow keys, and clicks
// in the window.
@(private = "file")
handle_docs_input :: proc(session: ^Session) {
	if key_pressed(.LEFT) {
		session_prev(session)
		view.code_scroll = 0
	}
	if key_pressed(.RIGHT) {
		session_next(session)
		view.code_scroll = 0
	}
	handle_docs_selection()
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

// A click on an entry in the Docs list pins it; the button goes back to
// following the next instruction.
@(private = "file")
handle_docs_selection :: proc() {
	if button_clicked(BUTTON_ID_DOCS_FOLLOW) {
		view.docs_pinned = -1
		return
	}
	if !rl.IsMouseButtonPressed(.LEFT) {
		return
	}
	for _, index in docs.entries {
		if clay.PointerOver(clay.ID(DOCS_ENTRY_ID, u32(index))) {
			view.docs_pinned = index
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
