package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for the UART (devices/uart.odin) and devices on the bus
// (core/bus.odin): registers, input and output, and undo.
//
// Most tests use machine_load / machine_store: accesses from outside the
// program, the way the debugger reads memory. They go through the bus
// and the device exactly as a program's lb / sb would, but they aren't
// instructions, so nothing is recorded for undo. The two undo tests run
// a real instruction instead, because only a step makes an undo record.

// The UART's registers used here, by address. Each is one byte
// (docs: uart).
THR :: rv.UART_BASE + 0 // THR (send) when storing; RBR (receive) when loading
LSR :: rv.UART_BASE + 5 // line status: bit 0 data ready, bit 5 ready to send
LCR :: rv.UART_BASE + 3 // line control: byte format, and DLAB in bit 7

// A machine with a UART and room for a few undo records. Also returns the
// UART itself, so a test can look at `output` and give it `input`.
@(private = "file")
machine_with_uart :: proc() -> (rv.Machine, ^devices.Uart) {
	machine := rv.machine_create(64 * 1024, 16)
	uart := devices.uart_attach(&machine.bus)
	return machine, uart
}

@(test)
storing_to_thr_sends_a_byte :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// A byte stored to THR is sent at once: there is no wire here, so it
	// goes straight into `output` (what the Console tab shows).
	testing.expect(t, rv.machine_store(&machine, THR, 1, 'H'))
	testing.expect(t, rv.machine_store(&machine, THR, 1, 'i'))
	testing.expect_value(t, string(uart.output[:]), "Hi")
}

@(test)
lsr_says_ready_and_data_waiting :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// Nothing received yet: bits 5 (THRE, ready for a byte) and 6 (TEMT,
	// nothing left to send) are always 1, since sending is instant; bit 0
	// (DR, data ready) is 0.
	status, _ := rv.machine_load(&machine, LSR, 1)
	testing.expect_value(t, status, 0x60)
	// A byte arrives (as if typed): DR turns on.
	devices.uart_input(uart, {'x'})
	status, _ = rv.machine_load(&machine, LSR, 1)
	testing.expect_value(t, status, 0x61)
}

@(test)
reading_rbr_takes_the_byte_but_peeking_doesnt :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	devices.uart_input(uart, {'a', 'b'})
	// A peek (the debugger looking) shows the next byte without taking it.
	peeked, _ := rv.machine_peek(&machine, THR, 1)
	testing.expect_value(t, peeked, 'a')
	// A load (a program reading RBR) takes it: each load gets the next
	// byte, and once none are left RBR reads 0 (LSR's DR bit says so).
	first, _ := rv.machine_load(&machine, THR, 1)
	second, _ := rv.machine_load(&machine, THR, 1)
	empty, _ := rv.machine_load(&machine, THR, 1)
	testing.expect_value(t, first, 'a')
	testing.expect_value(t, second, 'b')
	testing.expect_value(t, empty, 0)
}

@(test)
dlab_switches_offsets_0_and_1_to_the_divisor :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// With DLAB (LCR bit 7) set, offset 0 is the divisor's low byte, not
	// THR: the 3 sets the baud rate and must not be sent (lesson 20).
	rv.machine_store(&machine, LCR, 1, 0x80) // DLAB on
	rv.machine_store(&machine, THR, 1, 0x03) // divisor low, not a byte sent
	rv.machine_store(&machine, LCR, 1, 0x03) // DLAB off, 8 bits
	testing.expect_value(t, len(uart.output), 0) // nothing was sent
	testing.expect_value(t, uart.registers.divisor_low, 3)
}

@(test)
only_byte_accesses :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// The UART's registers are bytes: a 4-byte load or a 2-byte store
	// fails (ok = false), which a program would see as an access fault.
	_, loaded := rv.machine_load(&machine, THR, 4)
	testing.expect(t, !loaded)
	testing.expect(t, !rv.machine_store(&machine, THR, 2, 0))
	// The debugger can still look at 4 registers at once: bus_peek falls
	// back to peeking a byte at a time.
	_, peeked := rv.machine_peek(&machine, rv.UART_BASE, 4)
	testing.expect(t, peeked)
}

@(test)
undo_takes_a_sent_byte_back :: proc(t: ^testing.T) {
	// A real instruction, so the step makes an undo record:
	// sb t0, 0(s0), with s0 = the UART and t0 = 'H'.
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	SB_T0_0_S0 :: u32(0x0054_0023)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(SB_T0_0_S0))
	machine.cpu.pc = rv.RAM_BASE
	machine.cpu.regs[8] = rv.UART_BASE // s0
	machine.cpu.regs[5] = 'H' // t0

	testing.expect(t, rv.machine_step(&machine) == nil) // the sb runs
	testing.expect_value(t, string(uart.output[:]), "H")
	// Stepping back restores the UART's saved state (uart_restore), which
	// takes the byte back off `output`: not sent twice, not left behind.
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, len(uart.output), 0)
}

@(test)
undo_gives_a_read_byte_back :: proc(t: ^testing.T) {
	// lbu t1, 0(s0) reads RBR, taking the byte; stepping back makes it
	// unread again.
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	LBU_T1_0_S0 :: u32(0x0004_4303)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(LBU_T1_0_S0))
	machine.cpu.pc = rv.RAM_BASE
	machine.cpu.regs[8] = rv.UART_BASE // s0
	devices.uart_input(uart, {'k'})

	testing.expect(t, rv.machine_step(&machine) == nil) // the lbu runs
	testing.expect_value(t, machine.cpu.regs[6], 'k') // t1
	testing.expect_value(t, uart.input_read, 1) // 'k' was taken
	// Back: the UART's read position goes back (its saved state), and t1
	// gets its old value (the register undo).
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, uart.input_read, 0)
	testing.expect_value(t, machine.cpu.regs[6], 0)
}

@(test)
instructions_are_not_fetched_from_a_device :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// Running "code" at the UART's address would read its registers, with
	// side effects (taking a received byte). bus_fetch_instruction reads
	// RAM only, so this is an Instruction_Access_Fault. No handler is set
	// (mtvec = 0), so the step returns the trap.
	machine.cpu.pc = rv.UART_BASE
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Instruction_Access_Fault)
}

@(test)
devices_cannot_overlap :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	// A second UART would claim the same addresses: bus_attach refuses
	// it, and uart_attach returns nil.
	testing.expect(t, devices.uart_attach(&machine.bus) == nil)
}
