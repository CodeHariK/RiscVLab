package rvemu

import "core:fmt"
import rv "../core"
import disasm "../disasm"

// Per-instruction trace (--trace). One line per instruction:
//
//   <pc>  <bits>  <disassembly>                  [<reg> <- <value>]
//
// A trap taken into a handler prints "trap <cause> -> handler <address>".
// An interrupt is taken before the instruction at the pc runs, so its line
// says so: "interrupt <cause> before this instruction -> handler <address>"
// (the instruction runs after the handler's mret).
// Used as the machine_run observer. Written to stderr, like the report:
// stdout is the program's output.
print_trace_line :: proc(machine: ^rv.Machine, pc: u64, result: rv.Step_Result) {
	raw, _ := rv.machine_peek(machine, pc, 4)
	instruction := u32(raw)
	buffer: [disasm.BUFFER_SIZE]u8
	text := disasm.disassemble(buffer[:], pc, instruction)

	if trap, has_trap := result.?; has_trap {
		if rv.trap_is_interrupt(trap.cause) {
			fmt.eprintfln("%016x  %08x  %-28s interrupt %v before this instruction, no handler", pc, instruction, text, trap.cause)
			return
		}
		fmt.eprintfln("%016x  %08x  %-28s trap %v value=%016x", pc, instruction, text, trap.cause, trap.value)
		return
	}

	if trap, took_trap := machine.last_trap.?; took_trap {
		if rv.trap_is_interrupt(trap.cause) {
			fmt.eprintfln(
				"%016x  %08x  %-28s interrupt %v before this instruction -> handler %016x",
				pc,
				instruction,
				text,
				trap.cause,
				machine.cpu.pc,
			)
			return
		}
		fmt.eprintfln(
			"%016x  %08x  %-28s trap %v value=%x -> handler %016x",
			pc,
			instruction,
			text,
			trap.cause,
			trap.value,
			machine.cpu.pc,
		)
		return
	}

	write := machine.cpu.last_write
	if write.valid {
		fmt.eprintfln("%016x  %08x  %-28s %s <- %016x", pc, instruction, text, disasm.register_name(write.index), write.value)
	} else {
		fmt.eprintfln("%016x  %08x  %s", pc, instruction, text)
	}
}
