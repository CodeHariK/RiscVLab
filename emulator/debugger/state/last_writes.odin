package state

import rv "../../core"
import devices "../../devices"

// Which step last wrote each register, CSR and device register, so the
// views can show what the program has set up so far ("#4": written by
// step 4) next to what the current step changes.
//
// Kept up to date as steps run rather than worked out from the timeline
// each frame: Next records what each write replaced in its timeline
// entry, and Prev puts that back. Reset clears it all.
//
// Only explicit writes count: a register an instruction writes, a CSR a
// CSR instruction or MRET writes, the CSRs trap entry sets (mstatus,
// mepc, mcause, mtval), a device register a store writes. The counters'
// own counting each step doesn't.

Last_Writes :: struct {
	registers:        [rv.REGISTER_COUNT]int, // step number, 0 = never written
	csrs:             map[u32]int,
	// By device and register name as the store saw it ("uart.THR",
	// "uart.DLL": the same offset is a different register with DLAB set).
	device_registers: map[string]int,
}

Write_Kind :: enum u8 {
	Register,
	Csr,
	Device_Register,
}

// One write a step made, and the step that had written there before it.
Write_Change :: struct {
	kind:     Write_Kind,
	index:    u32,    // register number, or CSR address
	name:     string, // device register ("uart.LCR"); a constant string
	previous: int,
}

// A step writes at most a register, a device register and the four CSRs
// trap entry sets.
MAX_WRITE_CHANGES :: 6

Step_Writes :: struct {
	changes: [MAX_WRITE_CHANGES]Write_Change,
	count:   int,
}

// The step number that last wrote register x`index`, 0 if none.
last_write_register :: proc(session: ^Session, index: u32) -> int {
	return session.last_writes.registers[index]
}

last_write_csr :: proc(session: ^Session, address: u32) -> int {
	return session.last_writes.csrs[address] or_else 0
}

// `name` as device_register_name gives it, e.g. "uart.DLL".
last_write_device_register :: proc(session: ^Session, name: string) -> int {
	return session.last_writes.device_registers[name] or_else 0
}

// "uart.THR": the register a store to `address` writes right now (before
// the step: LCR's DLAB decides between THR and DLL), or "" if it isn't a
// device register this knows by name.
device_register_name :: proc(session: ^Session, address: u64) -> string {
	device, _, found := rv.bus_device_at(&session.machine.bus, address)
	if !found {
		return ""
	}
	if device.name == "clint" {
		offset := address - device.base
		switch {
		case offset >= devices.CLINT_MSIP && offset < devices.CLINT_MSIP + 4: return "clint.msip"
		case offset >= devices.CLINT_MTIMECMP && offset < devices.CLINT_MTIMECMP + 8: return "clint.mtimecmp"
		case offset >= devices.CLINT_MTIME && offset < devices.CLINT_MTIME + 8: return "clint.mtime"
		}
		return ""
	}
	if device.name != "uart" || session.uart == nil {
		return ""
	}
	switch devices.uart_register_name(session.uart, address - device.base, true) {
	case "THR": return "uart.THR"
	case "DLL": return "uart.DLL"
	case "DLM": return "uart.DLM"
	case "IER": return "uart.IER"
	case "FCR": return "uart.FCR"
	case "LCR": return "uart.LCR"
	case "MCR": return "uart.MCR"
	case "SCR": return "uart.SCR"
	}
	return "" // LSR, MSR: writes are ignored
}

// After step `step` ran: records what it wrote, in `writes` (so Prev can
// undo it) and in the session's Last_Writes.
@(private)
last_writes_record :: proc(session: ^Session, step: int, record: rv.Undo_Record, device_register: string, writes: ^Step_Writes) {
	last := &session.last_writes
	if record.register_changed {
		index := record.register_index
		add_write(writes, {kind = .Register, index = index, previous = last.registers[index]})
		last.registers[index] = step
	}
	if record.csr_changed {
		csr_written(last, writes, record.csr_address, step)
	}
	if record.trap_taken {
		// mstatus (which sstatus shows too), and the trio of the mode
		// that took the trap.
		trio := []u32{rv.CSR_MEPC, rv.CSR_MCAUSE, rv.CSR_MTVAL}
		if record.trap_to_supervisor {
			trio = []u32{rv.CSR_SEPC, rv.CSR_SCAUSE, rv.CSR_STVAL}
		}
		csr_written(last, writes, rv.CSR_MSTATUS, step)
		for address in trio {
			csr_written(last, writes, address, step)
		}
	}
	// Rows that changed through a view (csr_views.odin): mie after a
	// csrw sie, sstatus after a trap into supervisor mode, sie and sip
	// after a csrw mideleg, ...
	for address in CSR_VIEW_ROWS {
		named := (record.csr_changed && record.csr_address == address) || (record.trap_taken && address == rv.CSR_MSTATUS)
		if !named && csr_changed_through_view(&session.machine.cpu, record, address) {
			csr_written(last, writes, address, step)
		}
	}
	if device_register != "" && record.device_changed {
		add_write(writes, {kind = .Device_Register, name = device_register, previous = last.device_registers[device_register] or_else 0})
		last.device_registers[device_register] = step
	}
}

@(private = "file")
add_write :: proc(writes: ^Step_Writes, change: Write_Change) {
	if writes.count < MAX_WRITE_CHANGES {
		writes.changes[writes.count] = change
		writes.count += 1
	}
}

@(private = "file")
csr_written :: proc(last: ^Last_Writes, writes: ^Step_Writes, address: u32, step: int) {
	add_write(writes, {kind = .Csr, index = address, previous = last.csrs[address] or_else 0})
	last.csrs[address] = step
}

// Prev: puts back what the undone step's writes replaced (newest first).
@(private)
last_writes_undo :: proc(session: ^Session, writes: Step_Writes) {
	last := &session.last_writes
	for i := writes.count - 1; i >= 0; i -= 1 {
		change := writes.changes[i]
		switch change.kind {
		case .Register:
			last.registers[change.index] = change.previous
		case .Csr:
			set_or_remove(&last.csrs, change.index, change.previous)
		case .Device_Register:
			set_or_remove(&last.device_registers, change.name, change.previous)
		}
	}
}

@(private)
set_or_remove :: proc(table: ^map[$K]int, key: K, step: int) {
	if step == 0 {
		delete_key(table, key)
	} else {
		table[key] = step
	}
}

@(private)
last_writes_clear :: proc(last: ^Last_Writes) {
	last.registers = {}
	clear(&last.csrs)
	clear(&last.device_registers)
}

@(private)
last_writes_destroy :: proc(last: ^Last_Writes) {
	delete(last.csrs)
	delete(last.device_registers)
}
