package rv

// Control and Status Registers (CSRs): the machine-mode set this emulator
// implements, and the rules for reading and writing them.
//
// Every CSR has a 12-bit address. Its top bits encode access rules
// (privileged spec, "CSR Address Mapping Conventions"):
//
//   bits 11:10  11 = read-only, anything else = read/write
//   bits 9:8    lowest privilege level that may access it (3 = machine)
//
// Both rules are enforced: accessing a CSR from a lower privilege level
// than its bits 9:8 allow (csr_allowed), reading or writing a CSR that
// isn't implemented, or writing a read-only one, is illegal: the CSR
// instructions (zicsr.odin) turn that into an Illegal_Instruction trap.
// All the CSRs so far are machine CSRs, except the read-only counters
// cycle and instret, so user mode can only read those two.
//
// Many CSRs are "WARL" (write any value, read legal value): fields that
// don't exist or can't hold the written value are fixed up on write.
// Each write rule below says what it keeps.

// Machine information (read-only).
CSR_MVENDORID :: 0xF11 // vendor ID: 0 = not a commercial implementation
CSR_MARCHID :: 0xF12 // architecture ID: 0 = not allocated
CSR_MIMPID :: 0xF13 // implementation version: 0
CSR_MHARTID :: 0xF14 // this hart's number: 0 (the only one)

// Machine trap setup.
CSR_MSTATUS :: 0x300 // global state: interrupt enable, previous privilege
CSR_MISA :: 0x301 // which ISA extensions this hart has
CSR_MIE :: 0x304 // which interrupts are enabled
CSR_MTVEC :: 0x305 // trap handler address (and mode)

// Machine trap handling.
CSR_MSCRATCH :: 0x340 // free for the trap handler to use
CSR_MEPC :: 0x341 // address of the instruction that trapped
CSR_MCAUSE :: 0x342 // why the trap happened (Trap_Cause, or an interrupt)
CSR_MTVAL :: 0x343 // extra trap information: bad address or instruction
CSR_MIP :: 0x344 // which interrupts are pending

// Counters. mcycle / minstret are read/write; cycle / instret are their
// read-only copies for less privileged code.
CSR_MCYCLE :: 0xB00
CSR_MINSTRET :: 0xB02
CSR_CYCLE :: 0xC00
CSR_INSTRET :: 0xC02

// mstatus, the machine status register: one 64-bit CSR made of small
// fields. The ones this hart has so far (the rest read 0; supervisor mode
// adds SIE, SPIE, SPP and others):
//
//   bit:   63 ...  13 | 12 11 | 10 9 8 | 7    | 6 5 4 | 3   | 2 1 0
//   field:    (0)     |  MPP  |  (0)   | MPIE |  (0)  | MIE |  (0)
//
//   MIE   machine interrupts on (only matters in machine mode)
//   MPIE  what MIE was before the last trap (MRET puts it back)
//   MPP   the mode the last trap came from (MRET returns to it): two
//         bits, read and written with mstatus_mpp / mstatus_with_mpp
//         (privilege.odin, which also has MSTATUS_MPP and MSTATUS_RESET)
MSTATUS_MIE :: u64(1) << 3
MSTATUS_MPIE :: u64(1) << 7

// misa: MXL = 2 (64-bit) in bits 63:62, then one bit per extension letter
// (bit 0 = A, ..., bit 8 = I, bit 12 = M, bit 20 = U): RV64IMA, with user
// mode. Zicsr and Zifencei have no letter.
MISA_VALUE :: u64(2) << 62 | u64(1) << ('A' - 'A') | u64(1) << ('I' - 'A') | u64(1) << ('M' - 'A') | u64(1) << ('U' - 'A')

// The CSRs that need their own storage. Counters live in Cpu.instret and
// Cpu.cycle, and the read-only machine information CSRs are constants.
Csr_File :: struct {
	mstatus:  u64,
	mie:      u64,
	mtvec:    u64,
	mscratch: u64,
	mepc:     u64,
	mcause:   u64,
	mtval:    u64,
	mip:      u64,
}

// True if the current privilege level may access the CSR: bits 9:8 of
// its address are the lowest level allowed (0 user, 1 supervisor,
// 3 machine).
csr_allowed :: proc(cpu: ^Cpu, address: u32) -> bool {
	return u32(cpu.privilege) >= csr_level(address)
}

// The lowest privilege level that may access the CSR (address bits 9:8):
// 0 user, 1 supervisor, 3 machine.
csr_level :: proc(address: u32) -> u32 {
	return (address >> 8) & 0b11
}

