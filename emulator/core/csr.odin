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

// Supervisor trap setup and handling: supervisor mode's own copies of the
// machine trap CSRs, at the same numbers with bits 9..8 = 01 instead of
// 11, so supervisor and machine mode may use them (csr_allowed). They
// hold what a trap delegated to supervisor mode records (docs: stvec).
// Nothing is delegated yet, so for now they are only storage.
CSR_STVEC :: 0x105 // supervisor trap handler address (and mode), like mtvec
CSR_SSCRATCH :: 0x140 // free for the supervisor trap handler, like mscratch
CSR_SEPC :: 0x141 // where the supervisor trap happened, like mepc
CSR_SCAUSE :: 0x142 // why, like mcause
CSR_STVAL :: 0x143 // extra information, like mtval

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

// mtvec, where traps go: the handler's address (BASE), with the mode in
// its low 2 bits. A handler is 4-byte aligned, so those bits are free.
//
//   bit:   63 ... 2 | 1 0
//   field:   BASE   | MODE   0 = direct: every trap goes to BASE
//                            1 = vectored: interrupt n goes to BASE + 4 * n
//                            (2 and 3 are reserved)
MTVEC_MODE :: u64(0b11)
MTVEC_DIRECT :: u64(0)
MTVEC_VECTORED :: u64(1)

// The handler's address, without the mode bits.
mtvec_base :: #force_inline proc(mtvec: u64) -> u64 {
	return mtvec &~ MTVEC_MODE
}

// MTVEC_DIRECT or MTVEC_VECTORED.
mtvec_mode :: #force_inline proc(mtvec: u64) -> u64 {
	return mtvec & MTVEC_MODE
}

// misa: MXL = 2 (64-bit) in bits 63:62, then one bit per extension letter
// (bit 0 = A, ..., bit 8 = I, bit 12 = M, bit 18 = S, bit 20 = U): RV64IMA,
// with supervisor and user mode. Zicsr and Zifencei have no letter.
MISA_VALUE :: u64(2) << 62 | u64(1) << ('A' - 'A') | u64(1) << ('I' - 'A') | u64(1) << ('M' - 'A') | u64(1) << ('S' - 'A') | u64(1) << ('U' - 'A')

// The CSRs that need their own storage (the read-only machine
// information CSRs are constants).
Csr_File :: struct {
	mstatus:  u64,
	mie:      u64,
	mtvec:    u64,
	mscratch: u64,
	mepc:     u64,
	mcause:   u64,
	mtval:    u64,
	mip:      u64,
	// The two counters every RISC-V hart has, for programs to measure
	// themselves with (lesson 11). Each is one counter at two CSR
	// addresses: the m... one for machine mode, read / write, and a
	// read-only copy without the m (cycle, instret) for lower modes.
	//
	// Clock cycles. One per step here: an instruction, or a trap or
	// interrupt taken into a handler (those take cycles on real hardware
	// too, but retire nothing, so minstret doesn't count them). Also the
	// base of the step clock (step_clock, cpu.odin).
	mcycle:   u64,
	// Instructions completed ("retired").
	minstret: u64,
	// Supervisor trap CSRs (after the counters, so the fields every step
	// touches keep their place).
	stvec:    u64,
	sscratch: u64,
	sepc:     u64,
	scause:   u64,
	stval:    u64,
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
		return cpu.csr.mcycle, true
	case CSR_MINSTRET, CSR_INSTRET:
		return cpu.csr.minstret, true
	case CSR_STVEC:
		return csr.stvec, true
	case CSR_SSCRATCH:
		return csr.sscratch, true
	case CSR_SEPC:
		return csr.sepc, true
	case CSR_SCAUSE:
		return csr.scause, true
	case CSR_STVAL:
		return csr.stval, true
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
		// MPP can only hold a mode the hart has (WARL): user (0),
		// supervisor (1) or machine (3). Writing 2 (reserved) leaves MPP
		// as it was.
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
		// MODE 2 and 3 are reserved, so bit 1 of MTVEC_MODE is kept at 0:
		// only MTVEC_DIRECT and MTVEC_VECTORED can be stored. BASE is
		// kept as written.
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
		// step_clock = mcycle + step_clock_offset, and the step clock must
		// go up by exactly 1 each step, even when software writes mcycle
		// (the CLINT's mtime follows it). So after this step:
		//
		//   new mcycle + new offset  =  old mcycle + old offset + 1
		//   value      + new offset  =  old mcycle + old offset + 1
		//   new offset               =  old offset + (old mcycle + 1 - value)
		//
		// The + 1 is this step's tick: cpu_step skips its mcycle += 1 on a
		// step that wrote mcycle (mcycle_written).
		cpu.step_clock_offset += cpu.csr.mcycle + 1 - value
		cpu.csr.mcycle = value
		cpu.mcycle_written = true
	case CSR_MINSTRET:
		cpu.csr.minstret = value
		cpu.minstret_written = true
	case CSR_STVEC:
		// The same layout and rule as mtvec: MODE 2 and 3 are reserved.
		csr.stvec = value & ~u64(0b10)
	case CSR_SSCRATCH:
		csr.sscratch = value
	case CSR_SEPC:
		// Instructions are 4-byte aligned (no C extension), as for mepc.
		csr.sepc = value & ~u64(0b11)
	case CSR_SCAUSE:
		csr.scause = value
	case CSR_STVAL:
		csr.stval = value
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
		cpu.step_clock_offset = step_clock(cpu) - 1 - value
		cpu.csr.mcycle = value
	case CSR_MINSTRET:
		cpu.csr.minstret = value
	case CSR_STVEC:
		csr.stvec = value
	case CSR_SSCRATCH:
		csr.sscratch = value
	case CSR_SEPC:
		csr.sepc = value
	case CSR_SCAUSE:
		csr.scause = value
	case CSR_STVAL:
		csr.stval = value
	}
}

