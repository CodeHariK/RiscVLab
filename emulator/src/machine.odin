package emulator

import "core:fmt"

// The whole emulated computer: one hart plus the bus it is wired to.
Machine :: struct {
	cpu: Cpu,
	bus: Bus,
}

// Why `machine_run` returned.
Stop_Reason :: enum {
	// EBREAK: the normal way for a test program to finish.
	Breakpoint,
	// Any other trap. There is no trap handler until the Zicsr milestone,
	// so every trap stops the machine for now.
	Trap,
	// The `--max-steps` limit was reached (guards against endless loops).
	Step_Limit,
}

Run_Result :: struct {
	reason: Stop_Reason,
	trap:   Trap,
	steps:  u64,
}

// Creates a machine with `ram_size` bytes of zeroed RAM, PC at RAM_BASE.
machine_create :: proc(ram_size: u64) -> Machine {
	machine := Machine{bus = bus_create(ram_size)}
	machine.cpu.pc = RAM_BASE
	return machine
}

machine_destroy :: proc(machine: ^Machine) {
	bus_destroy(&machine.bus)
}

// Runs instructions until a trap or until `max_steps` (0 = no limit).
machine_run :: proc(machine: ^Machine, max_steps: u64, trace: bool) -> Run_Result {
	steps: u64 = 0
	for max_steps == 0 || steps < max_steps {
		pc := machine.cpu.pc
		result := cpu_step(&machine.cpu, &machine.bus)
		steps += 1

		if trace {
			trace_step(&machine.cpu, &machine.bus, pc, result)
		}

		if trap, has_trap := result.?; has_trap {
			reason := Stop_Reason.Breakpoint if trap.cause == .Breakpoint else Stop_Reason.Trap
			return Run_Result{reason = reason, trap = trap, steps = steps}
		}
	}
	return Run_Result{reason = .Step_Limit, steps = steps}
}

// Prints why the machine stopped and returns the process exit code.
// After EBREAK the exit code is a0 (low 8 bits), so test programs can
// report pass (0) or the number of the failing check.
machine_report :: proc(machine: ^Machine, result: Run_Result) -> int {
	cpu := &machine.cpu
	a0 := reg_read(cpu, REG_A0)

	switch result.reason {
	case .Breakpoint:
		fmt.printfln("ebreak at pc=0x%016x after %d instructions, a0=%d", cpu.pc, cpu.instret, a0)
		return int(a0 & 0xFF)
	case .Trap:
		fmt.printfln(
			"stopped: %v (value=0x%016x) at pc=0x%016x after %d instructions",
			result.trap.cause,
			result.trap.value,
			cpu.pc,
			cpu.instret,
		)
		return 1
	case .Step_Limit:
		fmt.printfln("stopped: step limit of %d reached at pc=0x%016x", result.steps, cpu.pc)
		return 1
	}
	return 1
}
