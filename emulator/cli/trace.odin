package rvemu

import "core:fmt"
import rv "../core"

// Per-instruction trace (--trace). One line per instruction:
//
//   <pc>  <bits>  <disassembly>                  [<reg> <- <value>]
//
// Used as the machine_run observer.
print_trace_line :: proc(machine: ^rv.Machine, pc: u64, result: rv.Step_Result) {
	raw, _ := rv.bus_load(&machine.bus, pc, 4)
	instruction := u32(raw)
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	text := rv.disassemble(buffer[:], pc, instruction)

	if trap, has_trap := result.?; has_trap {
		fmt.printfln("%016x  %08x  %-28s trap %v value=%016x", pc, instruction, text, trap.cause, trap.value)
		return
	}

	write := machine.cpu.last_write
	if write.valid {
		fmt.printfln("%016x  %08x  %-28s %s <- %016x", pc, instruction, text, rv.register_name(write.index), write.value)
	} else {
		fmt.printfln("%016x  %08x  %s", pc, instruction, text)
	}
}
