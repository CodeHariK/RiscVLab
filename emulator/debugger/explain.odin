package rvdbg

import "core:fmt"
import "core:strings"
import rv "../core"

// The Status line of the explanation panel. (The Next and Last lines are
// the step details: step_detail.odin.) All strings are allocated with the
// temp allocator, which is freed after each frame.

// One-line state of the program for the status row.
explain_status :: proc(session: ^Session) -> string {
	cpu := &session.machine.cpu
	if trap, stopped := session.stopped.?; stopped {
		if trap.cause == .Breakpoint {
			return fmt.tprintf(
				"Program finished (ebreak) after %d instructions. a0 = %s",
				cpu.instret,
				value_text(rv.reg_read(cpu, rv.REG_A0)),
			)
		}
		return fmt.tprintf("Stopped: %v (value 0x%x) at pc 0x%x", trap.cause, trap.value, cpu.pc)
	}
	if exit_code, exited := session.exited.?; exited {
		if exit_code == 0 {
			return fmt.tprintf("Program finished through tohost after %d instructions: exit code 0 (pass)", cpu.instret)
		}
		return fmt.tprintf("Program finished through tohost: exit code %s (riscv-tests: test %d failed)", value_text(u64(exit_code)), exit_code)
	}
	if cpu.instret == 0 {
		return "Ready. Press Next (or the right arrow key) to run the first instruction."
	}
	return fmt.tprintf("Paused after %d instructions.", cpu.instret)
}
