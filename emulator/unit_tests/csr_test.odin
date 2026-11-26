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
	// MPP = 11, and the supervisor ones SIE, SPIE, SPP); every other bit
	// reads 0.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MSTATUS)
	testing.expect_value(t, value, rv.MSTATUS_MIE | rv.MSTATUS_MPIE | rv.MSTATUS_MPP | rv.SSTATUS_MASK)
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
mip_machine_bits_ignore_writes_supervisor_bits_take_them :: proc(t: ^testing.T) {
	// mip has two kinds of bit (interrupts.odin): the machine ones are
	// wires from the devices, the supervisor ones belong to software.
	cpu: rv.Cpu
	cpu.csr.mip = rv.MIP_MTIP // as if the CLINT's alarm were ringing

	// Write all ones: the three supervisor bits (1, 5, 9) turn on; the
	// machine bits stay as the devices drive them (MSIP and MEIP stay 0).
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIP, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIP)
	testing.expect_value(t, value, rv.MIP_MTIP | rv.SUPERVISOR_INTERRUPT_BITS)

	// Write zero: the supervisor bits clear, and MTIP is still pending.
	// Software can't silence a device by writing mip; it has to tell the
	// device (for the timer: a new mtimecmp).
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIP, 0))
	value, _ = rv.csr_read(&cpu, rv.CSR_MIP)
	testing.expect_value(t, value, rv.MIP_MTIP)
}

@(test)
mie_holds_machine_and_supervisor_enables :: proc(t: ^testing.T) {
	// Write all ones: the six enable bits that exist stick, 11 9 7 5 3 1,
	// every other bit from 1 to 11: 0b1010_1010_1010.
	cpu: rv.Cpu
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIE, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIE)
	testing.expect_value(t, value, 0xaaa)
	testing.expect_value(t, value, rv.INTERRUPT_BITS)
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

@(test)
sstatus_is_a_view_of_mstatus :: proc(t: ^testing.T) {
	// sstatus is mstatus through SSTATUS_MASK (SIE, SPIE, SPP): no
	// storage of its own.
	cpu: rv.Cpu
	cpu.csr.mstatus = rv.MSTATUS_RESET | rv.MSTATUS_MIE // MPP = machine, MIE on
	machine_fields := cpu.csr.mstatus

	// Write all ones to sstatus: only the supervisor fields turn on.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SSTATUS, ~u64(0)))
	sstatus, _ := rv.csr_read(&cpu, rv.CSR_SSTATUS)
	testing.expect_value(t, sstatus, rv.SSTATUS_MASK)
	// They are mstatus's bits, and the machine fields are untouched.
	testing.expect_value(t, cpu.csr.mstatus, machine_fields | rv.SSTATUS_MASK)

	// Write 0 to sstatus: the supervisor fields go off, MIE and MPP stay.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SSTATUS, 0))
	testing.expect_value(t, cpu.csr.mstatus, machine_fields)

	// The other way round: a write to mstatus shows through sstatus.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MSTATUS, machine_fields | rv.MSTATUS_SPP))
	sstatus, _ = rv.csr_read(&cpu, rv.CSR_SSTATUS)
	testing.expect_value(t, sstatus, rv.MSTATUS_SPP)

	// sstatus is supervisor level (0x100: bits 9..8 = 01).
	testing.expect_value(t, rv.csr_level(rv.CSR_SSTATUS), 1)
}

@(test)
medeleg_holds_only_delegable_causes :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	// Write all ones: only causes 0..9 stick (the exceptions this hart
	// can raise below machine mode). Bit 11, ecall from machine mode, can
	// never be delegated: a trap never goes down a level.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MEDELEG, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MEDELEG)
	testing.expect_value(t, value, rv.MEDELEG_WRITABLE)
	testing.expect_value(t, value & (1 << 11), 0)

	// A typical kernel setup: user ecalls and illegal instructions go to
	// the kernel in supervisor mode.
	wanted := u64(1) << u64(rv.Trap_Cause.Ecall_From_U_Mode) | u64(1) << u64(rv.Trap_Cause.Illegal_Instruction)
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MEDELEG, wanted))
	value, _ = rv.csr_read(&cpu, rv.CSR_MEDELEG)
	testing.expect_value(t, value, wanted)

	// medeleg is machine level (0x302: bits 9..8 = 11): only machine mode
	// decides what supervisor mode gets.
	testing.expect_value(t, rv.csr_level(rv.CSR_MEDELEG), 3)
}

@(test)
mideleg_holds_only_supervisor_interrupts :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	// Write all ones: only bits 1, 5 and 9 stick, the supervisor
	// interrupts. Machine interrupts (3, 7, 11) can't be delegated: they
	// always go to machine mode, so their bits read 0.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIDELEG, ~u64(0)))
	value, _ := rv.csr_read(&cpu, rv.CSR_MIDELEG)
	testing.expect_value(t, value, rv.SUPERVISOR_INTERRUPT_BITS)

	// Asking for the supervisor and the machine timer: only the
	// supervisor one is kept.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_MIDELEG, rv.MIP_STIP | rv.MIP_MTIP))
	value, _ = rv.csr_read(&cpu, rv.CSR_MIDELEG)
	testing.expect_value(t, value, rv.MIP_STIP)

	// mideleg is machine level (0x303: bits 9..8 = 11), like medeleg.
	testing.expect_value(t, rv.csr_level(rv.CSR_MIDELEG), 3)
}

