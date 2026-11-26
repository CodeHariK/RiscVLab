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
CSR_MEDELEG :: 0x302 // which exceptions go to supervisor mode instead (docs: medeleg)
CSR_MIDELEG :: 0x303 // which interrupts go to supervisor mode instead (docs: mideleg)
CSR_MIE :: 0x304 // which interrupts are enabled
CSR_MTVEC :: 0x305 // trap handler address (and mode)
CSR_MCOUNTEREN :: 0x306 // which counters supervisor mode may read (docs: mcounteren scounteren)
CSR_MENVCFG :: 0x30A // what lower modes' environment has: STCE turns stimecmp on (docs: menvcfg)

// Machine trap handling.
CSR_MSCRATCH :: 0x340 // free for the trap handler to use
CSR_MEPC :: 0x341 // address of the instruction that trapped
CSR_MCAUSE :: 0x342 // why the trap happened (Trap_Cause, or an interrupt)
CSR_MTVAL :: 0x343 // extra trap information: bad address or instruction
CSR_MIP :: 0x344 // which interrupts are pending

// Supervisor status: a view of mstatus (SSTATUS_MASK below), not a
// register of its own.
CSR_SSTATUS :: 0x100 // supervisor interrupt enable and previous privilege

// Supervisor interrupt enable and pending: views of mie and mip through
// mideleg, so supervisor mode sees only the interrupts handed to it
// (docs: sie sip).
CSR_SIE :: 0x104 // mie & mideleg
CSR_SIP :: 0x144 // mip & mideleg; only SSIP is writable here

// The supervisor timer (Sstc): an alarm against time, like mtimecmp
// against mtime (docs: stimecmp).
CSR_STIMECMP :: 0x14D

// Supervisor trap setup and handling: supervisor mode's own copies of the
// machine trap CSRs, at the same numbers with bits 9..8 = 01 instead of
// 11, so supervisor and machine mode may use them (csr_allowed). They
// hold what a trap delegated to supervisor mode records (docs: stvec).
// Nothing is delegated yet, so for now they are only storage.
CSR_STVEC :: 0x105 // supervisor trap handler address (and mode), like mtvec
CSR_SCOUNTEREN :: 0x106 // which counters user mode may read, like mcounteren
CSR_SSCRATCH :: 0x140 // free for the supervisor trap handler, like mscratch
CSR_SEPC :: 0x141 // where the supervisor trap happened, like mepc
CSR_SCAUSE :: 0x142 // why, like mcause
CSR_STVAL :: 0x143 // extra information, like mtval

// Counters. mcycle / minstret are read/write; cycle / instret are their
// read-only copies for less privileged code. time is the platform's
// clock, the CLINT's mtime (Cpu.time_source), read-only: it is set by
// writing mtime. Below machine mode the three read-only names need
// mcounteren / scounteren (counter_allowed).
CSR_MCYCLE :: 0xB00
CSR_MINSTRET :: 0xB02
CSR_CYCLE :: 0xC00
CSR_TIME :: 0xC01
CSR_INSTRET :: 0xC02

// mstatus, the machine status register: one 64-bit CSR made of small
// fields. The ones this hart has so far (the rest read 0; paging adds
// SUM and MXR later):
//
//   bit:   63 .. 13 | 12 11 | 10 9 | 8   | 7    | 6 | 5    | 4 | 3   | 2 | 1   | 0
//   field:   (0)    |  MPP  | (0)  | SPP | MPIE | 0 | SPIE | 0 | MIE | 0 | SIE | 0
//
//   MIE   machine interrupts on (only matters in machine mode)
//   MPIE  what MIE was before the last trap (MRET puts it back)
//   MPP   the mode the last trap came from (MRET returns to it): two
//         bits, read and written with mstatus_mpp / mstatus_with_mpp
//         (privilege.odin, which also has MSTATUS_MPP and MSTATUS_RESET)
//   SIE, SPIE, SPP: supervisor mode's copies of MIE, MPIE and MPP, for
//         traps into supervisor mode (SRET returns with them). SPP is
//         one bit: a trap into supervisor mode can only come from user
//         (0) or supervisor (1). Nothing uses them yet: delegation and
//         SRET come next.
MSTATUS_SIE :: u64(1) << 1
MSTATUS_MIE :: u64(1) << 3
MSTATUS_SPIE :: u64(1) << 5
MSTATUS_MPIE :: u64(1) << 7
MSTATUS_SPP :: u64(1) << 8

