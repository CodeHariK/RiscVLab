package emulator

import "core:fmt"

// Per-instruction trace, enabled with --trace. One line per instruction:
//
//   <pc>  <instruction bits>  [x<rd> <- <value>]
//
// The format is deliberately plain so it can be diffed against a reference
// simulator's log (Spike's --log-commits) once a converter script exists.
trace_step :: proc(cpu: ^Cpu, bus: ^Bus, pc: u64, result: Step_Result) {
	raw, _ := bus_load(bus, pc, 4)
	instruction := u32(raw)

	if trap, has_trap := result.?; has_trap {
		fmt.printfln("%016x  %08x  trap %v value=%016x", pc, instruction, trap.cause, trap.value)
		return
	}

	write := cpu.last_write
	if write.valid {
		fmt.printfln("%016x  %08x  x%d <- %016x", pc, instruction, write.index, write.value)
	} else {
		fmt.printfln("%016x  %08x", pc, instruction)
	}
}
