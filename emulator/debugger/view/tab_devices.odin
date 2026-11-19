package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import devices "../../devices"
import ui "../ui"
import state "../state"

// The Devices tab: the registers of each device on the bus, what their
// values mean, and which one the next instruction or the last step uses:
// the CLINT (devices/clint.odin), then the UART (devices/uart.odin). The
// PLIC will add its own section.
//
// Every register is listed, always in the same order; those DLAB hides
// at offsets 0 and 1 get a light red background. "#4" in the first
// column: step 4 last wrote that register (state/last_writes.odin). The values are peeked
// (rv.bus_peek): looking doesn't take a received byte out of RBR. As in the Memory tab, the register the next
// instruction loads or stores is coloured (load: rs1 colour, store: rd
// colour), and the one the last step used has the "changed" background.
//
//       RBR  0x10000000  +0  0x00
//   nothing received (a load reads 0)
//   #10 LCR  0x10000003  +3  0x03
//   8 data bits, 1 stop bit, no parity; DLAB=0
//       LSR  0x10000005  +5  0x60
//   DR=0 THRE=1 TEMT=1: ready to send, nothing received
//   ...

tab_devices :: proc(session: ^state.Session) {
	colors := ui.palette()
	if session.uart == nil && session.clint == nil {
		wrapped_text("No devices on the bus.", ui.text_config(.Code_Small, colors.text_dim))
		return
	}
	next := state.next_memory_access(session)
	last: state.Memory_Access
	if record, has_record := session.last_step.?; has_record && record.device_changed {
		last = session.last_access // the access that step made
	}
	// In address order, as in the memory map.
	if session.clint != nil {
		clint_section(session, next, last)
	}
	if session.uart != nil {
		uart_section(session, next, last)
	}
}

// The CLINT: msip, mtimecmp (the alarm), mtime (the clock).
@(private)
clint_section :: proc(session: ^state.Session, next: state.Memory_Access, last: state.Memory_Access) {
	colors := ui.palette()
	clint := session.clint
	clock := rv.step_clock(&session.machine.cpu)
	wrapped_text(
		fmt.tprintf("clint at 0x%x: the timer, and software interrupts. 4- and 8-byte registers.", rv.CLINT_BASE),
		ui.text_config(.Code_Small, colors.accent),
	)
	rows := make([dynamic]ui.Table_Row, context.temp_allocator)
	mtime := devices.clint_mtime(clint, clock)

	msip := "software interrupt pending (mip.MSIP = 1)" if clint.msip & 1 != 0 else "no software interrupt (write 1 to raise one)"
	add_register(&rows, session, "clint", rv.CLINT_BASE, 4, "msip", devices.CLINT_MSIP, .Both, true,
		fmt.tprintf("0x%x", clint.msip), msip, next, last)

	alarm := "no alarm set (all ones): nothing pending"
	if clint.mtimecmp != max(u64) {
		if steps, coming := devices.clint_steps_to_alarm(clint, clock); coming {
			alarm = fmt.tprintf("the alarm: timer interrupt pending in %d %s", steps, "step" if steps == 1 else "steps")
		} else {
			alarm = "the alarm has come: timer interrupt pending (mip.MTIP = 1) until mtimecmp is moved on"
		}
	}
	add_register(&rows, session, "clint", rv.CLINT_BASE, 8, "mtimecmp", devices.CLINT_MTIMECMP, .Both, true,
		fmt.tprintf("0x%x", clint.mtimecmp), alarm, next, last)
	add_register(&rows, session, "clint", rv.CLINT_BASE, 8, "mtime", devices.CLINT_MTIME, .Both, true,
		value_text(mtime), "the clock: one tick per step (docs: emulator-time)", next, last)

	options := tab_table()
	options.min_columns = {"#99"}
	ui.table(clay.ID("ClintTable"), rows[:], options)
}

