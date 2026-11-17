package state

import "core:fmt"
import "core:path/filepath"
import rv "../../core"
import loader "../../loader"

// One debugging session: the machine plus what the UI needs to know
// about it. All changes to the machine during debugging go through the
// three actions below, which match the three controls: Reset, Prev, Next.
Session :: struct {
	machine:      rv.Machine,
	// The program's bytes, kept so Reset can reload a fresh copy.
	image:        []u8,
	// Where the program starts and where its code is (from the loader).
	program:      loader.Program,
	// The program's source and line table, if the build made one.
	source:       Source_Map,
	has_source:   bool,
	// Labels and variables from the ELF symbol table, sorted by address
	// (names point into `image`).
	symbols:      []loader.Symbol,
	// The most recent load or store, so the Memory tab can stay on the data
	// a program is working with. `access_trail` holds its value before each
	// Next, so Prev can put it back.
	last_access:  Memory_Access,
	access_trail: [dynamic]Memory_Access,
	// Every step taken since Reset, for the Steps view (timeline.odin),
	// newest last. Capped a little above the undo history's size: steps
	// that old can't be stepped back to anyway (see timeline_trim).
	timeline:     [dynamic]Timeline_Entry,
	// How many of the oldest steps were dropped from `timeline` (and
	// `access_trail`): timeline[i] is step number timeline_dropped + i + 1.
	timeline_dropped: int,
	program_name: string,
	// Set when the last Next raised a trap with no handler (EBREAK ends a
	// program). Next does nothing while stopped; Prev clears it.
	stopped:      Maybe(rv.Trap),
	// Set when the program asked to exit through `tohost` (riscv-tests):
	// its exit code. Next does nothing after that; Prev clears it.
	exited:       Maybe(u64),
	// What the step that led to the current state changed: the latest
	// Next, or after Prev the step before (nil at the start).
	last_step:    Maybe(rv.Undo_Record),
	// Exactly what the next Next will do, for the Encoding panel and Steps view (see
	// session_update_preview). nil when the program has ended.
	preview:      Maybe(Timeline_Entry),
}

// Opens the program file at `path` (the session then owns its bytes).
// Fails, leaving `session` untouched, if the file can't be read or isn't
// a loadable program.
session_open :: proc(session: ^Session, path: string) -> bool {
	image, read_ok := read_program(path)
	if !read_ok {
		return false
	}
	// Check it loads before replacing the current program.
	probe := rv.machine_create(rv.RAM_SIZE_DEFAULT, 0)
	_, error := loader.load_program(&probe, image)
	rv.machine_destroy(&probe)
	if error != nil {
		fmt.eprintfln("error: cannot load %s: %v", path, error)
		delete(image)
		return false
	}

	delete(session.symbols)
	delete(session.image)
	session.image = image
	session.symbols = loader.elf_symbols(image)
	session.program_name = filepath.base(path)
	source_destroy(&session.source)
	session.source, session.has_source = source_load(path)
	session_reset(session)
	return true
}

session_destroy :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
	delete(session.symbols)
	delete(session.image)
	delete(session.access_trail)
	delete(session.timeline)
	source_destroy(&session.source)
}

// Reset: a fresh machine with the program loaded, PC at the first
// instruction, empty undo history.
session_reset :: proc(session: ^Session) {
	rv.machine_destroy(&session.machine)
	session.machine = rv.machine_create(rv.RAM_SIZE_DEFAULT, rv.HISTORY_CAPACITY_DEFAULT)
	// session_open checked that the program loads, so it loads again here.
	session.program, _ = loader.load_program(&session.machine, session.image)
	session.stopped = nil
	session.exited = nil
	session.last_step = nil
	session.last_access = {}
	clear(&session.access_trail)
	clear(&session.timeline)
	session.timeline_dropped = 0
	session_update_preview(session)
}

