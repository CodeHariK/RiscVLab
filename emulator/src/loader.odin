package emulator

import "core:fmt"
import "core:os"

// Copies a raw binary image (as produced by `objcopy -O binary`) into RAM,
// starting at RAM_BASE. ELF loading will come later, for riscv-tests.
load_raw_binary :: proc(bus: ^Bus, path: string) -> bool {
	data, error := os.read_entire_file(path, context.allocator)
	if error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, error)
		return false
	}
	defer delete(data)

	if len(data) > len(bus.ram) {
		fmt.eprintfln("error: %s is %d bytes, larger than RAM (%d bytes)", path, len(data), len(bus.ram))
		return false
	}
	copy(bus.ram, data)
	return true
}
