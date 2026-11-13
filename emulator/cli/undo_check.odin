package rvemu

import "core:fmt"
import "core:slice"
import rv "../core"

// --check-undo: a self-test of the undo history.
//
// Snapshots the machine, runs the program, then steps back until the
// history is empty. Passes (exit 0) if every retired instruction was undone
// and registers, PC, instret and all of RAM equal the snapshot.
check_undo :: proc(machine: ^rv.Machine, max_steps: u64) -> int {
	start_regs := machine.cpu.regs
	start_pc := machine.cpu.pc
	start_ram := slice.clone(machine.bus.ram)
	defer delete(start_ram)

	rv.machine_run(machine, max_steps)
	retired := machine.cpu.instret

	undone: u64 = 0
	for rv.machine_step_back(machine) {
		undone += 1
	}

	all_undone := undone == retired
	state_matches :=
		machine.cpu.regs == start_regs &&
		machine.cpu.pc == start_pc &&
		machine.cpu.instret == 0 &&
		slice.equal(machine.bus.ram, start_ram)

	if all_undone && state_matches {
		fmt.printfln("undo check: undid all %d instructions, state matches the start", retired)
		return 0
	}
	fmt.printfln(
		"undo check FAILED: undid %d of %d instructions, state matches start: %v",
		undone,
		retired,
		state_matches,
	)
	return 1
}
