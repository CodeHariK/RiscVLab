package rvdbg

import rv "../core"

// One debugging session: the machine plus what the UI needs to know
// about it. All changes to the machine during debugging go through the
// three actions below, which match the three controls: Start, Prev, Next.
Session :: struct {
	machine:      rv.Machine,
	// The program's bytes, kept so Start can reload a fresh copy.
	image:        []u8,
	program_name: string,
	// Set when the last Next raised a trap (EBREAK ends a program).
	// Next does nothing while stopped; Prev clears it.
	stopped:      Maybe(rv.Trap),
	// What the most recent Next changed (nil after Start or Prev).
	last_step:    Maybe(rv.Undo_Record),
}

session_create :: proc(image: []u8, program_name: string) -> Session {
	session := Session {
		image        = image,
		program_name = program_name,
	}
	session_start(&session)
	return session
}

session_destroy :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
}

// Start: a fresh machine with the program loaded, PC at the first
// instruction, empty undo history.
session_start :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
	session.machine = rv.machine_create(rv.RAM_SIZE_DEFAULT, rv.HISTORY_CAPACITY_DEFAULT)
	rv.load_image(&session.machine.bus, session.image)
	session.stopped = nil
	session.last_step = nil
}

// Next: run one instruction.
session_next :: proc(session: ^Session) {
	if session.stopped != nil {
		return
	}
	result := rv.machine_step(&session.machine)
	if trap, has_trap := result.?; has_trap {
		session.stopped = trap
		session.last_step = nil
		return
	}
	session.last_step = session.machine.cpu.undo
}

// Prev: undo one instruction. A trap changes nothing, so if the program
// had stopped, Prev also clears the stop and steps back to the
// instruction before it.
session_prev :: proc(session: ^Session) {
	session.stopped = nil
	session.last_step = nil
	rv.machine_step_back(&session.machine)
}

// Address one past the last loaded instruction.
session_program_end :: proc(session: ^Session) -> u64 {
	return rv.RAM_BASE + u64(len(session.image))
}
