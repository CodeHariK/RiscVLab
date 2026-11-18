package rv

// The whole emulated computer: one hart, the bus it is wired to, and the
// undo history used for stepping backwards.
//
// This file is the core's public API for front ends (the command-line
// runner, the debugger UI). Nothing in the core reads files or prints,
// so the same core can later be compiled to WebAssembly.
Machine :: struct {
	cpu:       Cpu,
	bus:       Bus,
	history:   History,
	// The trap the last step took into a handler, if any (for traces and
	// the debugger; the step itself reports success).
	last_trap: Maybe(Trap),
	// Address of the program's `tohost` variable, if it has one (set by
	// loader.load_program). See machine_host_exit.
	tohost:    Maybe(u64),
}

// Why `machine_run` returned.
Stop_Reason :: enum {
	// EBREAK: the normal way for a test program to finish.
	Breakpoint,
	// Any other trap while no handler is set up (mtvec's base is 0).
	Trap,
	// The step limit was reached (guards against endless loops).
	Step_Limit,
	// The program wrote an exit request to `tohost` (riscv-tests do this).
	Host_Exit,
}

Run_Result :: struct {
	reason:    Stop_Reason,
	trap:      Trap,
	steps:     u64,
	// For Host_Exit: the program's exit code (0 = success).
	exit_code: u64,
}

// Called after every step by `machine_run`, e.g. to print a trace line.
// `pc` is where the instruction was; `result` is what it did.
Step_Observer :: #type proc(machine: ^Machine, pc: u64, result: Step_Result)

// Creates a machine with `ram_size` bytes of zeroed RAM and the PC at
// RAM_BASE. `history_capacity` is how many steps can be undone (0 = none).
machine_create :: proc(ram_size: u64, history_capacity: int) -> Machine {
	machine := Machine {
		bus     = bus_create(ram_size),
		history = history_create(history_capacity),
	}
	machine.cpu.pc = RAM_BASE
	machine.cpu.privilege = .Machine
	machine.cpu.csr.mstatus = MSTATUS_RESET
	return machine
}

machine_destroy :: proc(machine: ^Machine) {
	history_destroy(&machine.history)
	bus_destroy(&machine.bus)
}

// Runs one instruction and records how to undo it.
//
// First, at the instruction boundary: if an interrupt is pending and
// enabled (interrupts.odin), it is taken instead, and the instruction at
// the pc doesn't run (it runs after the handler's mret).
//
// If the instruction traps and a handler is set up (mtvec's base != 0),
// the trap is taken: the hart jumps to the handler, `last_trap` is set and
// the step counts as done (nil). If there is no handler, nothing changed,
// so nothing is recorded and the trap is returned: the machine stops.
//
// Every step that is done moves mcycle, and so the step clock, on by one
// (cpu_clock); minstret counts only the instructions that completed.
machine_step :: proc(machine: ^Machine) -> Step_Result {
	cpu := &machine.cpu
	cpu.undo = Undo_Record {
		pc        = cpu.pc,
		instret   = cpu.instret,
		cycle     = cpu.cycle,
		privilege = cpu.privilege,
	}
	machine.last_trap = nil
	machine.bus.touched = {}

	if cpu_clock(cpu) >= machine.bus.interrupts_change_at {
		machine_update_interrupts(machine) // an alarm time has come
	}
	result: Step_Result
	// The common case, nothing pending and enabled, costs one test.
	cause, take := Trap_Cause{}, false
	if cpu.csr.mip & cpu.csr.mie != 0 {
		cause, take = interrupt_to_take(cpu)
	}
	if take {
		cpu.last_write = {}
		result = trap_make(cause, 0) // mtval is 0 for interrupts
	} else {
		result = cpu_step(cpu, &machine.bus)
	}
	if touch := machine.bus.touched; touch.touched {
		cpu.undo.device_changed = true
		cpu.undo.device_index = u8(touch.index)
		cpu.undo.device_state = touch.state
	}
	if trap, has_trap := result.?; has_trap {
		if !trap_has_handler(cpu) {
			return result
		}
		cpu.undo.trap_taken = true
		cpu.undo.trap_mstatus = cpu.csr.mstatus
		cpu.undo.trap_mepc = cpu.csr.mepc
		cpu.undo.trap_mcause = cpu.csr.mcause
		cpu.undo.trap_mtval = cpu.csr.mtval
		trap_enter(cpu, trap)
		machine.last_trap = trap
		cpu.cycle += 1 // cpu_step counts only instructions that completed
	}

	if history_is_enabled(&machine.history) {
		history_push(&machine.history, cpu.undo)
	}
	// Look again if a device register was used or an alarm time came.
	// (mie and mstatus.MIE don't change mip: they are checked when the
	// interrupt is about to be taken, above.)
	if machine.bus.touched.touched || cpu_clock(cpu) >= machine.bus.interrupts_change_at {
		machine_update_interrupts(machine)
	}
	return nil
}

