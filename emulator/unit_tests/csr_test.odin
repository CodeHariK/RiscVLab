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
counters_follow_instret :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	cpu.instret = 42
	cycle, _ := rv.csr_read(&cpu, rv.CSR_CYCLE)
	testing.expect_value(t, cycle, 42)
	testing.expect(t, !rv.csr_write(&cpu, rv.CSR_INSTRET, 0), "instret is read-only")
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MINSTRET, 7))
	testing.expect_value(t, cpu.instret, 7)
}

@(test)
mip_ignores_software_writes :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIP, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIP)
	testing.expect_value(t, value, 0)
}
