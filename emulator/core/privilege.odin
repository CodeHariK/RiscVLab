package rv

// Privilege levels: the three modes, and mstatus's MPP and SPP fields,
// the return slots where trap entry records the level a trap came from
// and MRET / SRET read it back.
//
// The hart is always in one mode (Cpu.privilege). It only changes on a
// trap (up: trap_entry.odin) or an MRET / SRET (down to the mode in MPP /
// SPP: trap_return.odin). What a trap is: trap.odin.

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

// mstatus.SPP, "supervisor previous privilege": bit 8 (MSTATUS_SPP,
// csr.odin), the mode the last trap into supervisor mode came from. One
// bit, not two like MPP: such a trap comes from user (0) or supervisor
// (1) mode, never from machine mode.
//
//   read:  mstatus & MSTATUS_SPP != 0 -> supervisor   mstatus_spp
//   write: set or clear bit 8                          mstatus_with_spp

// The mode in mstatus.SPP: user or supervisor.
mstatus_spp :: proc(mstatus: u64) -> Privilege {
	return .Supervisor if mstatus & MSTATUS_SPP != 0 else .User
}

// `mstatus` with SPP set to `mode`, user or supervisor (the other fields
// as they were).
mstatus_with_spp :: proc(mstatus: u64, mode: Privilege) -> u64 {
	if mode == .Supervisor {
		return mstatus | MSTATUS_SPP
	}
	return mstatus &~ MSTATUS_SPP
}

// The value mstatus has at reset: MPP = machine (the spec leaves it open;
// machine keeps an MRET with no trap before it in machine mode), and
// everything else 0.
MSTATUS_RESET :: u64(Privilege.Machine) << MSTATUS_MPP_SHIFT

// The least privileged mode the hart has: MRET resets MPP to it, so a
// stale MPP can't send a later MRET back up.
LEAST_PRIVILEGED_MODE :: Privilege.User

// The modes this hart has: all three. Only 2, the reserved code, is not
// a mode. mstatus.MPP can only hold one of these (csr_write).
privilege_implemented :: proc(privilege: Privilege) -> bool {
	return privilege == .User || privilege == .Supervisor || privilege == .Machine
}
