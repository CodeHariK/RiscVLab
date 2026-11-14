package rvemu

import "core:fmt"
import rv "../core"

// Prints why the machine stopped and returns the process exit code.
// After EBREAK the exit code is a0 (low 8 bits), so test programs can
// report pass (0) or the number of the failing check. Programs that use
// `tohost` (riscv-tests) report their own exit code there.
report_result :: proc(machine: ^rv.Machine, result: rv.Run_Result) -> int {
	cpu := &machine.cpu
	a0 := rv.reg_read(cpu, rv.REG_A0)

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
	case .Host_Exit:
		if result.exit_code == 0 {
			fmt.printfln("tohost: exit code 0 (pass) after %d instructions", cpu.instret)
		} else {
			fmt.printfln("tohost: exit code %d (riscv-tests: test %d failed) at pc=0x%016x", result.exit_code, result.exit_code, cpu.pc)
		}
		return int(min(result.exit_code, 255))
	case .Step_Limit:
		fmt.printfln("stopped: step limit of %d reached at pc=0x%016x", result.steps, cpu.pc)
		return 1
	}
	return 1
}
