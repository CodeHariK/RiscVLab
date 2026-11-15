package rvdbg

import clay "../vendor/clay-odin"
import rl "vendor:raylib"

// Keys and clicks for the Programs and Docs windows (programs_modal.odin,
// docs_view.odin). With no window open, P, ~ (the key left of 1) or the
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
handle_windows :: proc(session: ^Session) -> bool {
	if view.programs_open {
		handle_programs_window(session)
		return true
	}
	if view.docs_open {
		handle_docs_window(session)
		return true
	}
	if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.GRAVE) || button_clicked(BUTTON_ID_PROGRAMS) {
		open_programs_window()
		return true
	}
	if rl.IsKeyPressed(.D) || button_clicked(BUTTON_ID_DOCS) {
		open_docs_window()
		return true
	}
	return false
}

@(private = "file")
open_programs_window :: proc() {
	view.programs_open = true
	search_discard_typed()
	view.programs_list_scroll.restore_pending = true
}

@(private = "file")
open_docs_window :: proc() {
	view.docs_open = true
	search_discard_typed()
	view.docs_list_scroll.restore_pending = true
	view.docs_page_scroll.restore_pending = true
}

@(private = "file")
handle_programs_window :: proc(session: ^Session) {
	search := &view.programs_search
	if button_clicked(BUTTON_ID_PROGRAMS_CLOSE) {
		view.programs_open = false
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		view.programs_open = false
		return
	}
	if search_type(search) {
		view.program_cursor = 0
		view.programs_scroll_pending = true
	}

	matches := programs_filtered()
	if len(matches) == 0 {
		return
	}
	if key_pressed(.DOWN) {
		view.program_cursor = min(view.program_cursor + 1, len(matches) - 1)
		view.programs_scroll_pending = true
	}
	if key_pressed(.UP) {
		view.program_cursor = max(view.program_cursor - 1, 0)
		view.programs_scroll_pending = true
	}
	if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
		open_program(session, matches[clamp(view.program_cursor, 0, len(matches) - 1)])
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		for index in matches {
			if clay.PointerOver(clay.ID(PROGRAM_ROW_ID, u32(index))) {
				open_program(session, index)
				return
			}
		}
	}
}

// Opens catalog entry `index` and closes the window.
@(private = "file")
open_program :: proc(session: ^Session, index: int) {
	if session_open(session, catalog.entries[index].path) {
		view.selected_program = index
		view.code_scroll = 0
	}
	view.programs_open = false
}

@(private = "file")
handle_docs_window :: proc(session: ^Session) {
	search := &view.docs_search
	if button_clicked(BUTTON_ID_DOCS_CLOSE) {
		view.docs_open = false
		return
	}
	if rl.IsKeyPressed(.ESCAPE) {
		view.docs_open = false
		return
	}
	// Typing shows the best match; clearing the search goes back to
	// following the next instruction.
	if search_type(search) {
		view.docs_pinned = -1
		if search.length > 0 {
			if matches := docs_filtered(); len(matches) > 0 {
				view.docs_pinned = matches[0]
			}
		}
		view.docs_scroll_pending = true
	}

	if key_pressed(.LEFT) {
		session_prev(session)
		view.code_scroll = 0
	}
	if key_pressed(.RIGHT) {
		session_next(session)
		view.code_scroll = 0
	}
	if key_pressed(.DOWN) || key_pressed(.UP) {
		move_docs_selection(session, 1 if key_pressed(.DOWN) else -1)
	}

	if button_clicked(BUTTON_ID_DOCS_FOLLOW) {
		view.docs_pinned = -1
		view.docs_scroll_pending = true
		return
	}
	if rl.IsMouseButtonPressed(.LEFT) {
		for index in docs_filtered() {
			if clay.PointerOver(clay.ID(DOCS_ENTRY_ID, u32(index))) {
				view.docs_pinned = index
				return
			}
		}
	}
}

// Up / Down: pin the entry before or after the one shown, in the list as
// filtered by the search.
@(private = "file")
move_docs_selection :: proc(session: ^Session, step: int) {
	matches := docs_filtered()
	if len(matches) == 0 {
		return
	}
	shown := docs_shown_entry(session)
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
	view.docs_pinned = matches[position]
	view.docs_scroll_pending = true
}
