package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the undo history (core/history.odin).

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
	machine := machine_of_addis(4, 8)
	defer rv.machine_destroy(&machine)
	for _ in 0 ..< 6 {
		rv.machine_step(&machine)
	}
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
		rv.machine_step(&machine)
	}

	oldest := rv.history_save_oldest(&machine.history)
	testing.expect(t, oldest.full)
	rv.machine_step(&machine)
	rv.machine_step_back(&machine)
	rv.history_restore_oldest(&machine.history, oldest)

	undone := 0
	for rv.machine_step_back(&machine) {
		undone += 1
	}
	testing.expect_value(t, undone, 4)
	testing.expect_value(t, machine.cpu.regs[5], 0) // all the way to the start
}
