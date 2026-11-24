package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the CSR rules in core/csr.odin. Run with `make unit`
// (part of `make test`).
//
// These call csr_read / csr_write directly on a bare Cpu: no machine, no
// instruction, no privilege check. They test what each CSR keeps and
// returns (its WARL rule). zicsr_test.odin tests the instructions, and
// who may use them. csr_write returns false for a CSR that doesn't exist
// or is read-only (the instruction turns that into Illegal_Instruction).

@(test)
read_only_machine_info_is_zero :: proc(t: ^testing.T) {
	// The ID CSRs (0xf11..0xf14): bits 11..10 = 11, read-only. 0 means
	// "not a commercial chip", and hart 0 is the only hart.
	cpu: rv.Cpu
	for address in ([]u32{rv.CSR_MVENDORID, rv.CSR_MARCHID, rv.CSR_MIMPID, rv.CSR_MHARTID}) {
		value, ok := rv.csr_read(&cpu, address)
		testing.expect(t, ok)
		testing.expect_value(t, value, 0)
		testing.expect(t, !rv.csr_write(&cpu, address, 1), "read-only CSR accepted a write")
	}
}

@(test)
unknown_csr_is_rejected :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	_, ok := rv.csr_read(&cpu, 0x7C0) // a custom CSR this emulator doesn't have
	testing.expect(t, !ok)
	testing.expect(t, !rv.csr_write(&cpu, 0x7C0, 1))
}

@(test)
misa_reports_rv64i_and_ignores_writes :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	// misa is writable (the write is accepted), but this hart can't turn
	// extensions off, so writing 0 changes nothing.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MISA, 0))
	value, _ := rv.csr_read(&cpu, rv.CSR_MISA)
	// One bit per extension letter: bit ('X' - 'A').
	testing.expect_value(t, value >> 62, 2) // MXL = 64-bit
	testing.expect_value(t, value & (1 << 8), 1 << 8) // I
	testing.expect_value(t, value & (1 << 18), 1 << 18) // S: supervisor mode
	testing.expect_value(t, value & (1 << 20), 1 << 20) // U: user mode
}

@(test)
mstatus_keeps_only_implemented_fields :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	// Write all ones: only the fields this hart has stick (MIE, MPIE,
	// MPP = 11); every other bit reads 0.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, rv.MSTATUS_MIE | rv.MSTATUS_MPIE | rv.MSTATUS_MPP)
}

@(test)
mtvec_and_mepc_alignment :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	// mtvec's low 2 bits are MODE; 2 and 3 are reserved, so bit 1 is
	// forced to 0: only direct (0) or vectored (1) can be stored.
	rv.csr_write(&cpu, rv.CSR_MTVEC, 0x8000_0103) // mode 3 is reserved
	mtvec, _ := rv.csr_read(&cpu, rv.CSR_MTVEC)
	testing.expect_value(t, mtvec, 0x8000_0101) // mode bit 1 cleared

	// mepc holds an instruction address, and instructions are 4-byte
	// aligned here (no C extension), so its low 2 bits are cleared.
	rv.csr_write(&cpu, rv.CSR_MEPC, 0x8000_0007)
	mepc, _ := rv.csr_read(&cpu, rv.CSR_MEPC)
	testing.expect_value(t, mepc, 0x8000_0004)
}

@(test)
plain_csrs_hold_any_value :: proc(t: ^testing.T) {
	// These keep every bit written: no fields, no rules.
	cpu: rv.Cpu
	for address in ([]u32{rv.CSR_MSCRATCH, rv.CSR_MCAUSE, rv.CSR_MTVAL}) {
		testing.expect(t, rv.csr_write(&cpu, address, 0xDEAD_BEEF_1234_5678))
		value, _ := rv.csr_read(&cpu, address)
		testing.expect_value(t, value, 0xDEAD_BEEF_1234_5678)
	}
}

@(test)
counters_read_their_own_count :: proc(t: ^testing.T) {
	// instret and cycle (0xc02, 0xc00) are the read-only user names of
	// minstret and mcycle: the same counters, not copies.
	cpu: rv.Cpu
	cpu.csr.minstret = 42
	cpu.csr.mcycle = 40
	instret, _ := rv.csr_read(&cpu, rv.CSR_INSTRET)
	cycle, _ := rv.csr_read(&cpu, rv.CSR_CYCLE)
	testing.expect_value(t, instret, 42)
	testing.expect_value(t, cycle, 40)
	testing.expect(t, !rv.csr_write(&cpu, rv.CSR_INSTRET, 0), "instret is read-only")
	testing.expect(t, !rv.csr_write(&cpu, rv.CSR_CYCLE, 0), "cycle is read-only")
}

