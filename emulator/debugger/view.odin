package rvdbg

// UI state that isn't a setting: which tab the side panel shows and
// which listed program is open.
// Changed by clicking the tabs (input.odin).

Side_Tab :: enum {
	Programs,  // the program selector (catalog.odin)
	Csrs,      // control and status registers, privilege level
	Memory,    // hex dump around the address being used
	Elf,       // what the loader found in the program file
	Docs,      // what each instruction is for (docs_view.odin)
}

// What the code panel shows.
Code_Tab :: enum {
	Source,      // the .s file with its comments (when the build made a line map)
	Disassembly, // the instructions decoded from memory
	Steps,       // every step taken so far (timeline.odin)
}

// How the Memory tab groups bytes.
Memory_Layout :: enum {
	Words, // 32-bit little-endian words, as instructions and lw / sw see them
	Bytes, // one byte per column, in address order (shows little-endian order)
}

View_State :: struct {
	// Lines the code panel has been scrolled with the mouse wheel, away
	// from where it would follow the current instruction. Back to 0 on
	// every step, so stepping always brings the current line into view.
	code_scroll:      f32,
	memory_layout:    Memory_Layout,
	code_tab:         Code_Tab,
	// The Steps tab's mode: false = one line per step, true = every stage.
	steps_detailed:   bool,
	side_tab:         Side_Tab,
	// The Docs entry clicked in the Docs tab, or -1 to follow the next
	// instruction.
	docs_pinned:      int,
	// The catalog entry currently open, or -1 (a file not in the list).
	selected_program: int,
}

view := View_State {
	memory_layout    = .Words,
	code_tab         = .Source,
	side_tab         = .Csrs, // Registers have their own column
	selected_program = -1,
	docs_pinned      = -1,
}
