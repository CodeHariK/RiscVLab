package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the undo history (core/history.odin).
//
// The history is a ring buffer of undo records, one per step. When it is
// full, each new step overwrites the oldest record, so Prev can only go
// back as far as the history holds. Small capacities (4) make that easy
// to reach.

ADDI_T0_T0_1 :: u32(0x0012_8293) // addi t0, t0, 1

// A machine with a history of `capacity` records and the same addi
// everywhere in the first `count` words of RAM.
@(private = "file")
machine_of_addis :: proc(capacity: int, count: int) -> rv.Machine {
	machine := rv.machine_create(64 * 1024, capacity)
	for index in 0 ..< count {
		rv.machine_store(&machine, rv.RAM_BASE + u64(index) * 4, 4, u64(ADDI_T0_T0_1))
	}
	return machine
}

@(test)
full_history_forgets_the_oldest_step :: proc(t: ^testing.T) {
	// Room for 4 records; run 6 steps. Steps 1 and 2 are forgotten.
	machine := machine_of_addis(4, 8)
	defer rv.machine_destroy(&machine)
	for _ in 0 ..< 6 {
		rv.machine_step(&machine) // t0 counts the steps: 6
	}
	// Step back until history_pop says there's nothing left.
	undone := 0
	for rv.machine_step_back(&machine) {
		undone += 1
	}
	testing.expect_value(t, undone, 4)
	testing.expect_value(t, machine.cpu.regs[5], 2) // back 4 of 6 steps
}

@(test)
step_and_undo_keeps_a_full_history :: proc(t: ^testing.T) {
	// What the debugger's preview does: run one step and undo it. With the
	// history full, the oldest record must survive.
	machine := machine_of_addis(4, 8)
	defer rv.machine_destroy(&machine)
	for _ in 0 ..< 4 {
		rv.machine_step(&machine) // exactly fills the history
	}

	// The preview step would overwrite the oldest record (step 1), and
	// undoing it doesn't bring that record back. So the debugger saves
	// the oldest record first and puts it back afterwards.
	oldest := rv.history_save_oldest(&machine.debug_history)
	testing.expect(t, oldest.full)
	rv.machine_step(&machine) // the preview...
	rv.machine_step_back(&machine) // ...undone at once
	rv.history_restore_oldest(&machine.debug_history, oldest)

	// All 4 real steps can still be undone, back to t0 = 0.
	undone := 0
	for rv.machine_step_back(&machine) {
		undone += 1
	}
	testing.expect_value(t, undone, 4)
	testing.expect_value(t, machine.cpu.regs[5], 0) // all the way to the start
}