// The UART: every register, decoded.
@(private)
uart_section :: proc(session: ^state.Session, next: state.Memory_Access, last: state.Memory_Access) {
	colors := ui.palette()
	uart := session.uart
	wrapped_text(
		fmt.tprintf("uart at 0x%x: the serial port (NS16550A, as on QEMU). Byte registers only.", rv.UART_BASE),
		ui.text_config(.Code_Small, colors.accent),
	)

	registers := uart.registers
	divisor := registers.lcr & devices.UART_LCR_DLAB != 0
	rows := make([dynamic]ui.Table_Row, context.temp_allocator)

	// Every register, always in this order. Offsets 0 and 1 are two
	// registers each, picked by LCR's DLAB bit: the ones DLAB hides right
	// now get a light red background, with their values kept (IER doesn't lose its value
	// while DLAB is on), and loads and stores don't reach them.
	waiting := len(uart.input) - uart.input_read
	received := "nothing received (a load reads 0)"
	rbr: u64 = 0
	if waiting > 0 {
		rbr = u64(uart.input[uart.input_read])
		received = fmt.tprintf("next received byte: %s (%d waiting)", byte_text(rbr), waiting)
	}
	sent := "nothing sent yet"
	if count := len(uart.output); count > 0 {
		sent = fmt.tprintf("last sent %s; %d %s sent (Console)", byte_text(u64(uart.output[count - 1])), count, "byte" if count == 1 else "bytes")
	}
	hidden_by_dlab := "hidden: DLAB = 1, so offset %d is %s now"
	shown_with_dlab := "only with DLAB = 1 (LCR bit 7); offset %d is %s now"

	add_register(&rows, session, "uart", rv.UART_BASE, 1, "RBR", 0, .Load, !divisor, byte_hex(rbr),
		received if !divisor else fmt.tprintf(hidden_by_dlab, 0, "DLL"), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "THR", 0, .Store, !divisor, "-",
		sent if !divisor else fmt.tprintf(hidden_by_dlab, 0, "DLL"), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "IER", 1, .Both, !divisor, byte_hex(u64(registers.ier)),
		interrupt_enable_text(registers.ier) if !divisor else fmt.tprintf(hidden_by_dlab, 1, "DLM"), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "DLL", 0, .Both, divisor, byte_hex(u64(registers.divisor_low)),
		"divisor latch, low byte" if divisor else fmt.tprintf(shown_with_dlab, 0, "RBR / THR"), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "DLM", 1, .Both, divisor, byte_hex(u64(registers.divisor_high)),
		"divisor latch, high byte" if divisor else fmt.tprintf(shown_with_dlab, 1, "IER"), next, last)
	isr, _ := rv.machine_peek(&session.machine, rv.UART_BASE + 2, 1)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "ISR", 2, .Load, true, byte_hex(isr), fifo_text(isr), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "FCR", 2, .Store, true, byte_hex(u64(registers.fcr)),
		"FIFO control: FIFOs on" if registers.fcr & 1 != 0 else "FIFO control: FIFOs off", next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "LCR", 3, .Both, true, byte_hex(u64(registers.lcr)), line_control_text(registers), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "MCR", 4, .Both, true, byte_hex(u64(registers.mcr)), "modem control (no modem here)", next, last)
	lsr, _ := rv.machine_peek(&session.machine, rv.UART_BASE + 5, 1)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "LSR", 5, .Load, true, byte_hex(lsr), line_status_text(u8(lsr)), next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "MSR", 6, .Load, true, byte_hex(0), "modem status (no modem here)", next, last)
	add_register(&rows, session, "uart", rv.UART_BASE, 1, "SCR", 7, .Both, true, byte_hex(u64(registers.scr)), "scratch: a byte free for software", next, last)

	options := tab_table()
	options.min_columns = {"#99"} // the "#N" column keeps its width
	ui.table(clay.ID("UartTable"), rows[:], options)
}

// Which accesses reach a register: both for an ordinary read/write
// register (LCR, IER, the divisor), one side where an offset is two
// registers (offset 0: RBR for loads, THR for stores; offset 2: ISR /
// FCR) or the register is read-only (LSR, MSR).
@(private)
Register_Side :: enum {
	Both,
	Load,
	Store,
}

