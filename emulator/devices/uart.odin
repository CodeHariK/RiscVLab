package devices

import "core:mem"
import rv "../core"

// The UART: the serial port a program prints through, and later reads
// the keyboard through (xv6's console). The same chip QEMU's `virt` board
// has, an NS16550A, at the same address (rv.UART_BASE), so programs
// written for QEMU print here too.
//
// It is driven entirely by byte loads and stores to its registers
// ("memory-mapped I/O"); there are no special instructions:
//
//   offset  read                         write
//   0       RBR: next received byte      THR: send a byte
//   1       IER: interrupt enable        IER
//   2       ISR: interrupt status        FCR: FIFO control
//   3       LCR: line control            LCR
//   4       MCR: modem control           MCR
//   5       LSR: line status             (ignored)
//   6       MSR: modem status            (ignored)
//   7       SCR: scratch                 SCR
//
// With LCR bit 7 (DLAB) set, offsets 0 and 1 are the divisor latch (the
// baud rate) instead: drivers set it up first. There is no real wire, so
// the baud rate changes nothing.
//
// To print, a program waits until LSR bit 5 (THRE, "transmit holding
// register empty") is 1, then stores the byte to THR. Here sending is
// instant, so THRE is always 1, and the byte goes to `output` (the
// debugger's Console tab, the command-line runner's stdout). Received
// bytes come from `input` (uart_input); LSR bit 0 (DR, "data ready") says
// one is waiting.
//
// Only byte accesses are allowed, as on the real chip's 8-bit bus: a
// wider load or store raises an access fault. Offsets 8..0xff read as 0
// and ignore writes. Interrupts (IER) are stored but never raised: they
// arrive with the PLIC.

UART_LSR_DATA_READY :: u8(1 << 0)
UART_LSR_THR_EMPTY :: u8(1 << 5) // THRE: ready for the next byte
UART_LSR_TRANSMITTER_EMPTY :: u8(1 << 6) // TEMT: nothing left to send
UART_LCR_DLAB :: u8(1 << 7) // offsets 0 and 1 are the divisor latch
UART_FCR_CLEAR_RECEIVE :: u8(1 << 1)

Uart :: struct {
	registers:  Uart_Registers,
	// Every byte sent so far (THR writes), oldest first.
	output:     [dynamic]u8,
	// Bytes typed for the program; the next one to read is input[input_read].
	input:      [dynamic]u8,
	input_read: int,
}

// The registers that hold a value (the rest are worked out on reading).
Uart_Registers :: struct {
	ier, fcr, lcr, mcr, scr: u8,
	divisor_low, divisor_high: u8,
}

// What undo needs to put the UART back: the registers, how much had been
// sent (undoing a THR write takes its byte back off `output`) and read.
@(private = "file")
Uart_Saved :: struct {
	registers:     Uart_Registers,
	output_length: u32,
	input_read:    u32,
}
#assert(size_of(Uart_Saved) <= rv.DEVICE_STATE_SIZE)

// Creates a UART at rv.UART_BASE and attaches it to the bus, which frees
// it in bus_destroy. The pointer is for reading `output` and calling
// uart_input; nil if the bus has no room or the range is taken.
uart_attach :: proc(bus: ^rv.Bus) -> ^Uart {
	uart := new(Uart)
	device := rv.Device {
		name    = "uart",
		base    = rv.UART_BASE,
		size    = rv.UART_SIZE,
		data    = uart,
		load    = uart_load,
		peek    = uart_peek,
		store   = uart_store,
		save    = uart_save,
		restore = uart_restore,
		destroy = uart_destroy,
	}
	if !rv.bus_attach(bus, device) {
		uart_destroy(uart)
		return nil
	}
	return uart
}

// Bytes for the program to read, e.g. keys typed in a console.
uart_input :: proc(uart: ^Uart, bytes: []u8) {
	append(&uart.input, ..bytes)
}

// The name of the register at `offset`, as a load (`writing` = false) or
// store would see it, for the debugger: "THR", "LSR", "DLL", ...
uart_register_name :: proc(uart: ^Uart, offset: u64, writing: bool) -> string {
	divisor := uart.registers.lcr & UART_LCR_DLAB != 0
	switch offset {
	case 0:
		if divisor {
			return "DLL"
		}
		return "THR" if writing else "RBR"
	case 1:
		return "DLM" if divisor else "IER"
	case 2:
		return "FCR" if writing else "ISR"
	case 3:
		return "LCR"
	case 4:
		return "MCR"
	case 5:
		return "LSR"
	case 6:
		return "MSR"
	case 7:
		return "SCR"
	}
	return ""
}

// A program's load: what peek shows, and reading RBR also takes the byte.
@(private = "file")
uart_load :: proc(data: rawptr, offset: u64, size: u64, now: u64) -> (value: u64, ok: bool) {
	uart := (^Uart)(data)
	value = uart_peek(data, offset, size, now) or_return
	// Reading RBR takes the byte: the next read gets the one after it.
	if offset == 0 && uart.registers.lcr & UART_LCR_DLAB == 0 && uart.input_read < len(uart.input) {
		uart.input_read += 1
	}
	return value, true
}

