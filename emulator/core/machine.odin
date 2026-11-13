package rv

// The whole emulated computer: one hart, the bus it is wired to, and the
// undo history used for stepping backwards.
//
// This file is the core's public API for front ends (the command-line
// runner, the debugger UI). Nothing in the core reads files or prints,
// so the same core can later be compiled to WebAssembly.
Machine :: struct {
	cpu:     Cpu,
	bus:     Bus,
	history: History,
}

// Why `machine_run` returned.
Stop_Reason :: enum {
	// EBREAK: the normal way for a test program to finish.
	Breakpoint,
	// Any other trap. There is no trap handler until the Zicsr milestone,
	// so every trap stops the machine for now.
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
	return machine
}

machine_destroy :: proc(machine: ^Machine) {
	history_destroy(&machine.history)
	bus_destroy(&machine.bus)
}

// Runs one instruction and, if it completed, records how to undo it.
// A trapping instruction changes nothing yet, so it isn't recorded.
machine_step :: proc(machine: ^Machine) -> Step_Result {
	machine.cpu.undo = Undo_Record {
		pc      = machine.cpu.pc,
		instret = machine.cpu.instret,
	}
	result := cpu_step(&machine.cpu, &machine.bus)
	if result == nil && history_is_enabled(&machine.history) {
		history_push(&machine.history, machine.cpu.undo)
	}
	return result
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
	machine.cpu.pc = record.pc
	machine.cpu.instret = record.instret
	machine.cpu.last_write = {}
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
