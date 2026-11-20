package rvemu

import "core:fmt"
import "core:slice"
import rv "../core"

// --check-undo: a self-test of the undo history.
//
// Snapshots the machine, runs the program, then steps back until the
// history is empty. Passes (exit 0) if every recorded step was undone
// and registers, CSRs, privilege, the LR reservation, PC, the counters,
// all of RAM and the devices equal the snapshot. A run longer than the history holds
// can't be checked, and fails with a message saying so.
check_undo :: proc(machine: ^rv.Machine, max_steps: u64) -> int {
	start_regs := machine.cpu.regs
	start_csr := machine.cpu.csr
	start_privilege := machine.cpu.privilege
	start_reservation := machine.cpu.reservation
	start_pc := machine.cpu.pc
	start_ram := slice.clone(machine.bus.ram)
	defer delete(start_ram)
	// Devices (the UART) are compared through the state they save for undo.
	start_devices: [rv.MAX_DEVICES]rv.Device_State
	for device, index in machine.bus.devices[:machine.bus.device_count] {
		start_devices[index] = device.save(device.data)
	}

	result := rv.machine_run(machine, max_steps)
	// Every step is recorded except one that stopped the machine (a trap
	// with no handler). Steps that trapped into a handler are recorded but
	// don't retire, so this can be more than minstret.
	recorded := result.steps
	if result.reason == .Breakpoint || result.reason == .Trap {
		recorded -= 1
	}
	// Every step must still be in the history to be undone.
	capacity := u64(len(machine.debug_history.records))
	if recorded > capacity {
		fmt.printfln(
			"undo check FAILED: the program ran %d steps, but the history holds only the last %d (use --max-steps %d or less)",
			recorded,
			capacity,
			capacity,
		)
		return 1
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
		machine.cpu.reservation == start_reservation &&
		machine.cpu.csr.minstret == 0 &&
		machine.cpu.csr.mcycle == 0 &&
		machine.cpu.step_clock_offset == 0 &&
		slice.equal(machine.bus.ram, start_ram) &&
		devices_match(machine, start_devices)

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

@(private = "file")
devices_match :: proc(machine: ^rv.Machine, start: [rv.MAX_DEVICES]rv.Device_State) -> bool {
	for device, index in machine.bus.devices[:machine.bus.device_count] {
		if device.save(device.data) != start[index] {
			return false
		}
	}
	return true
}
