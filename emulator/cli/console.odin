package rvemu

import "core:os"
import rv "../core"
import devices "../devices"

// The program's console: what it sends to the UART is written to stdout.

// Steps between writes to stdout, so a long-running program's output
// appears while it runs rather than only at the end.
CONSOLE_FLUSH_STEPS :: u64(100_000)

// Runs like rv.machine_run (0 = no step limit), writing the UART's new
// output to stdout every CONSOLE_FLUSH_STEPS steps and at the end.
run_with_console :: proc(machine: ^rv.Machine, uart: ^devices.Uart, max_steps: u64, observer: rv.Step_Observer) -> rv.Run_Result {
	written := 0
	total: u64 = 0
	for {
		chunk := CONSOLE_FLUSH_STEPS
		if max_steps != 0 {
			chunk = min(chunk, max_steps - total)
		}
		result := rv.machine_run(machine, chunk, observer)
		total += result.steps
		written = write_console(uart, written)
		if result.reason != .Step_Limit || (max_steps != 0 && total >= max_steps) {
			result.steps = total
			return result
		}
	}
}

// Writes the output after the first `written` bytes; returns the new count.
@(private = "file")
write_console :: proc(uart: ^devices.Uart, written: int) -> int {
	if uart == nil || len(uart.output) <= written {
		return written
	}
	os.write(os.stdout, uart.output[written:])
	return len(uart.output)
}
