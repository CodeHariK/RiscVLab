package rvdbg

import rv "../core"

// One debugging session: the machine plus what the UI needs to know
// about it. All changes to the machine during debugging go through the
// three actions below, which match the three controls: Start, Prev, Next.
Session :: struct {
	machine:      rv.Machine,
	// The program's bytes, kept so Start can reload a fresh copy.
	image:        []u8,
	// Where the program starts and where its code is (from the loader).
	program:      rv.Program,
	program_name: string,
	// Set when the last Next raised a trap with no handler (EBREAK ends a
	// program). Next does nothing while stopped; Prev clears it.
	stopped:      Maybe(rv.Trap),
	// Set when the program asked to exit through `tohost` (riscv-tests):
	// its exit code. Next does nothing after that; Prev clears it.
	exited:       Maybe(u64),
	// What the most recent Next changed (nil after Start or Prev).
	last_step:    Maybe(rv.Undo_Record),
}

// Fails (with the loader's error) if the file isn't a loadable program.
session_create :: proc(image: []u8, program_name: string) -> (session: Session, error: rv.Load_Error) {
	session = Session {
		image        = image,
		program_name = program_name,
	}
	session.machine = rv.machine_create(rv.RAM_SIZE_DEFAULT, 0)
	_, error = rv.machine_load_program(&session.machine, image)
	if error != nil {
		rv.machine_destroy(&session.machine)
		return session, error
	}
	session_start(&session)
	return session, nil
}

session_destroy :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
}

// Start: a fresh machine with the program loaded, PC at the first
// instruction, empty undo history.
session_start :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
	session.machine = rv.machine_create(rv.RAM_SIZE_DEFAULT, rv.HISTORY_CAPACITY_DEFAULT)
	// The file loaded once at start-up (session_create checks it), so it
	// loads again here.
	session.program, _ = rv.machine_load_program(&session.machine, session.image)
	session.stopped = nil
	session.exited = nil
	session.last_step = nil
}

// Next: run one instruction.
session_next :: proc(session: ^Session) {
	if session.stopped != nil || session.exited != nil {
		return
	}
	result := rv.machine_step(&session.machine)
	if trap, has_trap := result.?; has_trap {
		session.stopped = trap
		session.last_step = nil
		return
	}
	session.last_step = session.machine.cpu.undo
	session.exited = rv.machine_host_exit(&session.machine)
}

// Prev: undo one instruction. A trap changes nothing, so if the program
// had stopped, Prev also clears the stop and steps back to the
// instruction before it.
session_prev :: proc(session: ^Session) {
	session.stopped = nil
	session.exited = nil
	session.last_step = nil
	rv.machine_step_back(&session.machine)
}

// The program's code: [start, end).
session_code_range :: proc(session: ^Session) -> (start: u64, end: u64) {
	return session.program.code_start, session.program.code_end
}