// sstatus (0x100) is not a register of its own: it is mstatus, seen
// through this mask. Supervisor mode can't use mstatus (0x300 is machine
// only), so it reads and writes its own fields here, without seeing or
// changing the machine ones (MIE, MPIE, MPP).
SSTATUS_MASK :: MSTATUS_SIE | MSTATUS_SPIE | MSTATUS_SPP

// The interrupt-enable fields a trap saves and xRET puts back, per mode:
// the enable bit and its saved copy (MPP and SPP have their own helpers
// in privilege.odin). Not SSTATUS_MASK: that is every field sstatus
// shows, and paging will add settings to it (SUM, MXR) that a trap must
// leave alone.
MSTATUS_TRAP_FIELDS_M :: MSTATUS_MIE | MSTATUS_MPIE
MSTATUS_TRAP_FIELDS_S :: MSTATUS_SIE | MSTATUS_SPIE

// medeleg, machine exception delegation: bit n set means exception cause
// n, when it happens below machine mode, goes to supervisor mode instead
// of machine mode (a trap never goes down a level, so an exception in
// machine mode ignores it). Only the causes this hart can raise are
// writable: 0 to 9 (misaligned and access faults, illegal instruction,
// breakpoint, ecall from user and supervisor). Cause 11, ecall from
// machine mode, can never be delegated, so its bit reads 0; 10 is
// reserved. The page faults (12, 13, 15) join with paging.
MEDELEG_WRITABLE :: u64(0b11_1111_1111) // causes 0..9

// mcounteren / scounteren, counter enable: one bit per counter, at the
// counter's offset from cycle (0xc00 + n):
//
//   bit:          2    1    0
//   mcounteren:   IR   TM   CY     machine mode lets supervisor mode read
//   scounteren:   IR   TM   CY     supervisor mode lets user mode read
//                 |    |    +---- cycle
//                 |    +--------- time
//                 +-------------- instret
//
// Machine mode may always read the counters; supervisor mode needs its
// bit in mcounteren, user mode in both (counter_allowed). The other bits
// would be for the hpmcounter3..31 performance counters, which this hart
// doesn't have: they read 0. Both start at 0: nothing allowed until
// machine mode says so.
COUNTEREN_CY :: u64(1) << 0 // cycle
COUNTEREN_TM :: u64(1) << 1 // time
COUNTEREN_IR :: u64(1) << 2 // instret
COUNTEREN_WRITABLE :: COUNTEREN_CY | COUNTEREN_TM | COUNTEREN_IR

// menvcfg, machine environment configuration: switches for features of
// the modes below machine mode. Only STCE exists here; the other fields
// are for extensions this hart doesn't have (cache-block instructions,
// page-based memory types) and read 0.
//
//   STCE (bit 63): Sstc on. stimecmp may be used in supervisor mode (with
//   mcounteren.TM too: stimecmp_allowed), and it drives STIP. Off: no
//   stimecmp below machine mode, and STIP is software's, as before.
MENVCFG_STCE :: u64(1) << 63
MENVCFG_WRITABLE :: MENVCFG_STCE

// stimecmp's value at reset: all ones, the farthest time, so no alarm
// until software sets one (as for the CLINT's mtimecmp).
STIMECMP_RESET :: max(u64)