// What a load of the register at `offset` would return, without the
// load's side effect (taking a received byte). Bytes only.
@(private = "file")
uart_peek :: proc(data: rawptr, offset: u64, size: u64, _: u64) -> (value: u64, ok: bool) {
	if size != 1 {
		return 0, false
	}
	uart := (^Uart)(data)
	registers := &uart.registers
	divisor := registers.lcr & UART_LCR_DLAB != 0
	switch offset {
	case 0:
		// DLAB set: the divisor's low byte. Otherwise RBR: the next byte
		// received, or 0 if nothing is waiting (LSR bit 0 says which).
		if divisor {
			return u64(registers.divisor_low), true
		}
		if uart.input_read < len(uart.input) {
			return u64(uart.input[uart.input_read]), true
		}
		return 0, true
	case 1:
		// DLAB set: the divisor's high byte. Otherwise IER.
		return u64(registers.divisor_high if divisor else registers.ier), true
	case 2:
		// ISR, the interrupt status (FCR is write-only at this offset).
		// Bit 0 = 1 means "no interrupt pending": this UART never raises
		// one yet. Bits 7:6 = 11 once FIFOs are on (FCR bit 0), which is
		// how a driver tells a 16550 from the older, FIFO-less 16450.
		fifos: u8 = 0xC0 if registers.fcr & 1 != 0 else 0
		return u64(0x01 | fifos), true
	case 3:
		return u64(registers.lcr), true // byte format, and DLAB in bit 7
	case 4:
		return u64(registers.mcr), true // modem lines: stored, no effect
	case 5:
		// LSR, the line status. Sending is instant here, so THR is always
		// empty (bit 5, THRE) and nothing is being sent (bit 6, TEMT).
		// Bit 0 (DR) when a received byte is waiting in RBR.
		status := UART_LSR_THR_EMPTY | UART_LSR_TRANSMITTER_EMPTY
		if uart.input_read < len(uart.input) {
			status |= UART_LSR_DATA_READY
		}
		return u64(status), true
	case 7:
		return u64(registers.scr), true // scratch: holds whatever was written
	}
	return 0, true // MSR (no modem lines) and the unused offsets
}

// A program's store to the register at `offset`. Bytes only.
@(private = "file")
uart_store :: proc(data: rawptr, offset: u64, size: u64, value: u64, _: u64) -> (ok: bool) {
	if size != 1 {
		return false
	}
	uart := (^Uart)(data)
	registers := &uart.registers
	byte_value := u8(value)
	divisor := registers.lcr & UART_LCR_DLAB != 0
	switch offset {
	case 0:
		// DLAB set: the divisor's low byte. Otherwise THR: send the byte,
		// which lands in `output` at once (no wire to wait for).
		if divisor {
			registers.divisor_low = byte_value
		} else {
			append(&uart.output, byte_value)
		}
	case 1:
		// DLAB set: the divisor's high byte. Otherwise IER: only its low
		// 4 bits exist (received data, transmitter empty, line status,
		// modem status interrupts).
		if divisor {
			registers.divisor_high = byte_value
		} else {
			registers.ier = byte_value & 0x0F
		}
	case 2:
		// FCR: bit 0 turns the FIFOs on (ISR shows it); bit 1 empties the
		// receive FIFO. (Bit 2, clearing the transmit FIFO, has nothing to
		// clear: sending is instant.)
		registers.fcr = byte_value
		if byte_value & UART_FCR_CLEAR_RECEIVE != 0 {
			uart.input_read = len(uart.input) // drop what wasn't read
		}
	case 3:
		registers.lcr = byte_value
	case 4:
		registers.mcr = byte_value
	case 7:
		registers.scr = byte_value
	}
	return true // LSR, MSR and the unused offsets ignore writes
}

@(private = "file")
uart_save :: proc(data: rawptr) -> rv.Device_State {
	uart := (^Uart)(data)
	saved := Uart_Saved {
		registers     = uart.registers,
		output_length = u32(len(uart.output)),
		input_read    = u32(uart.input_read),
	}
	state: rv.Device_State
	mem.copy(&state, &saved, size_of(saved))
	return state
}

@(private = "file")
uart_restore :: proc(data: rawptr, state: rv.Device_State) {
	uart := (^Uart)(data)
	saved: Uart_Saved
	state := state
	mem.copy(&saved, &state, size_of(saved))
	uart.registers = saved.registers
	resize(&uart.output, int(saved.output_length))
	uart.input_read = int(saved.input_read)
}

@(private = "file")
uart_destroy :: proc(data: rawptr) {
	uart := (^Uart)(data)
	delete(uart.output)
	delete(uart.input)
	free(uart)
}
