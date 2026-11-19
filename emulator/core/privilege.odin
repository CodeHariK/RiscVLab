package rv

// Privilege levels, and moving between them: trap entry goes up to
// machine mode, MRET comes back down (privileged spec, "Machine-Mode
// Exception Handling" and "Trap-Return Instructions"). Supervisor mode,
// SRET and delegation will join them here.
//
// The hart is always in one mode (Cpu.privilege). It only changes on a
// trap (up to machine mode) or an MRET (down to the mode in mstatus.MPP).

// ------------------------------------------------------------ levels

// Privilege levels, numbered as in mstatus.MPP (2 is reserved).
Privilege :: enum u8 {
	User       = 0,
	Supervisor = 1,
	Machine    = 3,
}

// mstatus.MPP, "machine previous privilege": bits 12:11 of mstatus, the
// mode the last trap into machine mode came from (see the mstatus layout
// in csr.odin). Two bits hold the four codes: 00 user, 01 supervisor,
// 10 reserved, 11 machine, the same numbers as Privilege.
//
//   read:  (mstatus & MSTATUS_MPP) >> 11        mstatus_mpp
//   write: clear bits 12:11, OR in mode << 11   mstatus_with_mpp
//
// Where the field sits is kept in this file: everything else uses the two
// procedures below.
@(private = "file")
MSTATUS_MPP_SHIFT :: 11
MSTATUS_MPP :: u64(0b11) << MSTATUS_MPP_SHIFT

// The mode in mstatus.MPP.
mstatus_mpp :: proc(mstatus: u64) -> Privilege {
	return Privilege((mstatus & MSTATUS_MPP) >> MSTATUS_MPP_SHIFT)
}

// `mstatus` with MPP set to `mode` (the other fields as they were).
mstatus_with_mpp :: proc(mstatus: u64, mode: Privilege) -> u64 {
	return mstatus &~ MSTATUS_MPP | u64(mode) << MSTATUS_MPP_SHIFT
}

// The value mstatus has at reset: MPP = machine (the spec leaves it open;
// machine keeps an MRET with no trap before it in machine mode), and
// everything else 0.
MSTATUS_RESET :: u64(Privilege.Machine) << MSTATUS_MPP_SHIFT

// The least privileged mode the hart has: MRET resets MPP to it, so a
// stale MPP can't send a later MRET back up.
LEAST_PRIVILEGED_MODE :: Privilege.User

// The modes this hart has: machine and user so far (supervisor comes
// next). mstatus.MPP can only hold one of these (csr_write).
privilege_implemented :: proc(privilege: Privilege) -> bool {
	return privilege == .User || privilege == .Machine
}

// ------------------------------------------------------------ trap entry
//
// When an instruction raises a trap, or an interrupt is taken, the hart:
//
//   1. mepc   = address of the instruction that trapped
//   2. mcause = why (Trap_Cause; bit 63 would mark an interrupt)
//   3. mtval  = extra information (bad address, or the instruction bits)
//   4. mstatus: MPIE = MIE, then MIE = 0 (interrupts off in the handler),
//      MPP = the privilege level it was running at
//   5. switches to machine mode and jumps to the handler at mtvec
//
// mtvec's low two bits are its mode: 0 = direct (every trap goes to the
// base address), 1 = vectored (interrupts go to base + 4 * their number;
// exceptions still go to the base).
//
// Emulator convention, not hardware: if mtvec's base address is 0, no
// handler has been set up, so the trap stops the machine instead (real
// hardware would jump to address 0). That keeps simple test programs,
// which just end with EBREAK, working. The base, not all of mtvec:
// mtvec = 1 (vectored, base 0) has no handler either.

trap_has_handler :: proc(cpu: ^Cpu) -> bool {
	return (cpu.csr.mtvec &~ 0b11) != 0
}