// mideleg, machine interrupt delegation: medeleg's twin for interrupts.
// Bit n set means interrupt n goes to supervisor mode instead of machine
// mode. Only the supervisor interrupts (bits 1, 5, 9) can be delegated;
// machine interrupts always go to machine mode, so their bits read 0.
MIDELEG_WRITABLE :: SUPERVISOR_INTERRUPT_BITS

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
	// Which exceptions go to supervisor mode (MEDELEG_WRITABLE above).
	medeleg:  u64,
	// Which interrupts go to supervisor mode (MIDELEG_WRITABLE above).
	mideleg:  u64,
	// Which counters lower modes may read (COUNTEREN_WRITABLE above).
	mcounteren: u64,
	scounteren: u64,
	// Sstc: its switch (MENVCFG_STCE) and the supervisor timer's alarm.
	menvcfg:    u64,
	stimecmp:   u64,
}

// True if the current privilege level may access the CSR: bits 9:8 of
// its address are the lowest level allowed (0 user, 1 supervisor,
// 3 machine). A few CSRs also need machine mode's permission: the
// counters (counter_allowed) and stimecmp (stimecmp_allowed).
csr_allowed :: proc(cpu: ^Cpu, address: u32) -> bool {
	if u32(cpu.privilege) < csr_level(address) {
		return false
	}
	switch address {
	case CSR_CYCLE, CSR_TIME, CSR_INSTRET:
		return counter_allowed(cpu, address)
	case CSR_STIMECMP:
		return stimecmp_allowed(cpu)
	}
	return true
}

// stimecmp below machine mode: Sstc must be on (menvcfg.STCE), and
// supervisor mode must be allowed to read time (mcounteren.TM): an alarm
// is no use without the clock it is set against. (User mode never gets
// here: stimecmp is a supervisor CSR.)
stimecmp_allowed :: proc(cpu: ^Cpu) -> bool {
	if cpu.privilege == .Machine {
		return true
	}
	return cpu.csr.menvcfg & MENVCFG_STCE != 0 && cpu.csr.mcounteren & COUNTEREN_TM != 0
}