// Sets mip to what the devices drive now, and notes when to look again.
// mip is never stored for undo: it follows from the devices' state and
// the step clock, so it is worked out again whenever either changes.
machine_update_interrupts :: proc(machine: ^Machine) {
	machine.cpu.csr.mip, machine.bus.interrupts_change_at = bus_interrupt_lines(&machine.bus, cpu_clock(&machine.cpu))
}

// Undoes the most recent recorded step. Returns false when there is
// nothing left to undo (start of the program, or history full and wrapped).
machine_step_back :: proc(machine: ^Machine) -> bool {
	record, ok := history_pop(&machine.history)
	if !ok {
		return false
	}
	if record.device_changed {
		// A device puts back its own state: writing the old value to a
		// register would act on it again (send another byte).
		device := &machine.bus.devices[record.device_index]
		if device.restore != nil {
			device.restore(device.data, record.device_state)
		}
	} else if record.memory_changed {
		bus_store(&machine.bus, record.memory_address, record.memory_size, record.memory_old, cpu_clock(&machine.cpu))
	}
	if record.register_changed {
		machine.cpu.regs[record.register_index] = record.register_old
	}
	if record.csr_changed {
		// Restore the exact old value (no WARL fix-ups on the way back).
		csr_restore(&machine.cpu, record.csr_address, record.csr_old)
	}
	if record.reservation_changed {
		machine.cpu.reservation = record.reservation_old
	}
	if record.trap_taken {
		machine.cpu.csr.mstatus = record.trap_mstatus
		machine.cpu.csr.mepc = record.trap_mepc
		machine.cpu.csr.mcause = record.trap_mcause
		machine.cpu.csr.mtval = record.trap_mtval
	}
	machine.cpu.pc = record.pc
	machine.cpu.instret = record.instret
	machine.cpu.cycle = record.cycle
	machine.cpu.privilege = record.privilege
	machine.cpu.last_write = {}
	machine.last_trap = nil
	machine_update_interrupts(machine)
	return true
}

// Runs until a trap or until `max_steps` (0 = no limit), calling
// `observer` (if given) after each step.
machine_run :: proc(machine: ^Machine, max_steps: u64, observer: Step_Observer = nil) -> Run_Result {
	steps: u64 = 0
	for max_steps == 0 || steps < max_steps {
		pc := machine.cpu.pc
		result := machine_step(machine)
		steps += 1

		if observer != nil {
			observer(machine, pc, result)
		}

		if trap, has_trap := result.?; has_trap {
			reason := Stop_Reason.Breakpoint if trap.cause == .Breakpoint else Stop_Reason.Trap
			return Run_Result{reason = reason, trap = trap, steps = steps}
		}
		if exit_code, exited := machine_host_exit(machine).?; exited {
			return Run_Result{reason = .Host_Exit, steps = steps, exit_code = exit_code}
		}
	}
	return Run_Result{reason = .Step_Limit, steps = steps}
}

// The `tohost` exit convention ("HTIF", from the Spike simulator), used by
// riscv-tests: the program writes a value to its `tohost` variable to talk
// to the outside world. A value with bit 0 set means "exit", with the exit
// code in the remaining bits: 1 = exit code 0 (pass); (n << 1) | 1 = exit
// code n (riscv-tests: test n failed).
//
// Returns the exit code once the program has asked to exit, else nil.
machine_host_exit :: proc(machine: ^Machine) -> Maybe(u64) {
	address, has_tohost := machine.tohost.?
	if !has_tohost {
		return nil
	}
	value, _ := machine_peek(machine, address, 8)
	if value & 1 == 0 {
		return nil
	}
	return value >> 1
}

// Loads, stores and peeks as the machine sees memory and its devices
// now (at its step clock): for front ends and tests, which would
// otherwise pass cpu_clock(&machine.cpu) to the bus themselves. These aren't
// steps, so they aren't undone; but a load or store can change a device's
// interrupt lines (setting mtimecmp), so mip is worked out again after one.
machine_load :: proc(machine: ^Machine, address: u64, size: u64) -> (value: u64, ok: bool) {
	value, ok = bus_load(&machine.bus, address, size, cpu_clock(&machine.cpu))
	after_front_end_access(machine)
	return value, ok
}

machine_peek :: proc(machine: ^Machine, address: u64, size: u64) -> (value: u64, ok: bool) {
	return bus_peek(&machine.bus, address, size, cpu_clock(&machine.cpu))
}

machine_store :: proc(machine: ^Machine, address: u64, size: u64, value: u64) -> bool {
	ok := bus_store(&machine.bus, address, size, value, cpu_clock(&machine.cpu))
	after_front_end_access(machine)
	return ok
}

// If the access reached a device: forget the touch (it belongs to no
// step) and look at the interrupt lines again.
@(private = "file")
after_front_end_access :: proc(machine: ^Machine) {
	if machine.bus.touched.touched {
		machine.bus.touched = {}
		machine_update_interrupts(machine)
	}
}
