package rvdbg

// UI state that isn't a setting: which tab the side panel shows.
// Changed by clicking the tabs (input.odin).

Side_Tab :: enum {
	Registers, // x0..x31
	Csrs,      // control and status registers, privilege level
	Program,   // what the loader found
}

View_State :: struct {
	side_tab: Side_Tab,
}

view := View_State {
	side_tab = .Registers,
}
