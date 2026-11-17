package rv

import "base:intrinsics"

// The system bus: routes a physical address to whatever lives there: RAM,
// or a device that claimed an address range (memory_map.odin). Devices
// (the UART, later the CLINT, PLIC and virtio) live outside the core, in
// the devices package: the bus only knows them through Device, a set of
// procedures, so the core doesn't depend on any of them. Front ends attach
// the devices a machine has (devices.uart_attach).
Bus :: struct {
	ram:          []u8,
	devices:      [MAX_DEVICES]Device,
	device_count: int,
	// The device this step's load or store changed, with its state from
	// before, for undo (machine_step copies it to the undo record).
	touched:      Device_Touch,
}

MAX_DEVICES :: 8

// A device's state, packed by the device into a fixed number of bytes,
// so one undo record can hold it (history.odin).
DEVICE_STATE_SIZE :: 32
Device_State :: [DEVICE_STATE_SIZE]u8

// A device on the bus. `offset` is from the start of its range. Loads and
// stores may change the device (reading a UART's receive register takes
// the byte out of it); peek must not. ok = false raises an access fault,
// e.g. for an access size the device doesn't support.
Device :: struct {
	name:    string,
	base:    u64,
	size:    u64,
	data:    rawptr, // the device itself, passed to every procedure
	load:    proc(data: rawptr, offset: u64, size: u64) -> (value: u64, ok: bool),
	peek:    proc(data: rawptr, offset: u64, size: u64) -> (value: u64, ok: bool),
	store:   proc(data: rawptr, offset: u64, size: u64, value: u64) -> (ok: bool),
	// Undo: the state a load or store may change, and putting it back.
	save:    proc(data: rawptr) -> Device_State,
	restore: proc(data: rawptr, state: Device_State),
	// Frees the device (bus_destroy).
	destroy: proc(data: rawptr),
}

Device_Touch :: struct {
	touched: bool,
	index:   int,
	state:   Device_State,
}

// RAM comes straight from the OS (zeroed_pages.odin), so untouched RAM
// takes no physical memory.
bus_create :: proc(ram_size: u64) -> Bus {
	return Bus{ram = zeroed_pages_alloc(int(ram_size))}
}

bus_destroy :: proc(bus: ^Bus) {
	zeroed_pages_free(bus.ram)
	bus.ram = nil
	for device in bus.devices[:bus.device_count] {
		if device.destroy != nil {
			device.destroy(device.data)
		}
	}
	bus.device_count = 0
}

// Adds a device. Fails if there is no room or its range overlaps RAM or
// another device.
bus_attach :: proc(bus: ^Bus, device: Device) -> bool {
	if bus.device_count == MAX_DEVICES || device.size == 0 {
		return false
	}
	ram_end := RAM_BASE + u64(len(bus.ram))
	if ranges_overlap(device.base, device.size, RAM_BASE, ram_end - RAM_BASE) {
		return false
	}
	for other in bus.devices[:bus.device_count] {
		if ranges_overlap(device.base, device.size, other.base, other.size) {
			return false
		}
	}
	bus.devices[bus.device_count] = device
	bus.device_count += 1
	return true
}

// The device whose range holds all of [addr, addr + size), if any.
bus_device_at :: proc(bus: ^Bus, addr: u64, size: u64 = 1) -> (device: ^Device, index: int, ok: bool) {
	for &candidate, candidate_index in bus.devices[:bus.device_count] {
		if addr >= candidate.base && size <= candidate.size && addr - candidate.base <= candidate.size - size {
			return &candidate, candidate_index, true
		}
	}
	return nil, -1, false
}

@(private = "file")
ranges_overlap :: proc(a: u64, a_size: u64, b: u64, b_size: u64) -> bool {
	return a < b + b_size && b < a + a_size
}

// Before a load or store that may change device `index`: keep its state
// for undo (the first one in a step is the one to restore).
@(private = "file")
note_touch :: proc(bus: ^Bus, device: ^Device, index: int) {
	if bus.touched.touched {
		return
	}
	bus.touched = {touched = true, index = index}
	if device.save != nil {
		bus.touched.state = device.save(device.data)
	}
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

// Fetches an instruction: from RAM only. Executing a device's registers
// would read them with side effects; it raises an access fault instead,
// as on real hardware, where device regions aren't executable.
bus_fetch :: proc(bus: ^Bus, addr: u64) -> (instruction: u32, ok: bool) {
	value := ram_load(bus, addr, 4) or_return
	return u32(value), true
}

// Reads `size` bytes (1, 2, 4 or 8) as a little-endian value,
// zero-extended to 64 bits, from RAM or a device. Callers do any sign
// extension themselves.
//
// Misaligned addresses are allowed in RAM, as on QEMU.
bus_load :: proc(bus: ^Bus, addr: u64, size: u64) -> (value: u64, ok: bool) {
	if value, ok = ram_load(bus, addr, size); ok {
		return
	}
	device, index := bus_device_at(bus, addr, size) or_return
	note_touch(bus, device, index)
	return device.load(device.data, addr - device.base, size)
}

// RAM only. The direct pointer loads assume a little-endian host (Apple
// Silicon and x86 both are).
@(private = "file")
ram_load :: #force_inline proc(bus: ^Bus, addr: u64, size: u64) -> (value: u64, ok: bool) {
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
// bytes saved for undo, the tohost check. For RAM the two are the same;
// a device must stay as it was (reading a UART's receive register would
// take the byte out of it). A device whose registers are bytes is peeked
// a byte at a time, so the debugger's 4-byte views can show it too.
bus_peek :: proc(bus: ^Bus, addr: u64, size: u64) -> (value: u64, ok: bool) {
	if value, ok = ram_load(bus, addr, size); ok {
		return
	}
	device, _ := bus_device_at(bus, addr, size) or_return
	if device.peek == nil {
		return 0, false
	}
	if value, ok = device.peek(device.data, addr - device.base, size); ok {
		return
	}
	value = 0
	for i in 0 ..< size {
		piece := device.peek(device.data, addr - device.base + i, 1) or_return
		value |= (piece & 0xFF) << (8 * i)
	}
	return value, true
}

// Writes the low `size` bytes (1, 2, 4 or 8) of `value`, little-endian,
// to RAM or a device.
bus_store :: proc(bus: ^Bus, addr: u64, size: u64, value: u64) -> bool {
	offset, in_ram := ram_offset(bus, addr, size)
	if !in_ram {
		device, index := bus_device_at(bus, addr, size) or_return
		note_touch(bus, device, index)
		return device.store(device.data, addr - device.base, size, value)
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