@(test)
writing_one_counter_leaves_the_other :: proc(t: ^testing.T) {
	// The two counters are separate: a write changes only the one named.
	cpu: rv.Cpu
	cpu.csr.minstret = 42
	cpu.csr.mcycle = 42
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MINSTRET, 7))
	testing.expect_value(t, cpu.csr.minstret, 7)
	testing.expect_value(t, cpu.csr.mcycle, 42)
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MCYCLE, 9))
	testing.expect_value(t, cpu.csr.mcycle, 9)
	testing.expect_value(t, cpu.csr.minstret, 7)
}

@(test)
mip_ignores_software_writes :: proc(t: ^testing.T) {
	// mip's bits are wires from the devices (interrupts.odin): a write is
	// accepted but changes nothing.
	cpu: rv.Cpu
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIP, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIP)
	testing.expect_value(t, value, 0)
}

@(test)
mstatus_mpp_holds_the_three_modes :: proc(t: ^testing.T) {
	// MPP (bits 12:11) holds the modes the hart has: user (0), supervisor
	// (1) and machine (3). The reserved 2 leaves it as it was.
	// csr_write / csr_read directly: no instruction, so no privilege
	// check, only csr_write's WARL rule. Each expect(csr_write(...))
	// checks the write was accepted (mstatus exists and is writable).
	cpu: rv.Cpu
	cpu.csr.mstatus = rv.MSTATUS_RESET // MPP = 11, machine

	// 00, user: a mode the hart has, so it is kept.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, 0))
	value, _ := rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, 0) // user

	// 01, supervisor: kept too, now that supervisor mode exists.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, rv.mstatus_with_mpp(0, .Supervisor)))
	value, _ = rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, rv.mstatus_mpp(value), rv.Privilege.Supervisor)

	// 10, reserved: not a mode, so MPP keeps its old value. The old
	// value is supervisor, not the reset value, so reading supervisor
	// back proves the write was ignored rather than turned into 0.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, u64(0b10) << 11))
	value, _ = rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, rv.mstatus_mpp(value), rv.Privilege.Supervisor) // unchanged

	// 11, machine: kept. Only MPP was set, so the whole value must be
	// exactly 0x1800.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, rv.MSTATUS_MPP))
	value, _ = rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, rv.MSTATUS_MPP) // machine
}

@(test)
supervisor_trap_csrs_follow_the_machine_rules :: proc(t: ^testing.T) {
	// Supervisor mode's trap CSRs copy the machine ones' rules.
	cpu: rv.Cpu

	// stvec, like mtvec: MODE 3 is reserved, so bit 1 is cleared.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_STVEC, 0x8000_0103))
	stvec, _ := rv.csr_read(&cpu, rv.CSR_STVEC)
	testing.expect_value(t, stvec, 0x8000_0101)

	// sepc, like mepc: instructions are 4-byte aligned.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SEPC, 0x8000_0007))
	sepc, _ := rv.csr_read(&cpu, rv.CSR_SEPC)
	testing.expect_value(t, sepc, 0x8000_0004)

	// sscratch, scause, stval keep every bit.
	for address in ([]u32{rv.CSR_SSCRATCH, rv.CSR_SCAUSE, rv.CSR_STVAL}) {
		testing.expect(t, rv.csr_write(&cpu, address, 0xDEAD_BEEF_1234_5678))
		value, _ := rv.csr_read(&cpu, address)
		testing.expect_value(t, value, 0xDEAD_BEEF_1234_5678)
	}

	// Each one's own field, not the machine twin's: mscratch stays 0.
	testing.expect_value(t, cpu.csr.mscratch, 0)

	// All five are supervisor level: bits 9..8 of the number = 01.
	for address in ([]u32{rv.CSR_STVEC, rv.CSR_SSCRATCH, rv.CSR_SEPC, rv.CSR_SCAUSE, rv.CSR_STVAL}) {
		testing.expect_value(t, rv.csr_level(address), 1)
	}
}

