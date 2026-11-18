package rv

// Trap entry in machine mode (privileged spec, "Machine-Mode Exception
// Handling"). When an instruction raises a trap, the hart:
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

// Privilege levels, numbered as in mstatus.MPP.
Privilege :: enum u8 {
	User       = 0,
	Supervisor = 1,
	Machine    = 3,
}

MSTATUS_MPP_SHIFT :: 11

// The only mode implemented so far. mstatus.MPP can only hold modes the
// hart has (csr.odin), and MRET resets MPP to this one.
LEAST_PRIVILEGED_MODE :: Privilege.Machine

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
	csr.mstatus &~= MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP // clear all three
	if interrupts_were_enabled {
		csr.mstatus |= MSTATUS_MPIE
	}
	csr.mstatus |= u64(cpu.privilege) << MSTATUS_MPP_SHIFT

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