// True if the address is in a read-only range (bits 11:10 = 11).
csr_is_read_only :: proc(address: u32) -> bool {
	return (address >> 10) & 0b11 == 0b11
}

// Reads a CSR. ok = false if this emulator doesn't implement it.
csr_read :: proc(cpu: ^Cpu, address: u32) -> (value: u64, ok: bool) {
	csr := &cpu.csr
	switch address {
	case CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID:
		return 0, true
	case CSR_MSTATUS:
		return csr.mstatus, true
	case CSR_MISA:
		return MISA_VALUE, true
	case CSR_MIE:
		return csr.mie, true
	case CSR_MTVEC:
		return csr.mtvec, true
	case CSR_MSCRATCH:
		return csr.mscratch, true
	case CSR_MEPC:
		return csr.mepc, true
	case CSR_MCAUSE:
		return csr.mcause, true
	case CSR_MTVAL:
		return csr.mtval, true
	case CSR_MIP:
		return csr.mip, true
	case CSR_MCYCLE, CSR_CYCLE:
		return cpu.cycle, true
	case CSR_MINSTRET, CSR_INSTRET:
		return cpu.instret, true
	}
	return 0, false
}

// Writes a CSR, applying its WARL rule. ok = false if it doesn't exist
// or is read-only.
csr_write :: proc(cpu: ^Cpu, address: u32, value: u64) -> (ok: bool) {
	if csr_is_read_only(address) {
		return false
	}
	csr := &cpu.csr
	switch address {
	case CSR_MSTATUS:
		// MPP can only hold a mode the hart has (WARL): user (0) or
		// machine (3) so far. Writing 1 (supervisor, not here yet) or 2
		// (reserved) leaves MPP as it was.
		mpp := mstatus_mpp(value)
		if !privilege_implemented(mpp) {
			mpp = mstatus_mpp(csr.mstatus)
		}
		csr.mstatus = mstatus_with_mpp(value & (MSTATUS_MIE | MSTATUS_MPIE), mpp)
	case CSR_MISA:
		// Legal but ignored: the set of extensions can't be changed.
	case CSR_MIE:
		csr.mie = value & MACHINE_INTERRUPT_BITS // the bits that exist (interrupts.odin)
	case CSR_MTVEC:
		// Mode (bits 1:0): 0 = direct, 1 = vectored; 2 and 3 are reserved,
		// so bit 1 is kept at 0. The base must stay 4-byte aligned.
		csr.mtvec = value & ~u64(0b10)
	case CSR_MSCRATCH:
		csr.mscratch = value
	case CSR_MEPC:
		// Instructions are 4-byte aligned (no C extension).
		csr.mepc = value & ~u64(0b11)
	case CSR_MCAUSE:
		csr.mcause = value
	case CSR_MTVAL:
		csr.mtval = value
	case CSR_MIP:
		// The pending bits are wires from the devices (the CLINT's timer
		// and software interrupts; interrupts.odin): software writes are
		// ignored.
	case CSR_MCYCLE:
		// The step clock (cpu_clock = cycle + clock_offset) must not
		// jump: like any step, this one moves it on by exactly one. So the
		// offset takes up the difference between the new mcycle and the
		// one it would have counted to (cycle + 1).
		cpu.clock_offset += cpu.cycle + 1 - value
		cpu.cycle = value
		cpu.cycle_written = true
	case CSR_MINSTRET:
		cpu.instret = value
		cpu.instret_written = true
	case:
		return false
	}
	return true
}

// Puts back a value read earlier from this CSR, exactly, with no WARL
// fix-ups (used by undo, machine_step_back, before it puts the counters
// back). Read-only and unknown CSRs are ignored.
csr_restore :: proc(cpu: ^Cpu, address: u32, value: u64) {
	csr := &cpu.csr
	switch address {
	case CSR_MSTATUS:
		csr.mstatus = value
	case CSR_MIE:
		csr.mie = value
	case CSR_MTVEC:
		csr.mtvec = value
	case CSR_MSCRATCH:
		csr.mscratch = value
	case CSR_MEPC:
		csr.mepc = value
	case CSR_MCAUSE:
		csr.mcause = value
	case CSR_MTVAL:
		csr.mtval = value
	case CSR_MIP:
		csr.mip = value
	case CSR_MCYCLE:
		// Undoing a write to mcycle: the offset goes back too. The step
		// being undone moved the clock on by one, so before it the clock
		// was one less than now, with mcycle = `value`.
		cpu.clock_offset = cpu_clock(cpu) - 1 - value
		cpu.cycle = value
	case CSR_MINSTRET:
		cpu.instret = value
	}
}

