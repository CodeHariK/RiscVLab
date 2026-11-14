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

View_State :: struct {
	side_tab:         Side_Tab,
	// The catalog entry currently open, or -1 (a file not in the list).
	selected_program: int,
}

view := View_State {
	side_tab         = .Registers,
	selected_program = -1,
}