// Enters the trap handler: what the hardware does the moment a trap is
// taken, for exceptions and interrupts alike. The caller has already
// saved, for undo, the state this changes (see `machine_step`).
trap_enter :: proc(cpu: ^Cpu, trap: Trap) {
	csr := &cpu.csr

	// 1. Remember where, why and what, for the handler.
	//    mepc:   the instruction that trapped; for an interrupt, the one
	//            that hadn't run yet (it runs after mret).
	//    mcause: e.g. 2 = Illegal_Instruction, 0x8000000000000007 = the
	//            timer interrupt (bit 63 set: an interrupt).
	//    mtval:  the bad address or instruction bits; 0 for interrupts.
	csr.mepc = cpu.pc
	csr.mcause = u64(trap.cause)
	csr.mtval = trap.value

	// 2. Interrupts off inside the handler, keeping how they were, so mret
	//    can put it back: MPIE = the old MIE, MIE = 0, MPP = the privilege
	//    level the trap came from. With MIE = 0 no interrupt can arrive in
	//    the middle of the handler (it would overwrite mepc and mcause).
	interrupts_were_enabled := csr.mstatus & MSTATUS_MIE != 0
	csr.mstatus &~= MSTATUS_MIE | MSTATUS_MPIE // both off, then MPIE as MIE was
	if interrupts_were_enabled {
		csr.mstatus |= MSTATUS_MPIE
	}
	csr.mstatus = mstatus_with_mpp(csr.mstatus, cpu.privilege)

	// 3. Machine mode, and jump to the handler. mtvec's low 2 bits are its
	//    mode, not part of the address:
	//      0 direct:   every trap goes to the base address; one handler
	//                  reads mcause and decides.
	//      1 vectored: interrupts go to base + 4 * their number, so each
	//                  kind gets its own entry point (the timer, number 7,
	//                  to base + 28). Exceptions still go to the base.
	//    `&~ INTERRUPT_BIT` takes bit 63 off mcause to leave that number.
	cpu.privilege = .Machine
	cpu.pc = csr.mtvec &~ 0b11
	if csr.mtvec & 0b11 == 1 && trap_is_interrupt(trap.cause) {
		cpu.pc += 4 * (u64(trap.cause) &~ INTERRUPT_BIT)
	}

	// 4. Cancel any LR reservation: an SC after the handler returns must
	//    fail, since the handler may have changed the memory (rv64a.odin,
	//    lesson 18).
	reservation_set(cpu, Reservation{})
}

// The environment-call cause for the current privilege level.
ecall_cause :: proc(privilege: Privilege) -> Trap_Cause {
	switch privilege {
	case .User:
		return .Ecall_From_U_Mode
	case .Supervisor:
		return .Ecall_From_S_Mode
	case .Machine:
	}
	return .Ecall_From_M_Mode
}

// ------------------------------------------------------------ MRET
//
// MRET: return from a machine-mode trap handler. Undoes what trap entry
// did:
//
//   1. pc        = mepc (the handler usually adds 4 first, to skip the
//                  instruction that trapped, e.g. an ECALL)
//   2. privilege = mstatus.MPP (the level the trap came from)
//   3. MIE = MPIE (interrupts back to how they were), then MPIE = 1
//   4. MPP = the least-privileged mode this hart supports (user), so a
//      stale MPP can't be reused by a later MRET
//
// Only machine mode may execute MRET; anywhere else it is illegal.

ENCODING_MRET :: u32(0x3020_0073)

exec_mret :: proc(cpu: ^Cpu, instruction: u32) -> Step_Result {
	if cpu.privilege != .Machine {
		return illegal_instruction(instruction)
	}
	csr := &cpu.csr
	old_mstatus := csr.mstatus

	previous := mstatus_mpp(old_mstatus)
	new_mstatus := old_mstatus &~ MSTATUS_MIE
	if old_mstatus & MSTATUS_MPIE != 0 {
		new_mstatus |= MSTATUS_MIE
	}
	new_mstatus |= MSTATUS_MPIE
	new_mstatus = mstatus_with_mpp(new_mstatus, LEAST_PRIVILEGED_MODE)

	when DEBUG_RECORD_STEPS {
		cpu.undo.csr_changed = true
		cpu.undo.csr_address = CSR_MSTATUS
		cpu.undo.csr_old = old_mstatus
	}
	csr.mstatus = new_mstatus
	cpu.privilege = previous
	cpu.next_pc = csr.mepc
	return nil
}
