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
}

// Why `machine_run` returned.
Stop_Reason :: enum {
	// EBREAK: the normal way for a test program to finish.
	Breakpoint,
	// Any other trap while no handler is set up (mtvec = 0).
	Trap,
	// The step limit was reached (guards against endless loops).
	Step_Limit,
}

Run_Result :: struct {
	reason: Stop_Reason,
	trap:   Trap,
	steps:  u64,
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
	return machine
}

machine_destroy :: proc(machine: ^Machine) {
	history_destroy(&machine.history)
	bus_destroy(&machine.bus)
}

// Runs one instruction and records how to undo it.
//
// If the instruction traps and a handler is set up (mtvec != 0), the trap
// is taken: the hart jumps to the handler, `last_trap` is set and the
// step counts as done (nil). If there is no handler, nothing changed, so
// nothing is recorded and the trap is returned: the machine stops.
machine_step :: proc(machine: ^Machine) -> Step_Result {
	cpu := &machine.cpu
	cpu.undo = Undo_Record {
		pc        = cpu.pc,
		instret   = cpu.instret,
		privilege = cpu.privilege,
	}
	machine.last_trap = nil

	result := cpu_step(cpu, &machine.bus)
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
	}

	if history_is_enabled(&machine.history) {
		history_push(&machine.history, cpu.undo)
	}
	return nil
}

// Undoes the most recent recorded step. Returns false when there is
// nothing left to undo (start of the program, or history full and wrapped).
machine_step_back :: proc(machine: ^Machine) -> bool {
	record, ok := history_pop(&machine.history)
	if !ok {
		return false
	}
	if record.memory_changed {
		bus_store(&machine.bus, record.memory_address, record.memory_size, record.memory_old)
	}
	if record.register_changed {
		machine.cpu.regs[record.register_index] = record.register_old
	}
	if record.csr_changed {
		// The old value was read from the CSR, so it is already legal and
		// writing it back restores it exactly.
		csr_write(&machine.cpu, record.csr_address, record.csr_old)
	}
	if record.trap_taken {
		machine.cpu.csr.mstatus = record.trap_mstatus
		machine.cpu.csr.mepc = record.trap_mepc
		machine.cpu.csr.mcause = record.trap_mcause
		machine.cpu.csr.mtval = record.trap_mtval
	}
	machine.cpu.pc = record.pc
	machine.cpu.instret = record.instret
	machine.cpu.privilege = record.privilege
	machine.cpu.last_write = {}
	machine.last_trap = nil
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
	}
	return Run_Result{reason = .Step_Limit, steps = steps}
}