// cycle, time and instret below machine mode: their bit in mcounteren
// (supervisor mode), or in both mcounteren and scounteren (user mode).
// Each mode can only pass on what it was given. True for every other CSR.
counter_allowed :: proc(cpu: ^Cpu, address: u32) -> bool {
	bit: u64
	switch address {
	case CSR_CYCLE:
		bit = COUNTEREN_CY
	case CSR_TIME:
		bit = COUNTEREN_TM
	case CSR_INSTRET:
		bit = COUNTEREN_IR
	case:
		return true
	}
	switch cpu.privilege {
	case .Supervisor:
		return cpu.csr.mcounteren & bit != 0
	case .User:
		return cpu.csr.mcounteren & cpu.csr.scounteren & bit != 0
	case .Machine:
	}
	return true
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
	case CSR_SSTATUS:
		return csr.mstatus & SSTATUS_MASK, true
	case CSR_SIE:
		return csr.mie & csr.mideleg, true
	case CSR_SIP:
		return csr.mip & csr.mideleg, true
	case CSR_MEDELEG:
		return csr.medeleg, true
	case CSR_MIDELEG:
		return csr.mideleg, true
	case CSR_MCOUNTEREN:
		return csr.mcounteren, true
	case CSR_SCOUNTEREN:
		return csr.scounteren, true
	case CSR_MENVCFG:
		return csr.menvcfg, true
	case CSR_STIMECMP:
		return csr.stimecmp, true
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
	case CSR_TIME:
		// Asks the device that keeps the clock. None: as if the CSR
		// didn't exist (Illegal_Instruction).
		if cpu.time_source.read == nil {
			return 0, false
		}
		return cpu.time_source.read(cpu.time_source.data, step_clock(cpu)), true
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
		csr.mstatus = mstatus_with_mpp(value & (MSTATUS_MIE | MSTATUS_MPIE | SSTATUS_MASK), mpp)
	case CSR_SSTATUS:
		// Only the supervisor fields change; the machine ones stay.
		csr.mstatus = (csr.mstatus &~ SSTATUS_MASK) | (value & SSTATUS_MASK)
	case CSR_SIE:
		// sstatus's rule, with mideleg as the mask: only the delegated
		// enable bits change, the rest of mie stays.
		csr.mie = (csr.mie &~ csr.mideleg) | (value & csr.mideleg)
	case CSR_SIP:
		// Only SSIP, and only if it is delegated. STIP and SEIP stand for
		// something outside the kernel (machine mode's timer, the PLIC):
		// it clears them by dealing with the source, not by writing sip.
		writable := MIP_SSIP & csr.mideleg
		csr.mip = (csr.mip &~ writable) | (value & writable)
	case CSR_MEDELEG:
		// Only causes that exist and may be delegated (WARL): bit 11
		// (ecall from machine mode) and the rest read 0.
		csr.medeleg = value & MEDELEG_WRITABLE
	case CSR_MIDELEG:
		// Only the supervisor interrupts (WARL): machine ones read 0.
		csr.mideleg = value & MIDELEG_WRITABLE
	case CSR_MCOUNTEREN:
		// Only the three counters that exist (WARL).
		csr.mcounteren = value & COUNTEREN_WRITABLE
	case CSR_SCOUNTEREN:
		csr.scounteren = value & COUNTEREN_WRITABLE
	case CSR_MENVCFG:
		// Only STCE (WARL): the other fields' extensions don't exist.
		csr.menvcfg = value & MENVCFG_WRITABLE
		cpu.interrupts_change_at = 0 // STIP may change owner: look now
	case CSR_STIMECMP:
		csr.stimecmp = value
		cpu.interrupts_change_at = 0 // STIP may rise or fall: look now
	case CSR_MISA:
		// Legal but ignored: the set of extensions can't be changed.
	case CSR_MIE:
		csr.mie = value & INTERRUPT_BITS // the bits that exist (interrupts.odin)
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
		// Two kinds of bit (interrupts.odin). The machine bits are wires
		// from the devices (the CLINT's timer and software interrupts):
		// writes leave them alone. The supervisor bits are software's:
		// they take the written value. The mirror of
		// machine_update_interrupts (machine.odin), which keeps the
		// supervisor bits and takes the machine ones (docs: mie mip).
		// With Sstc on, STIP is the supervisor timer's (interrupts.odin):
		// mip_software_bits leaves it out.
		software := mip_software_bits(cpu)
		csr.mip = (csr.mip &~ software) | (value & software)
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
	case CSR_SSTATUS:
		// The undo record holds sstatus as it was read: the supervisor
		// fields only. Put those back, and keep the machine ones.
		csr.mstatus = (csr.mstatus &~ SSTATUS_MASK) | (value & SSTATUS_MASK)
	case CSR_SIE:
		// The record holds sie as it was read: mie's delegated bits.
		// mideleg is as it was then (undo goes back in order).
		csr.mie = (csr.mie &~ csr.mideleg) | (value & csr.mideleg)
	case CSR_SIP:
		// Only SSIP can have been written through sip.
		writable := MIP_SSIP & csr.mideleg
		csr.mip = (csr.mip &~ writable) | (value & writable)
	case CSR_MEDELEG:
		csr.medeleg = value
	case CSR_MIDELEG:
		csr.mideleg = value
	case CSR_MCOUNTEREN:
		csr.mcounteren = value
	case CSR_SCOUNTEREN:
		csr.scounteren = value
	case CSR_MENVCFG:
		csr.menvcfg = value
	case CSR_STIMECMP:
		csr.stimecmp = value
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
		// Only the software bits: the machine bits follow the devices,
		// and STIP the supervisor timer when Sstc is on; they are worked
		// out again after a step back.
		software := mip_software_bits(cpu)
		csr.mip = (csr.mip &~ software) | (value & software)
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
