package rv_unit_tests

import "core:testing"
import rv "../core"
import loader "../loader"

// Unit tests for the ELF loader's checks (loader/elf.odin).
//
// They build an ELF file by hand: only the 64-byte header, with no
// segments, so there's nothing to copy into RAM; only the entry point is
// checked and used.

// A minimal ELF64 header for RISC-V with no segments, entry at `entry`.
// Byte offsets are those of the ELF64 header (docs: elf): the magic
// number, the class and byte order, the file type, the machine, and the
// 8-byte entry point at offset 24, written little-endian.
@(private = "file")
elf_header :: proc(entry: u64) -> [64]u8 {
	header: [64]u8
	header[0], header[1], header[2], header[3] = 0x7F, 'E', 'L', 'F'
	header[4] = 2 // 64-bit
	header[5] = 1 // little-endian
	header[16] = 2 // executable
	header[18] = 243 // RISC-V
	for i in 0 ..< 8 {
		header[24 + i] = u8(entry >> (8 * u64(i)))
	}
	return header
}

@(test)
misaligned_entry_point_is_refused :: proc(t: ^testing.T) {
	// Instructions are 4-byte aligned (no C extension), so an entry point
	// at RAM_BASE + 2 could never be fetched: the loader refuses the file
	// rather than letting the first fetch fail.
	machine := rv.machine_create(64 * 1024, 0)
	defer rv.machine_destroy(&machine)
	image := elf_header(rv.RAM_BASE + 2)
	_, error := loader.load_program(&machine, image[:])
	testing.expect_value(t, error, loader.Load_Error(loader.Elf_Error.Entry_Misaligned))
}

@(test)
aligned_entry_point_loads :: proc(t: ^testing.T) {
	machine := rv.machine_create(64 * 1024, 0)
	defer rv.machine_destroy(&machine)
	image := elf_header(rv.RAM_BASE + 4)
	_, error := loader.load_program(&machine, image[:])
	// Loaded, and the pc set to the entry point, ready for the first step.
	testing.expect(t, error == nil)
	testing.expect_value(t, machine.cpu.pc, rv.RAM_BASE + 4)
}
