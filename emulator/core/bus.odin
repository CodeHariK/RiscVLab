package rv

import "base:intrinsics"

// The system bus: routes a physical address to whatever lives there.
//
// For now that is only RAM. The UART, CLINT, PLIC and virtio devices will
// be added here, each claiming its own address range from memory_map.odin.
Bus :: struct {
	ram: []u8,
}

// RAM comes straight from the OS (zeroed_pages.odin), so untouched RAM
// takes no physical memory.
bus_create :: proc(ram_size: u64) -> Bus {
	return Bus{ram = zeroed_pages_alloc(int(ram_size))}
}

bus_destroy :: proc(bus: ^Bus) {
	zeroed_pages_free(bus.ram)
	bus.ram = nil
}

// Finds where [addr, addr + size) lives inside RAM.
// Returns ok = false if any of those bytes fall outside RAM.
@(private = "file")
ram_offset :: #force_inline proc(bus: ^Bus, addr: u64, size: u64) -> (offset: u64, ok: bool) {
	if addr < RAM_BASE {
		return 0, false
	}
	offset = addr - RAM_BASE
	ram_length := u64(len(bus.ram))
	// Written this way round so `offset + size` can never overflow.
	if size > ram_length || offset > ram_length - size {
		return 0, false
	}
	return offset, true
}

// The RAM bytes for [addr, addr + size), for bulk copies such as loading
// a program. ok = false if any of the range is outside RAM.
bus_ram_slice :: proc(bus: ^Bus, addr: u64, size: u64) -> (bytes: []u8, ok: bool) {
	offset := ram_offset(bus, addr, size) or_return
	return bus.ram[offset:offset + size], true
}

// Reads `size` bytes (1, 2, 4 or 8) as a little-endian value,
// zero-extended to 64 bits. Callers do any sign extension themselves.
//
// Misaligned addresses are allowed, as on QEMU. The direct pointer loads
// assume a little-endian host (Apple Silicon and x86 both are).
bus_load :: proc(bus: ^Bus, addr: u64, size: u64) -> (value: u64, ok: bool) {
	offset := ram_offset(bus, addr, size) or_return
	location := &bus.ram[offset]
	switch size {
	case 1:
		value = u64(location^)
	case 2:
		value = u64(intrinsics.unaligned_load((^u16)(location)))
	case 4:
		value = u64(intrinsics.unaligned_load((^u32)(location)))
	case 8:
		value = intrinsics.unaligned_load((^u64)(location))
	case:
		return 0, false
	}
	return value, true
}

// Reads like bus_load, but only to look: the debugger's views, the old
// bytes saved for undo, the tohost check. For RAM the two are the same.
// They will differ for devices whose reads change them (reading a UART's
// receive register takes the byte out of it): bus_load is what a load
// instruction does, bus_peek must leave the device as it was.
bus_peek :: proc(bus: ^Bus, addr: u64, size: u64) -> (value: u64, ok: bool) {
	return bus_load(bus, addr, size)
}

// Writes the low `size` bytes (1, 2, 4 or 8) of `value`, little-endian.
bus_store :: proc(bus: ^Bus, addr: u64, size: u64, value: u64) -> bool {
	offset, ok := ram_offset(bus, addr, size)
	if !ok {
		return false
	}
	location := &bus.ram[offset]
	switch size {
	case 1:
		location^ = u8(value)
	case 2:
		intrinsics.unaligned_store((^u16)(location), u16(value))
	case 4:
		intrinsics.unaligned_store((^u32)(location), u32(value))
	case 8:
		intrinsics.unaligned_store((^u64)(location), value)
	case:
		return false
	}
	return true
}
