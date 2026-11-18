package rv_unit_tests

import "core:testing"
import rv "../core"
import devices "../devices"

// Unit tests for the UART (devices/uart.odin) and devices on the bus
// (core/bus.odin): registers, input and output, and undo.

THR :: rv.UART_BASE + 0 // also RBR when reading
LSR :: rv.UART_BASE + 5
LCR :: rv.UART_BASE + 3

// A machine with a UART and room for a few undo records.
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
	testing.expect(t, rv.machine_store(&machine, THR, 1, 'H'))
	testing.expect(t, rv.machine_store(&machine, THR, 1, 'i'))
	testing.expect_value(t, string(uart.output[:]), "Hi")
}

@(test)
lsr_says_ready_and_data_waiting :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	status, _ := rv.machine_load(&machine, LSR, 1)
	testing.expect_value(t, status, 0x60) // THRE and TEMT; no data
	devices.uart_input(uart, {'x'})
	status, _ = rv.machine_load(&machine, LSR, 1)
	testing.expect_value(t, status, 0x61) // data ready
}

@(test)
reading_rbr_takes_the_byte_but_peeking_doesnt :: proc(t: ^testing.T) {
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	devices.uart_input(uart, {'a', 'b'})
	peeked, _ := rv.machine_peek(&machine, THR, 1)
	testing.expect_value(t, peeked, 'a')
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
	rv.machine_store(&machine, LCR, 1, 0x80) // DLAB on
	rv.machine_store(&machine, THR, 1, 0x03) // divisor low, not a byte sent
	rv.machine_store(&machine, LCR, 1, 0x03) // DLAB off, 8 bits
	testing.expect_value(t, len(uart.output), 0)
	testing.expect_value(t, uart.registers.divisor_low, 3)
}

@(test)
only_byte_accesses :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	_, loaded := rv.machine_load(&machine, THR, 4)
	testing.expect(t, !loaded)
	testing.expect(t, !rv.machine_store(&machine, THR, 2, 0))
	// The debugger can still look at 4 registers at once.
	_, peeked := rv.machine_peek(&machine, rv.UART_BASE, 4)
	testing.expect(t, peeked)
}

@(test)
undo_takes_a_sent_byte_back :: proc(t: ^testing.T) {
	// sb t0, 0(s0) with s0 = UART, t0 = 'H', then step back.
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	SB_T0_0_S0 :: u32(0x0054_0023)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(SB_T0_0_S0))
	machine.cpu.pc = rv.RAM_BASE
	machine.cpu.regs[8] = rv.UART_BASE
	machine.cpu.regs[5] = 'H'

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, string(uart.output[:]), "H")
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, len(uart.output), 0) // not sent twice, not left behind
}

@(test)
undo_gives_a_read_byte_back :: proc(t: ^testing.T) {
	// lbu t1, 0(s0) reads RBR; stepping back makes it unread again.
	machine, uart := machine_with_uart()
	defer rv.machine_destroy(&machine)
	LBU_T1_0_S0 :: u32(0x0004_4303)
	rv.machine_store(&machine, rv.RAM_BASE, 4, u64(LBU_T1_0_S0))
	machine.cpu.pc = rv.RAM_BASE
	machine.cpu.regs[8] = rv.UART_BASE
	devices.uart_input(uart, {'k'})

	testing.expect(t, rv.machine_step(&machine) == nil)
	testing.expect_value(t, machine.cpu.regs[6], 'k')
	testing.expect_value(t, uart.input_read, 1)
	testing.expect(t, rv.machine_step_back(&machine))
	testing.expect_value(t, uart.input_read, 0)
	testing.expect_value(t, machine.cpu.regs[6], 0)
}

@(test)
instructions_are_not_fetched_from_a_device :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	machine.cpu.pc = rv.UART_BASE
	trap, trapped := rv.machine_step(&machine).?
	testing.expect(t, trapped)
	testing.expect_value(t, trap.cause, rv.Trap_Cause.Instruction_Access_Fault)
}

@(test)
devices_cannot_overlap :: proc(t: ^testing.T) {
	machine, _ := machine_with_uart()
	defer rv.machine_destroy(&machine)
	testing.expect(t, devices.uart_attach(&machine.bus) == nil)
}
