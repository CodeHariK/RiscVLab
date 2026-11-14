package rvemu

import "core:fmt"
import "core:slice"
import rv "../core"

// --check-undo: a self-test of the undo history.
//
// Snapshots the machine, runs the program, then steps back until the
// history is empty. Passes (exit 0) if every recorded step was undone
// and registers, CSRs, privilege, PC, instret and all of RAM equal the
// snapshot.
check_undo :: proc(machine: ^rv.Machine, max_steps: u64) -> int {
	start_regs := machine.cpu.regs
	start_csr := machine.cpu.csr
	start_privilege := machine.cpu.privilege
	start_pc := machine.cpu.pc
	start_ram := slice.clone(machine.bus.ram)
	defer delete(start_ram)

	result := rv.machine_run(machine, max_steps)
	// Every step is recorded except one that stopped the machine (a trap
	// with no handler). Steps that trapped into a handler are recorded but
	// don't retire, so this can be more than instret.
	recorded := result.steps
	if result.reason == .Breakpoint || result.reason == .Trap {
		recorded -= 1
	}

	undone: u64 = 0
	for rv.machine_step_back(machine) {
		undone += 1
	}

	all_undone := undone == recorded
	state_matches :=
		machine.cpu.regs == start_regs &&
		machine.cpu.csr == start_csr &&
		machine.cpu.privilege == start_privilege &&
		machine.cpu.pc == start_pc &&
		machine.cpu.instret == 0 &&
		slice.equal(machine.bus.ram, start_ram)

	if all_undone && state_matches {
		fmt.printfln("undo check: undid all %d steps, state matches the start", recorded)
		return 0
	}
	fmt.printfln(
		"undo check FAILED: undid %d of %d steps, state matches start: %v",
		undone,
		recorded,
		state_matches,
	)
	return 1
}
