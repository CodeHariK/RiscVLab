package rv

// Interrupts: devices asking for the hart's attention (docs: interrupt).
//
// Each device drives some of mip's machine bits, like wires
// (Device.interrupts): the CLINT drives MTIP (timer) and MSIP (software),
// the PLIC will drive MEIP. The machine reads them whenever they can have
// changed: after a step that loaded from or stored to a device, after a
// step back, and when the step clock reaches the time a device said they
// would change (the CLINT's alarm). So mip always shows what the devices
// say, without asking them every step. Software can't write these bits.
//
// mip's supervisor bits are the other way round: no device drives them
// (yet), machine-mode software sets and clears them with csrw mip. That
// is how a machine-mode timer handler passes a tick down to a kernel in
// supervisor mode: it sets STIP. The exception is STIP with Sstc on
// (menvcfg.STCE): then the supervisor timer drives it, 1 while
// time >= stimecmp (supervisor_timer), and software writes leave it.
//
// At each instruction boundary, a pending interrupt is taken if its bit
// is set in both mip and mie, and the mode it goes to (mideleg) allows it
// (interrupt_to_take). It is a trap like any other (privilege.odin), with
// bit 63 of mcause / scause set, and mepc / sepc = the instruction that
// hadn't run yet.

// The interrupt bits, at the same place in mie (enabled) and mip
// (pending): one per kind of interrupt and mode. Each machine bit has a
// supervisor twin two places lower (bit n = interrupt number n, the
// number mcause / scause report).
//
//   bit:   11    9     7     5     3     1
//   mie:   MEIE  SEIE  MTIE  STIE  MSIE  SSIE   software turns each on or off
//   mip:   MEIP  SEIP  MTIP  STIP  MSIP  SSIP   M: devices, S: software
//          external    timer       software
//
// An interrupt is taken when its bit is 1 in both, and interrupts are on:
// mstatus.MIE in machine mode. mstatus.MIE is a different register's bit
// (it too is bit 3, by chance): the one switch for all of them.
MIP_MSIP :: u64(1) << 3 // machine software interrupt pending (the CLINT's msip)
MIP_MTIP :: u64(1) << 7 // machine timer interrupt pending (the CLINT's alarm)
MIP_MEIP :: u64(1) << 11 // machine external interrupt pending (the PLIC, later)
MIP_SSIP :: u64(1) << 1 // supervisor software interrupt pending
MIP_STIP :: u64(1) << 5 // supervisor timer interrupt pending
MIP_SEIP :: u64(1) << 9 // supervisor external interrupt pending

// The interrupt bits mie and mip have for machine mode. Devices can only
// drive these in mip, and software can't write them there.
MACHINE_INTERRUPT_BITS :: MIP_MSIP | MIP_MTIP | MIP_MEIP
// And for supervisor mode: in mip, written by software (machine mode for
// now). They are also the interrupts mideleg can hand to supervisor mode.
SUPERVISOR_INTERRUPT_BITS :: MIP_SSIP | MIP_STIP | MIP_SEIP
// Every bit mie can hold.
INTERRUPT_BITS :: MACHINE_INTERRUPT_BITS | SUPERVISOR_INTERRUPT_BITS

// mip as the devices drive it now (`now`: the step clock, for devices
// that keep time), and the clock time at which that next changes by
// itself. Asked only when it can have changed (machine_step): it isn't
// free, and is the same for most steps.
bus_interrupt_lines :: proc(bus: ^Bus, now: u64) -> (lines: u64, changes_at: u64) {
	changes_at = max(u64)
	for device in bus.devices[:bus.device_count] {
		if device.interrupts != nil {
			device_lines, device_changes_at := device.interrupts(device.data, now)
			lines |= device_lines
			changes_at = min(changes_at, device_changes_at)
		}
	}
	return lines & MACHINE_INTERRUPT_BITS, changes_at
}

// The order interrupts are taken in when several are ready (the spec's):
// external, then software, then timer; machine before supervisor.
@(rodata)
INTERRUPT_PRIORITY := [?]Trap_Cause {
	.Machine_External_Interrupt,
	.Machine_Software_Interrupt,
	.Machine_Timer_Interrupt,
	.Supervisor_External_Interrupt,
	.Supervisor_Software_Interrupt,
	.Supervisor_Timer_Interrupt,
}

