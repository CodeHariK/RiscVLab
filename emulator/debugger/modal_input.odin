package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"
import ui "ui"
import view "view"
import state "state"

// Keys and clicks for the Programs and Docs windows (view/window_programs.odin,
// view/window_docs.odin). With no window open, P, ~ (the key left of 1) or the
// Programs button opens
// Programs, D or the Docs button opens Docs. While one is open it takes
// every key and click:
//
//   typing        goes into the search box (Backspace deletes)
//   Up / Down     choose a program / go through the docs entries
//   Enter         open the chosen program (Programs)
//   Left / Right  step the program (Docs, to read along)
//   Esc           close (the search, choice and scroll positions are kept,
//                 so the window reopens where it was left)
//
// Letters type into the search, so P and D don't close the windows.

// Returns true if a window is (or just got) open, so nothing else should
// handle this frame's input.
handle_windows :: proc(session: ^state.Session) -> bool {
	if view.display.programs_open {
		handle_programs_window(session)
		return true
	}
	if view.display.docs_open {
		handle_docs_window(session)
		return true
	}
	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.GRAVE) || button_clicked(view.BUTTON_ID_PROGRAMS) {
		open_programs_window()
		return true
	}
	if rl.IsKeyPressed(.D) || button_clicked(view.BUTTON_ID_DOCS) {
		open_docs_window()
		return true
	}
	return false
}

@(private = "file")
open_programs_window :: proc() {
	view.display.programs_open = true
	ui.search_discard_typed()
	view.display.programs_list_scroll.restore_pending = true
}

@(private = "file")
open_docs_window :: proc() {
	view.display.docs_open = true
	ui.search_discard_typed()
	view.display.docs_list_scroll.restore_pending = true
	view.display.docs_page_scroll.restore_pending = true
}

@(private = "file")
handle_programs_window :: proc(session: ^state.Session) {
	search := &view.display.programs_search
	if button_clicked(view.BUTTON_ID_PROGRAMS_CLOSE) {
		view.display.programs_open = false
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		view.display.programs_open = false
		return
	}
	if ui.search_type(search) {
		view.display.program_cursor = 0
		view.display.programs_scroll_pending = true
	}

	matches := view.programs_filtered()
	if len(matches) == 0 {
		return
	}
	if key_pressed(.DOWN) {
		view.display.program_cursor = min(view.display.program_cursor + 1, len(matches) - 1)
		view.display.programs_scroll_pending = true
	}
	if key_pressed(.UP) {
		view.display.program_cursor = max(view.display.program_cursor - 1, 0)
		view.display.programs_scroll_pending = true
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		open_program(session, matches[clamp(view.display.program_cursor, 0, len(matches) - 1)])
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		for index in matches {
			if clay.PointerOver(clay.ID(view.PROGRAM_ROW_ID, u32(index))) {
				open_program(session, index)
				return
			}
		}
	}
}

// Opens catalog entry `index` and closes the window. If it can't be
// opened, the window stays open and says so (the details go to stderr).
@(private = "file")
open_program :: proc(session: ^state.Session, index: int) {
	if !state.session_open(session, state.catalog.entries[index].path) {
		view.display.program_failed = index
		return
	}
	view.display.program_failed = -1
	view.display.selected_program = index
	view.display.code_scroll = 0
	view.docs_show_lesson(session)
	view.display.programs_open = false
	settings_save(session)
}

@(private = "file")
handle_docs_window :: proc(session: ^state.Session) {
	search := &view.display.docs_search
	if button_clicked(view.BUTTON_ID_DOCS_CLOSE) {
		view.display.docs_open = false
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		view.display.docs_open = false
		return
	}
	// Typing shows the best match; clearing the search goes back to
	// following the next instruction.
	if ui.search_type(search) {
		view.display.docs_pinned = -1
		if search.length > 0 {
			if matches := view.docs_filtered(); len(matches) > 0 {
				view.display.docs_pinned = matches[0]
			}
		}
		view.display.docs_scroll_pending = true
	}

	if key_pressed(.LEFT) {
		state.session_prev(session)
		view.display.code_scroll = 0
	}
	if key_pressed(.RIGHT) {
		state.session_next(session)
		view.display.code_scroll = 0
	}
	if key_pressed(.DOWN) || key_pressed(.UP) {
		move_docs_selection(session, 1 if key_pressed(.DOWN) else -1)
	}

	if button_clicked(view.BUTTON_ID_DOCS_FOLLOW) {
		view.display.docs_pinned = -1
		view.display.docs_scroll_pending = true
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		for index in view.docs_filtered() {
			if clay.PointerOver(clay.ID(view.DOCS_ENTRY_ID, u32(index))) {
				view.display.docs_pinned = index
				return
			}
		}
		for index in view.lesson_doc_entries(session) {
			if clay.PointerOver(clay.ID(view.DOCS_LESSON_ENTRY_ID, u32(index))) {
				view.display.docs_pinned = index
				return
			}
		}
	}
}

// Up / Down: pin the entry before or after the one shown, in the list as
// filtered by the search.
@(private = "file")
move_docs_selection :: proc(session: ^state.Session, step: int) {
	matches := view.docs_filtered()
	if len(matches) == 0 {
		return
	}
	shown := view.docs_shown_entry(session)
	position := -1
	for index, at in matches {
		if index == shown {
			position = at
		}
	}
	if position < 0 {
		position = 0 if step > 0 else len(matches) - 1
	} else {
		position = clamp(position + step, 0, len(matches) - 1)
	}
	view.display.docs_pinned = matches[position]
	view.display.docs_scroll_pending = true
}