// Next: run one instruction.
session_next :: proc(session: ^Session) {
	if session.stopped != nil || session.exited != nil {
		return
	}
	access := next_memory_access(session)
	pc := session.machine.cpu.pc
	instruction, _ := rv.bus_peek(&session.machine.bus, pc, 4)
	inputs := step_inputs_capture(session, u32(instruction))
	result := rv.machine_step(&session.machine)
	if trap, has_trap := result.?; has_trap {
		// Nothing changed, so the step before stays the latest change.
		session.stopped = trap
		session_update_preview(session)
		return
	}
	session.last_step = session.machine.cpu.undo
	timeline_record(session, pc, u32(instruction), inputs)
	append(&session.access_trail, session.last_access)
	timeline_trim(session)
	if access.kind != .None {
		session.last_access = access
	}
	session.exited = rv.machine_host_exit(&session.machine)
	session_update_preview(session)
}

// Prev: undo one instruction. A trap changes nothing, so if the program
// had stopped, Prev also clears the stop and steps back to the
// instruction before it.
session_prev :: proc(session: ^Session) {
	session.stopped = nil
	session.exited = nil
	session.last_step = nil
	defer session_update_preview(session)
	if !rv.machine_step_back(&session.machine) {
		return
	}
	if len(session.access_trail) > 0 {
		session.last_access = pop(&session.access_trail)
	}
	if len(session.timeline) > 0 {
		pop(&session.timeline)
	}
	// The machine is now as the step before left it, so show what that
	// step changed, exactly as right after it ran.
	if len(session.timeline) > 0 {
		session.last_step = session.timeline[len(session.timeline) - 1].record
	}
}

// Steps dropped at a time once the timeline is full: removing from the
// front of an array moves everything after it, so do it rarely.
TIMELINE_TRIM_CHUNK :: 4096

// Keeps `timeline` and `access_trail` from growing for ever on a long
// run. The undo history keeps only its newest steps, so entries older
// than that can't be stepped back to; once there are a chunk more of them
// than the history holds, the oldest chunk goes. (The Stack tab works out
// frames from the timeline, so a frame made that long ago loses its
// heading; its words are still shown.)
@(private)
timeline_trim :: proc(session: ^Session) {
	limit := len(session.machine.history.records) + TIMELINE_TRIM_CHUNK
	if len(session.timeline) <= limit {
		return
	}
	remove_range(&session.timeline, 0, TIMELINE_TRIM_CHUNK)
	remove_range(&session.access_trail, 0, min(TIMELINE_TRIM_CHUNK, len(session.access_trail)))
	session.timeline_dropped += TIMELINE_TRIM_CHUNK
}

// Works out exactly what Next will do, so the Encoding panel and Steps view can show
// every stage of the instruction (results included) before it runs: the
// instruction is run and then undone straight away. Called after every
// Reset, Next and Prev.
//
// Skipped when the program has ended. When the undo history is full, the
// step would push its oldest record out: that one is saved first and put
// back after the undo.
session_update_preview :: proc(session: ^Session) {
	session.preview = nil
	if session.stopped != nil || session.exited != nil {
		return
	}
	machine := &session.machine
	pc := machine.cpu.pc
	raw, fetched := rv.bus_peek(&machine.bus, pc, 4)
	if !fetched {
		return
	}
	instruction := u32(raw)
	inputs := step_inputs_capture(session, instruction)
	oldest := rv.history_save_oldest(&machine.history)
	defer rv.history_restore_oldest(&machine.history, oldest)
	if trap, stops := rv.machine_step(machine).?; stops {
		// No handler: the step changed nothing, so there is nothing to undo.
		session.preview = Timeline_Entry {
			pc          = pc,
			instruction = instruction,
			next_pc     = pc,
			trap        = trap,
			inputs      = inputs,
			stops       = true,
		}
		return
	}
	session.preview = timeline_entry_make(session, pc, instruction, inputs)
	rv.machine_step_back(machine)
}

// The program's code: [start, end).
session_code_range :: proc(session: ^Session) -> (start: u64, end: u64) {
	return session.program.code_start, session.program.code_end
}
