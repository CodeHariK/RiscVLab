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
// supervisor mode: it sets STIP.
//
// At each instruction boundary, a pending interrupt is taken if its bit
// is set in both mip and mie, and interrupts are on: mstatus.MIE in
// machine mode (always, from a lower privilege level). It is a trap like
// any other (privilege.odin), with mcause bit 63 set, and mepc = the
// instruction that hadn't run yet. If several are pending, external
// beats software beats timer, as in the spec.

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

// The interrupt to take before the next instruction, if any.
interrupt_to_take :: proc(cpu: ^Cpu) -> (cause: Trap_Cause, take: bool) {
	ready := cpu.csr.mip & cpu.csr.mie // pending and enabled
	if ready == 0 {
		return {}, false
	}
	// In machine mode, mstatus.MIE = 0 holds every interrupt back. A lower
	// mode can always be interrupted into machine mode.
	if cpu.privilege == .Machine && cpu.csr.mstatus & MSTATUS_MIE == 0 {
		return {}, false
	}
	switch {
	case ready & MIP_MEIP != 0:
		return .Machine_External_Interrupt, true
	case ready & MIP_MSIP != 0:
		return .Machine_Software_Interrupt, true
	case ready & MIP_MTIP != 0:
		return .Machine_Timer_Interrupt, true
	}
	return {}, false
}
