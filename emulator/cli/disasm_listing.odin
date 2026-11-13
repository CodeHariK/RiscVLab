package rvemu

import "core:fmt"
import rv "../core"

// --disasm: prints every 4-byte word of the image as
//   <address> <bits> <disassembly>
// The format is what tests/compare_disasm.sh expects, so `make test` can
// diff it against objdump's listing of the same program.
print_disassembly :: proc(image: []u8) {
	buffer: [rv.DISASM_BUFFER_SIZE]u8
	for offset := 0; offset + 4 <= len(image); offset += 4 {
		instruction := u32(image[offset]) |
			u32(image[offset + 1]) << 8 |
			u32(image[offset + 2]) << 16 |
			u32(image[offset + 3]) << 24
		pc := rv.RAM_BASE + u64(offset)
		fmt.printfln("%x %08x %s", pc, instruction, rv.disassemble(buffer[:], pc, instruction))
	}
}
