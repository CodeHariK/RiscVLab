package rvemu

import "core:fmt"
import rv "../core"

// --disasm: prints every instruction in the program's code range as
//   <address> <bits> <disassembly>
// The format is what tests/compare_disasm.sh expects, so `make test` can
// diff it against objdump's listing of the same program.
print_disassembly :: proc(machine: ^rv.Machine, program: rv.Program) {
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	for pc := program.code_start; pc + 4 <= program.code_end; pc += 4 {
		raw, _ := rv.bus_load(&machine.bus, pc, 4)
		instruction := u32(raw)
		fmt.printfln("%x %08x %s", pc, instruction, rv.disassemble(buffer[:], pc, instruction))
	}
}