// The interrupt to take before the next instruction, if any.
//
// Each ready interrupt (pending and enabled) goes to the mode mideleg
// picks, and that mode decides whether it can be taken now:
//
//   goes to \ hart in:   user     supervisor     machine
//   machine               taken    taken          if mstatus.MIE
//   supervisor            taken    if sstatus.SIE never
//
// The same rule both times: a mode's switch (MIE, SIE) holds back its own
// interrupts only while the hart runs in that mode. A lower mode can
// always be interrupted up; a higher mode is never interrupted down (a
// delegated interrupt waits until the hart leaves machine mode).
//
// Interrupts going to machine mode come first; within each group,
// INTERRUPT_PRIORITY's order. An undelegated supervisor interrupt goes to
// machine mode, and is taken there after the machine ones.
interrupt_to_take :: proc(cpu: ^Cpu) -> (cause: Trap_Cause, take: bool) {
	ready := cpu.csr.mip & cpu.csr.mie // pending and enabled
	if ready == 0 {
		return {}, false
	}
	to_machine := ready &~ cpu.csr.mideleg
	to_supervisor := ready & cpu.csr.mideleg
	if !interrupts_allowed(cpu, .Machine) {
		to_machine = 0
	}
	if !interrupts_allowed(cpu, .Supervisor) {
		to_supervisor = 0
	}
	for group in ([2]u64{to_machine, to_supervisor}) {
		for candidate in INTERRUPT_PRIORITY {
			if group & (u64(1) << trap_cause_number(candidate)) != 0 {
				return candidate, true
			}
		}
	}
	return {}, false
}

// True if an interrupt going to `target` may be taken now (the table
// above): always from a lower mode, never from a higher one, and in
// `target` itself only if its switch is on.
@(private = "file")
interrupts_allowed :: proc(cpu: ^Cpu, target: Privilege) -> bool {
	current := u32(cpu.privilege)
	switch {
	case current < u32(target):
		return true
	case current > u32(target):
		return false
	case target == .Machine:
		return cpu.csr.mstatus & MSTATUS_MIE != 0
	case:
		return cpu.csr.mstatus & MSTATUS_SIE != 0
	}
}

// The mip bits software writes (csrw mip; undo restores them): the
// supervisor ones, except STIP while Sstc is on (the supervisor timer
// drives it then).
mip_software_bits :: proc(cpu: ^Cpu) -> u64 {
	if cpu.csr.menvcfg & MENVCFG_STCE != 0 {
		return SUPERVISOR_INTERRUPT_BITS &~ MIP_STIP
	}
	return SUPERVISOR_INTERRUPT_BITS
}

// The supervisor timer (Sstc), as the CLINT's alarm is for MTIP: while
// menvcfg.STCE is on, STIP is a wire, 1 while time >= stimecmp.
//
//   drives:     Sstc is on, so STIP is the timer's (not software's)
//   pending:    STIP now
//   changes_at: the step clock time at which STIP next changes by itself
//               (the alarm time comes), or max(u64): it only falls when
//               software writes a later stimecmp (or moves mtime back),
//               and machine_step looks again after those.
//
// With no clock attached (no CLINT), time never reaches anything: STIP
// stays 0.
supervisor_timer :: proc(cpu: ^Cpu, now: u64) -> (drives: bool, pending: bool, changes_at: u64) {
	changes_at = max(u64)
	if cpu.csr.menvcfg & MENVCFG_STCE == 0 {
		return false, false, changes_at
	}
	source := cpu.time_source
	if source.read == nil {
		return true, false, changes_at
	}
	time := source.read(source.data, now)
	alarm := cpu.csr.stimecmp
	if time >= alarm {
		return true, true, changes_at
	}
	// Rounded up: the first step at which time has reached the alarm.
	ticks := alarm - time
	steps := ticks / source.ticks_per_step
	if ticks % source.ticks_per_step != 0 {
		steps += 1
	}
	if steps <= max(u64) - now { // else: so far off it never comes
		changes_at = now + steps
	}
	return true, false, changes_at
}