// One register: the step that last wrote it ("#4"), name, address,
// offset, value, and a dim line saying what the value means. `active` is
// false for a register DLAB hides: light red, and never highlighted.
@(private)
add_register :: proc(
	rows: ^[dynamic]ui.Table_Row,
	session: ^state.Session,
	device: string, // "uart": the last-written key is "uart.<name>"
	base: u64,
	size: u64, // the register's size in bytes
	name: string,
	offset: u64,
	side: Register_Side,
	active: bool,
	value: string,
	meaning: string,
	next: state.Memory_Access,
	last: state.Memory_Access,
) {
	colors := ui.palette()
	address := base + offset
	color := ui.COLOR_NONE
	// Out of reach while DLAB says otherwise: a light red background.
	background := ui.COLOR_NONE if active else colors.unreachable
	if active && register_used(next, address, size, side) {
		color = field_color(.Rs1) if next.kind == .Load else field_color(.Rd)
		background = colors.current_line
	}
	if active && register_used(last, address, size, side) {
		background = colors.changed
	}
	written := state.last_write_device_register(session, fmt.tprintf("%s.%s", device, name))
	append(rows, ui.Table_Row{
		cells = ui.cells(
			{text = step_mark(written), color = colors.text_dim},
			{text = name},
			{text = fmt.tprintf("0x%x", address)},
			{text = fmt.tprintf("+%d", offset) if offset < 10 else fmt.tprintf("+0x%x", offset)},
			{text = value},
		),
		color = color,
		background = background,
	})
	append(rows, ui.Table_Row{
		cells = ui.cells({text = meaning, color = colors.text_dim}),
		background = background,
		span = true,
		span_from = 1, // under the name, not the "#N" column
	})
}

// True if `access` reaches any byte of the register at `address` (`size`
// bytes) from `side`: a 4-byte store to the top half of mtimecmp counts.
@(private)
register_used :: proc(access: state.Memory_Access, address: u64, size: u64, side: Register_Side) -> bool {
	if access.kind == .None || address >= access.address + access.size || access.address >= address + size {
		return false
	}
	switch side {
	case .Load:
		return access.kind == .Load
	case .Store:
		return access.kind == .Store
	case .Both:
	}
	return true
}

@(private)
byte_hex :: proc(value: u64) -> string {
	return fmt.tprintf("0x%02x", value & 0xFF)
}

// IER bits 0..3: which events would interrupt (none can yet: no PLIC).
@(private)
interrupt_enable_text :: proc(ier: u8) -> string {
	if ier == 0 {
		return "interrupts: none enabled"
	}
	return fmt.tprintf(
		"interrupts on: received=%d sent=%d line=%d modem=%d (none raised yet: no PLIC)",
		ier & 1,
		(ier >> 1) & 1,
		(ier >> 2) & 1,
		(ier >> 3) & 1,
	)
}

@(private)
fifo_text :: proc(isr: u64) -> string {
	fifos := "FIFOs on" if isr & 0xC0 != 0 else "FIFOs off"
	return fmt.tprintf("interrupt status: none pending; %s", fifos)
}

// LCR: word length (bits 1:0), stop bits (bit 2), parity (bit 3), DLAB
// (bit 7); with the divisor, the baud rate (QEMU's 1.8432 MHz clock).
@(private)
line_control_text :: proc(registers: devices.Uart_Registers) -> string {
	lcr := registers.lcr
	stop := 2 if lcr & 0b100 != 0 else 1
	parity := "parity" if lcr & 0b1000 != 0 else "no parity"
	text := fmt.tprintf("%d data bits, %d stop bit%s, %s; DLAB=%d", 5 + (lcr & 0b11), stop, "s" if stop == 2 else "", parity, lcr >> 7)
	if divisor := u32(registers.divisor_high) << 8 | u32(registers.divisor_low); divisor != 0 {
		text = fmt.tprintf("%s; divisor %d = %d baud (no wire here: no effect)", text, divisor, 1_843_200 / (16 * divisor))
	}
	return text
}

@(private)
line_status_text :: proc(lsr: u8) -> string {
	received := lsr & devices.UART_LSR_DATA_READY != 0
	ready := lsr & devices.UART_LSR_THR_EMPTY != 0
	return fmt.tprintf(
		"DR=%d THRE=%d TEMT=%d: %s, %s",
		u8(received),
		u8(ready),
		u8(lsr & devices.UART_LSR_TRANSMITTER_EMPTY != 0),
		"ready to send" if ready else "busy sending",
		"a byte is waiting in RBR" if received else "nothing received",
	)
}
