package rvdbg

// UI state that isn't a setting: which tab the side panel shows and
// which listed program is open.
// Changed by clicking the tabs (input.odin).

Side_Tab :: enum {
	Programs,  // the program selector (catalog.odin)
	Registers, // x0..x31
	Csrs,      // control and status registers, privilege level
	Elf,       // what the loader found in the program file
}

// What the code panel shows.
Code_Tab :: enum {
	Source,      // the .s file with its comments (when the build made a line map)
	Disassembly, // the instructions decoded from memory
}

View_State :: struct {
	code_tab:         Code_Tab,
	side_tab:         Side_Tab,
	// The catalog entry currently open, or -1 (a file not in the list).
	selected_program: int,
}

view := View_State {
	code_tab         = .Source,
	side_tab         = .Registers,
	selected_program = -1,
}