@(test)
sie_is_mie_through_mideleg :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	rv.csr_write(&cpu, rv.CSR_MIE, ~u64(0)) // all six enables on: 0xaaa
	rv.csr_write(&cpu, rv.CSR_MIDELEG, rv.MIP_STIP) // only the supervisor timer delegated

	// sie shows only the delegated bit: supervisor mode can't see that
	// machine mode turned its own interrupts on.
	value, _ := rv.csr_read(&cpu, rv.CSR_SIE)
	testing.expect_value(t, value, rv.MIP_STIP) // 0x020

	// Writing 0 clears only STIE: the bits that aren't delegated (all
	// the machine ones, SSIE, SEIE) stay as they were in mie.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIE, 0))
	testing.expect_value(t, cpu.csr.mie, rv.INTERRUPT_BITS &~ rv.MIP_STIP) // 0xa8a
	// Writing all ones turns only STIE back on.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIE, ~u64(0)))
	testing.expect_value(t, cpu.csr.mie, rv.INTERRUPT_BITS)

	// Nothing delegated: sie reads 0 and writes change nothing.
	rv.csr_write(&cpu, rv.CSR_MIDELEG, 0)
	value, _ = rv.csr_read(&cpu, rv.CSR_SIE)
	testing.expect_value(t, value, 0)
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIE, 0))
	testing.expect_value(t, cpu.csr.mie, rv.INTERRUPT_BITS)

	// sie is supervisor level (0x104: bits 9..8 = 01).
	testing.expect_value(t, rv.csr_level(rv.CSR_SIE), 1)
}

@(test)
sip_is_mip_through_mideleg_and_only_ssip_is_writable :: proc(t: ^testing.T) {
	cpu: rv.Cpu
	cpu.csr.mip = rv.MIP_MTIP | rv.MIP_STIP // the CLINT's alarm, and a forwarded tick
	rv.csr_write(&cpu, rv.CSR_MIDELEG, ~u64(0)) // all three supervisor interrupts: 0x222

	// sip hides the machine timer: only STIP shows.
	value, _ := rv.csr_read(&cpu, rv.CSR_SIP)
	testing.expect_value(t, value, rv.MIP_STIP)

	// Writing all ones sets only SSIP. STIP was already 1; SEIP stays 0:
	// supervisor mode can't raise or clear those through sip.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIP, ~u64(0)))
	testing.expect_value(t, cpu.csr.mip, rv.MIP_MTIP | rv.MIP_STIP | rv.MIP_SSIP)
	// Writing 0 clears only SSIP: STIP is still pending.
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIP, 0))
	testing.expect_value(t, cpu.csr.mip, rv.MIP_MTIP | rv.MIP_STIP)

	// SSIP not delegated: it isn't supervisor mode's to set.
	rv.csr_write(&cpu, rv.CSR_MIDELEG, rv.MIP_STIP)
	testing.expect(t, rv.csr_write(&cpu, rv.CSR_SIP, ~u64(0)))
	testing.expect_value(t, cpu.csr.mip, rv.MIP_MTIP | rv.MIP_STIP)

	// sip is supervisor level (0x144: bits 9..8 = 01).
	testing.expect_value(t, rv.csr_level(rv.CSR_SIP), 1)
}

@(test)
time_needs_a_clock_and_is_read_only :: proc(t: ^testing.T) {
	// A bare Cpu has no clock attached (Cpu.time_source is set by the
	// CLINT): reading time fails, as for a CSR that doesn't exist, so
	// csrr time would be an illegal instruction.
	cpu: rv.Cpu
	_, ok := rv.csr_read(&cpu, rv.CSR_TIME)
	testing.expect(t, !ok)

	// 0xc01: bits 11..10 = 11 (read-only), bits 9..8 = 00 (any mode may
	// read it). A write is refused, clock or not.
	testing.expect(t, rv.csr_is_read_only(rv.CSR_TIME))
	testing.expect_value(t, rv.csr_level(rv.CSR_TIME), 0)
	testing.expect(t, !rv.csr_write(&cpu, rv.CSR_TIME, 5))
}

@(test)
spp_helpers_read_and_write_bit_8 :: proc(t: ^testing.T) {
	// SPP is one bit (8): supervisor when set, user when clear.
	status := rv.MSTATUS_RESET // MPP = machine, SPP = 0
	testing.expect_value(t, rv.mstatus_spp(status), rv.Privilege.User)

	status = rv.mstatus_with_spp(status, .Supervisor)
	testing.expect_value(t, status, rv.MSTATUS_RESET | rv.MSTATUS_SPP) // only bit 8 changed
	testing.expect_value(t, rv.mstatus_spp(status), rv.Privilege.Supervisor)

	status = rv.mstatus_with_spp(status, .User)
	testing.expect_value(t, status, rv.MSTATUS_RESET) // and back
}

