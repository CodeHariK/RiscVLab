package rv

// Undo history: what lets the debugger step backwards.
//
// Before an instruction runs, `machine_step` notes the PC and the counters.
// While it runs, `reg_write`, the store handler and the CSR instructions
// note the old value of whatever they overwrite. An instruction changes at
// most one register, one memory location (up to 8 bytes) and one CSR, so
// one fixed-size record per step is enough. A step that traps into a
// handler instead records the CSRs that trap entry overwrites. Stepping
// back restores those old values.
//
// Interrupts and supervisor mode will add fields when they arrive.
//
// Recording costs time on every step (about a fifth of a tight loop's), so
// it can be left out of a build: compile with -define:DEBUG_RECORD_STEPS=false
// and every `when DEBUG_RECORD_STEPS { ... }` below and in the handlers is gone
// from the program. Such a build runs programs and nothing more: no undo,
// and no "what did this step write" for --trace (Cpu.last_write). The
// debugger, the unit tests and build/rvemu-check record; build/rvemu, the
// one for plain runs, doesn't (Makefile).
//
// Watch out: Odin doesn't type-check a `when` branch that is switched off,
// so code inside one is only checked by a build that has it on. `make
// test` builds both kinds.

DEBUG_RECORD_STEPS :: #config(DEBUG_RECORD_STEPS, true)

Undo_Record :: struct {
	// Where the step started (restored on undo).
	pc:               u64,
	instret:          u64,
	cycle:            u64,
	privilege:        Privilege,
	// The register the step overwrote, if any.
	register_old:     u64,
	register_index:   u32,
	register_changed: bool,
	// The memory the step overwrote, if any (old bytes as a little-endian value).
	memory_changed:   bool,
	memory_address:   u64,
	memory_size:      u64,
	memory_old:       u64,
	// The device the step's load or store changed, if any, and its state
	// before (bus.odin). Its memory fields above are then not used: a
	// device register can't be put back by writing the old value (writing
	// a UART's transmit register sends a byte).
	device_changed:   bool,
	device_index:     u8,
	device_state:     Device_State,
	// The CSR the step overwrote, if any.
	csr_changed:      bool,
	csr_address:      u32,
	csr_old:          u64,
	// The LR / SC reservation the step changed, if any (rv64a.odin).
	reservation_changed: bool,
	reservation_old:     Reservation,
	// If the step trapped into a handler: the CSRs trap entry overwrote.
	// (PC and privilege are restored from the fields above.)
	trap_taken:       bool,
	trap_mstatus:     u64,
	trap_mepc:        u64,
	trap_mcause:      u64,
	trap_mtval:       u64,
}

// Default number of steps that can be undone. Each record is about 200
// bytes, so this is about 50 MiB (taken from the OS only as it is used). When full, the oldest steps are forgotten.
HISTORY_CAPACITY_DEFAULT :: 256 * 1024

// Fixed-size ring buffer of undo records, newest last.
History :: struct {
	records: []Undo_Record,
	next:    int, // slot the next record will be written to
	count:   int, // how many records are valid (at most len(records))
}

// Capacity 0 creates an empty history: recording is then switched off.
// The records come straight from the OS (zeroed_pages.odin), so slots not
// used yet take no physical memory.
history_create :: proc(capacity: int) -> History {
	bytes := zeroed_pages_alloc(capacity * size_of(Undo_Record))
	return History{records = ([^]Undo_Record)(raw_data(bytes))[:capacity]}
}

history_destroy :: proc(history: ^History) {
	bytes := ([^]u8)(raw_data(history.records))[:len(history.records) * size_of(Undo_Record)]
	zeroed_pages_free(bytes)
	history^ = {}
}

history_is_enabled :: #force_inline proc(history: ^History) -> bool {
	return len(history.records) > 0
}

history_clear :: proc(history: ^History) {
	history.next = 0
	history.count = 0
}

history_push :: proc(history: ^History, record: Undo_Record) {
	capacity := len(history.records)
	history.records[history.next] = record
	history.next = (history.next + 1) % capacity
	history.count = min(history.count + 1, capacity)
}

// For a step that is undone straight away (the debugger's preview of
// Next): when the history is full, pushing that step overwrites the
// oldest record, and undoing it doesn't bring that back. Save it before
// the step and put it back after the undo, and the history is exactly as
// it was.
History_Oldest :: struct {
	record: Undo_Record,
	full:   bool,
}

history_save_oldest :: proc(history: ^History) -> History_Oldest {
	if !history_is_enabled(history) || history.count < len(history.records) {
		return {}
	}
	// Full: the next slot to write is the oldest record.
	return {record = history.records[history.next], full = true}
}

history_restore_oldest :: proc(history: ^History, saved: History_Oldest) {
	if !saved.full {
		return
	}
	history.records[history.next] = saved.record
	history.count = len(history.records)
}

// Removes and returns the newest record; ok = false when empty.
history_pop :: proc(history: ^History) -> (record: Undo_Record, ok: bool) {
	if history.count == 0 {
		return {}, false
	}
	capacity := len(history.records)
	history.next = (history.next - 1 + capacity) % capacity
	history.count -= 1
	return history.records[history.next], true
}
