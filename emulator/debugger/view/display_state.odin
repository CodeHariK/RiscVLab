package view

import ui "../ui"

// UI state that isn't a setting: which tab each panel shows and which
// listed program is open.
// Changed by clicking the tabs (input.odin).

// How the Memory tab groups bytes.
Memory_Layout :: enum {
	Words, // 32-bit little-endian words, as instructions and lw / sw see them
	Bytes, // one byte per column, in address order (shows little-endian order)
}

View_State :: struct {
	// Lines the code panel has been scrolled with the mouse wheel, away
	// from where it would follow the current instruction. Back to 0 on
	// every step, so stepping always brings the current line into display.
	code_scroll:      f32,
	memory_layout:    Memory_Layout,
	// The tab each panel shows (panel.odin).
	selected_tab:     [Panel]Tab,
	// The Steps tab's mode: false = one line per step, true = every stage.
	steps_detailed:   bool,
	// The Docs window (window_docs.odin): open or not, and the entry clicked
	// in its list, or -1 to follow the next instruction.
	docs_open:        bool,
	docs_pinned:      int,
	docs_search:      ui.Search_Field,
	// Set by Up / Down: scroll the list to the chosen entry (next frame).
	docs_scroll_pending: bool,
	docs_list_scroll: ui.Saved_Scroll,
	docs_page_scroll: ui.Saved_Scroll,
	// The Programs window (window_programs.odin): open or not, its search,
	// and the chosen row (a position in the filtered list). Both windows
	// keep their search, choice and scroll positions while closed, so they
	// reopen where they were left.
	programs_open:    bool,
	programs_search:  ui.Search_Field,
	program_cursor:   int,
	// The catalog entry that last failed to open (the window stays open
	// and says so), or -1.
	program_failed:   int,
	programs_scroll_pending: bool,
	programs_list_scroll: ui.Saved_Scroll,
	// The catalog entry currently open, or -1 (a file not in the list).
	selected_program: int,
}

display := View_State {
	memory_layout    = .Words,
	selected_tab     = {.Code = .Source, .Registers = .Registers, .Side = .Csrs, .Encoding = .Encoding, .Console = .Console},
	selected_program = -1,
	program_failed   = -1,
	docs_pinned      = -1,
}
