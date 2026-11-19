package rv_unit_tests

import "core:testing"
import rv "../core"

// Unit tests for the CSR rules in core/csr.odin. Run with `make unit`
// (part of `make test`).

@(test)
read_only_machine_info_is_zero :: proc(t: ^testing.T) {
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
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MISA, 0))
	value, _ := rv.csr_read(&cpu, rv.CSR_MISA)
	testing.expect_value(t, value >> 62, 2) // MXL = 64-bit
	testing.expect_value(t, value & (1 << 8), 1 << 8) // I
	testing.expect_value(t, value & (1 << 20), 1 << 20) // U: user mode
}

@(test)
mstatus_keeps_only_implemented_fields :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, rv.MSTATUS_MIE | rv.MSTATUS_MPIE | rv.MSTATUS_MPP)
}

@(test)
mtvec_and_mepc_alignment :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	rv.csr_write(&cpu, rv.CSR_MTVEC, 0x8000_0103) // mode 3 is reserved
	mtvec, _ := rv.csr_read(&cpu, rv.CSR_MTVEC)
	testing.expect_value(t, mtvec, 0x8000_0101) // mode bit 1 cleared

	rv.csr_write(&cpu, rv.CSR_MEPC, 0x8000_0007)
	mepc, _ := rv.csr_read(&cpu, rv.CSR_MEPC)
	testing.expect_value(t, mepc, 0x8000_0004)
}

@(test)
plain_csrs_hold_any_value :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	for address in ([]u32{rv.CSR_MSCRATCH, rv.CSR_MCAUSE, rv.CSR_MTVAL}) {
		testing.expect(t, rv.csr_write(&cpu, address, 0xDEAD_BEEF_1234_5678))
		value, _ := rv.csr_read(&cpu, address)
		testing.expect_value(t, value, 0xDEAD_BEEF_1234_5678)
	}
}

@(test)
counters_read_their_own_count :: proc(t: ^testing.T) {
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
	cpu: rv.Cpu
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIP, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIP)
	testing.expect_value(t, value, 0)
}

@(test)
mstatus_mpp_holds_user_or_machine :: proc(t: ^testing.T) {
	// MPP (bits 12:11) holds the modes the hart has: user (0) and machine
	// (3). Supervisor (1) and the reserved 2 leave it as it was.
	cpu: rv.Cpu
	cpu.csr.mstatus = rv.MSTATUS_RESET
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, 0))
	value, _ := rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, 0) // user
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, rv.mstatus_with_mpp(0, .Supervisor)))
	value, _ = rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, 0) // supervisor ignored: still user
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, rv.MSTATUS_MPP))
	value, _ = rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, rv.MSTATUS_MPP) // machine
}
