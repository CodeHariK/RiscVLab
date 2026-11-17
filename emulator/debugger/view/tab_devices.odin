package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rv "../../core"
import devices "../../devices"
import ui "../ui"
import state "../state"

// The Devices tab: the registers of each device on the bus, what their
// values mean, and which one the next instruction or the last step uses.
// Only the UART so far (devices/uart.odin); the CLINT and PLIC will add
// their own sections.
//
// The values are peeked (rv.bus_peek): looking doesn't take a received
// byte out of RBR. As in the Memory tab, the register the next
// instruction loads or stores is coloured (load: rs1 colour, store: rd
// colour), and the one the last step used has the "changed" background.
//
//   RBR  0x10000000  +0  0x00
//   nothing received (a load reads 0)
//   LSR  0x10000005  +5  0x60
//   DR=0 THRE=1 TEMT=1: ready to send, nothing received
//   ...

tab_devices :: proc(session: ^state.Session) {
	colors := ui.palette()
	uart := session.uart
	if uart == nil {
		wrapped_text("No devices on the bus.", ui.text_config(.Code_Small, colors.text_dim))
		return
	}
	wrapped_text(
		fmt.tprintf("uart at 0x%x: the serial port (NS16550A, as on QEMU). Byte registers only.", rv.UART_BASE),
		ui.text_config(.Code_Small, colors.accent),
	)

	next := state.next_memory_access(session)
	last: state.Memory_Access
	if record, has_record := session.last_step.?; has_record && record.device_changed {
		last = session.last_access // the access that step made
	}

	registers := uart.registers
	divisor := registers.lcr & devices.UART_LCR_DLAB != 0
	rows := make([dynamic]ui.Table_Row, context.temp_allocator)
	add := proc(rows: ^[dynamic]ui.Table_Row, name: string, offset: u64, writing: bool, value: string, meaning: string, next: state.Memory_Access, last: state.Memory_Access) {
		colors := ui.palette()
		address := rv.UART_BASE + offset
		color := ui.COLOR_NONE
		background := ui.COLOR_NONE
		if register_used(next, address, writing) {
			color = field_color(.Rs1) if next.kind == .Load else field_color(.Rd)
			background = colors.current_line
		}
		if register_used(last, address, writing) {
			background = colors.changed
		}
		append(rows, ui.Table_Row{
			cells = ui.cells({text = name}, {text = fmt.tprintf("0x%x", address)}, {text = fmt.tprintf("+%d", offset)}, {text = value}),
			color = color,
			background = background,
		})
		append(rows, ui.Table_Row{cells = ui.cells({text = meaning, color = colors.text_dim}), background = background, span = true})
	}

	// Offset 0: RBR (load) and THR (store), or DLL with DLAB set.
	rbr, _ := rv.bus_peek(&session.machine.bus, rv.UART_BASE, 1)
	waiting := len(uart.input) - uart.input_read
	if divisor {
		add(&rows, "DLL", 0, false, byte_hex(u64(registers.divisor_low)), "divisor latch, low byte (DLAB = 1)", next, last)
		add(&rows, "DLM", 1, false, byte_hex(u64(registers.divisor_high)), "divisor latch, high byte (DLAB = 1)", next, last)
	} else {
		received := "nothing received (a load reads 0)"
		if waiting > 0 {
			received = fmt.tprintf("next received byte: %s (%d waiting)", byte_text(rbr), waiting)
		}
		add(&rows, "RBR", 0, false, byte_hex(rbr), received, next, last)
		sent := "nothing sent yet"
		if count := len(uart.output); count > 0 {
			sent = fmt.tprintf("last sent %s; %d %s sent (Console)", byte_text(u64(uart.output[count - 1])), count, "byte" if count == 1 else "bytes")
		}
		add(&rows, "THR", 0, true, "-", sent, next, last)
		add(&rows, "IER", 1, false, byte_hex(u64(registers.ier)), interrupt_enable_text(registers.ier), next, last)
	}
	isr, _ := rv.bus_peek(&session.machine.bus, rv.UART_BASE + 2, 1)
	add(&rows, "ISR", 2, false, byte_hex(isr), fifo_text(isr), next, last)
	add(&rows, "FCR", 2, true, byte_hex(u64(registers.fcr)), "FIFO control: FIFOs on" if registers.fcr & 1 != 0 else "FIFO control: FIFOs off", next, last)
	add(&rows, "LCR", 3, false, byte_hex(u64(registers.lcr)), line_control_text(registers), next, last)
	add(&rows, "MCR", 4, false, byte_hex(u64(registers.mcr)), "modem control (no modem here)", next, last)
	lsr, _ := rv.bus_peek(&session.machine.bus, rv.UART_BASE + 5, 1)
	add(&rows, "LSR", 5, false, byte_hex(lsr), line_status_text(u8(lsr)), next, last)
	add(&rows, "MSR", 6, false, byte_hex(0), "modem status (no modem here)", next, last)
	add(&rows, "SCR", 7, false, byte_hex(u64(registers.scr)), "scratch: a byte free for software", next, last)

	ui.table(clay.ID("DeviceTable"), rows[:], tab_table())
}

// True if `access` reaches the register at `address` the same way (a
// load reads the read side, a store the write side of a shared offset).
@(private)
register_used :: proc(access: state.Memory_Access, address: u64, writing: bool) -> bool {
	if access.kind == .None || address < access.address || address >= access.address + access.size {
		return false
	}
	return (access.kind == .Store) == writing
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
