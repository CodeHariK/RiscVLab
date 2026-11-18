package view

import "core:fmt"
import rv "../../core"
import devices "../../devices"
import state "../state"

// Words for loads and stores that reach a device instead of memory
// (memory-mapped I/O), for the step details and the Steps list.

// "uart THR (0x10000000)" if `address` is a device register, with the
// register's name when the device has one for it.
device_place :: proc(session: ^state.Session, address: u64, writing: bool) -> (text: string, on_device: bool) {
	device, _, found := rv.bus_device_at(&session.machine.bus, address)
	if !found {
		return "", false
	}
	offset := address - device.base
	name := ""
	switch device.name {
	case "uart":
		if session.uart != nil {
			name = devices.uart_register_name(session.uart, offset, writing)
		}
	case "clint":
		switch {
		case offset >= devices.CLINT_MSIP && offset < devices.CLINT_MSIP + 4: name = "msip"
		case offset >= devices.CLINT_MTIMECMP && offset < devices.CLINT_MTIMECMP + 8: name = "mtimecmp"
		case offset >= devices.CLINT_MTIME && offset < devices.CLINT_MTIME + 8: name = "mtime"
		}
	}
	if name == "" {
		return fmt.tprintf("%s+0x%x (0x%x)", device.name, offset, address), true
	}
	return fmt.tprintf("%s %s (0x%x)", device.name, name, address), true
}

// The value a load got from, or a store gave to, the device register at
// `address`: as a character too when the register carries data (the
// UART's THR / RBR: 0x48 (72) 'H'), as a plain number when it is a
// control or status register (LSR 0x60 (96), not '`').
device_value_text :: proc(session: ^state.Session, address: u64, writing: bool, value: u64) -> string {
	device, _, found := rv.bus_device_at(&session.machine.bus, address)
	if found && device.name == "uart" && session.uart != nil {
		switch devices.uart_register_name(session.uart, address - device.base, writing) {
		case "THR", "RBR":
			return byte_text(value)
		}
		return value_text(u64(u8(value))) // UART registers are bytes
	}
	return value_text(value)
}

// A byte as a number and, when it is a printable character, as that
// character: 0x48 'H', 0xa (10) '\n'.
byte_text :: proc(value: u64) -> string {
	character := u8(value)
	switch character {
	case ' ' ..= '~':
		return fmt.tprintf("%s '%c'", value_text(u64(character)), character)
	case '\n':
		return fmt.tprintf("%s '\\n'", value_text(u64(character)))
	}
	return value_text(u64(character))
}
