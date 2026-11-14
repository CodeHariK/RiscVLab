package rv

// Undo history: what lets the debugger step backwards.
//
// Before an instruction runs, `machine_step` notes the PC and instret.
// While it runs, `reg_write`, the store handler and the CSR instructions
// note the old value of whatever they overwrite. An instruction changes at
// most one register, one memory location (up to 8 bytes) and one CSR, so
// one fixed-size record per step is enough. Stepping back restores those
// old values.
//
// Traps, CSRs and privilege modes will add fields when they arrive.

Undo_Record :: struct {
	// Where the step started (restored on undo).
	pc:               u64,
	instret:          u64,
	// The register the step overwrote, if any.
	register_old:     u64,
	register_index:   u32,
	register_changed: bool,
	// The memory the step overwrote, if any (old bytes as a little-endian value).
	memory_changed:   bool,
	memory_address:   u64,
	memory_size:      u64,
	memory_old:       u64,
	// The CSR the step overwrote, if any.
	csr_changed:      bool,
	csr_address:      u32,
	csr_old:          u64,
}

// Default number of steps that can be undone. Each record is 72 bytes,
// so this is 18 MiB. When full, the oldest steps are forgotten.
HISTORY_CAPACITY_DEFAULT :: 256 * 1024

// Fixed-size ring buffer of undo records, newest last.
History :: struct {
	records: []Undo_Record,
	next:    int, // slot the next record will be written to
	count:   int, // how many records are valid (at most len(records))
}

// Capacity 0 creates an empty history: recording is then switched off.
history_create :: proc(capacity: int) -> History {
	return History{records = make([]Undo_Record, capacity)}
}

history_destroy :: proc(history: ^History) {
	delete(history.records)
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
