package devices

import "core:mem"
import rv "../core"

// The CLINT: the timer, and software interrupts between harts (docs:
// clint, timebase, emulator-time). The same layout as QEMU's `virt`
// board, at rv.CLINT_BASE, for one hart:
//
//   offset  register   size  what it does
//   0x0000  msip       4     bit 0 = 1: a software interrupt is pending (mip.MSIP)
//   0x4000  mtimecmp   8     the alarm: while mtime >= mtimecmp, mip.MTIP = 1
//   0xbff8  mtime      8     the clock
//
// 4-byte and 8-byte accesses are allowed (mtimecmp and mtime can also be
// accessed as two 4-byte halves, as 32-bit code does); anything else
// faults. Other offsets read as 0 and ignore writes.
//
// Time is counted in steps, not real time: mtime is worked out from the
// step clock (rv.cpu_clock, one tick per step, which no program can
// write), mtime = clock * CLINT_TICKS_PER_STEP + offset, so it needs no
// work per step and undo comes for free (the clock is already put back
// on every step back). `offset` is what writing mtime changes. A timer
// interrupt therefore arrives at the same instruction on every run.
// (mcycle counts the same steps, but a program can write it, and on real
// hardware that doesn't move the timer: rv.cpu_clock says how the two
// are kept apart.)
//
// mtimecmp starts as all ones: no alarm, nothing pending, until software
// sets one.

CLINT_MSIP :: u64(0x0000)
CLINT_MTIMECMP :: u64(0x4000)
CLINT_MTIME :: u64(0xbff8)
CLINT_TICKS_PER_STEP :: u64(1)

// All of the CLINT's state, saved whole for undo (clint_save): it must
// fit in a Device_State. A field that shouldn't be saved would need a
// struct of its own for the saved part, as the UART has.
Clint :: struct {
	msip:     u32,
	mtimecmp: u64,
	offset:   u64, // mtime = clock * CLINT_TICKS_PER_STEP + offset
}
#assert(size_of(Clint) <= rv.DEVICE_STATE_SIZE)

// Creates the CLINT and attaches it to the bus (which frees it in
// bus_destroy). Its clock is the step clock, which the bus hands to
// every access (`now`). nil if the bus has no room.
clint_attach :: proc(bus: ^rv.Bus) -> ^Clint {
	clint := new(Clint)
	clint.mtimecmp = max(u64)
	device := rv.Device {
		name       = "clint",
		base       = rv.CLINT_BASE,
		size       = rv.CLINT_SIZE,
		data       = clint,
		load       = clint_peek, // reading changes nothing
		peek       = clint_peek,
		store      = clint_store,
		interrupts = clint_interrupts,
		save       = clint_save,
		restore    = clint_restore,
		destroy    = clint_destroy,
	}
	if !rv.bus_attach(bus, device) {
		free(clint)
		return nil
	}
	return clint
}

// mtime when the step clock reads `now`. Wraps around past max(u64), as
// a real 64-bit counter would.
clint_mtime :: proc(clint: ^Clint, now: u64) -> u64 {
	return now * CLINT_TICKS_PER_STEP + clint.offset
}

// How many more steps until the timer interrupt is pending, or false if
// no alarm is set (or it already is pending).
clint_steps_to_alarm :: proc(clint: ^Clint, now: u64) -> (steps: u64, ok: bool) {
	mtime := clint_mtime(clint, now)
	alarm := clint.mtimecmp
	if alarm == max(u64) || mtime >= alarm {
		return 0, false
	}
	// Rounded up: the first step at which mtime has reached the alarm.
	// (Not `(ticks + TICKS - 1) / TICKS`, which could overflow.)
	ticks := alarm - mtime
	steps = ticks / CLINT_TICKS_PER_STEP
	if ticks % CLINT_TICKS_PER_STEP != 0 {
		steps += 1
	}
	return steps, true
}

// The register at `offset` as a 64-bit value and where it starts, so a
// 4-byte access can reach either half of an 8-byte register.
@(private = "file")
clint_register :: proc(clint: ^Clint, offset: u64, now: u64) -> (value: u64, start: u64, size: u64, ok: bool) {
	switch {
	case offset >= CLINT_MSIP && offset < CLINT_MSIP + 4:
		return u64(clint.msip), CLINT_MSIP, 4, true
	case offset >= CLINT_MTIMECMP && offset < CLINT_MTIMECMP + 8:
		return clint.mtimecmp, CLINT_MTIMECMP, 8, true
	case offset >= CLINT_MTIME && offset < CLINT_MTIME + 8:
		return clint_mtime(clint, now), CLINT_MTIME, 8, true
	}
	return 0, 0, 0, false
}

// A load (or peek: reading changes nothing) of `size` bytes at `offset`.
// A 4-byte access to an 8-byte register reads one half of it. For example
// a 4-byte load at 0x4004, the high half of mtimecmp:
//
//   start = 0x4000, register_size = 8, offset - start = 4
//   4 + 4 <= 8 (fits) and 4 % 4 = 0 (aligned)
//   shift = 4 * 8 = 32: value = mtimecmp >> 32, then the low 32 bits
@(private = "file")
clint_peek :: proc(data: rawptr, offset: u64, size: u64, now: u64) -> (value: u64, ok: bool) {
	if size != 4 && size != 8 {
		return 0, false
	}
	clint := (^Clint)(data)
	register, start, register_size, found := clint_register(clint, offset, now)
	if !found {
		return 0, true // the space between the registers reads as 0
	}
	// Where the access starts inside the register, in bits.
	shift := (offset - start) * 8
	if offset - start + size > register_size || (offset - start) % size != 0 {
		return 0, false // past the register's end, or misaligned
	}
	value = register >> shift
	if size == 4 {
		value &= 0xffff_ffff
	}
	return value, true
}

// A store of `size` bytes at `offset`. A 4-byte store to an 8-byte
// register replaces one half and keeps the other, as 32-bit code sets
// mtimecmp. For example a 4-byte store of 0x1234 at 0x4004:
//
//   shift   = 32
//   mask    = 0xffffffff_00000000              the bytes being written
//   updated = (mtimecmp &~ mask) | (0x1234 << 32)
//           = new high half, old low half
@(private = "file")
clint_store :: proc(data: rawptr, offset: u64, size: u64, value: u64, now: u64) -> (ok: bool) {
	if size != 4 && size != 8 {
		return false
	}
	clint := (^Clint)(data)
	register, start, register_size, found := clint_register(clint, offset, now)
	if !found {
		return true // the space between the registers ignores writes
	}
	if offset - start + size > register_size || (offset - start) % size != 0 {
		return false // past the register's end, or misaligned
	}
	// Replace the bytes written, keep the rest of the register.
	shift := (offset - start) * 8
	mask := max(u64) if size == 8 else u64(0xffff_ffff) << shift
	updated := (register &~ mask) | ((value << shift) & mask)
	switch start {
	case CLINT_MSIP:
		clint.msip = u32(updated) & 1 // only bit 0 exists
	case CLINT_MTIMECMP:
		clint.mtimecmp = updated
	case CLINT_MTIME:
		// Setting the clock: mtime = now * TICKS + offset, so choose the
		// offset that makes it read `updated` now; it keeps counting from
		// there. (A negative offset just wraps round, which works out.)
		clint.offset = updated - now * CLINT_TICKS_PER_STEP
	}
	return true
}

// The wires into the hart's mip: MTIP while the alarm time has come, MSIP
// while msip's bit is set; and the step clock time at which MTIP turns
// on by itself (nothing else changes without a store).
@(private = "file")
clint_interrupts :: proc(data: rawptr, now: u64) -> (lines: u64, changes_at: u64) {
	clint := (^Clint)(data)
	changes_at = max(u64)
	if clint.msip & 1 != 0 {
		lines |= rv.MIP_MSIP
	}
	if clint_mtime(clint, now) >= clint.mtimecmp {
		lines |= rv.MIP_MTIP
	} else if steps, coming := clint_steps_to_alarm(clint, now); coming {
		// When mtime reaches the alarm. If that is further away than the
		// clock can count, never (max(u64)), rather than wrapping round
		// to a time that has already passed, which would make the machine
		// ask again on every step.
		changes_at = now + steps if steps <= max(u64) - now else max(u64)
	}
	return lines, changes_at
}

@(private = "file")
clint_save :: proc(data: rawptr) -> rv.Device_State {
	clint := (^Clint)(data)
	state: rv.Device_State
	mem.copy(&state, clint, size_of(Clint))
	return state
}

@(private = "file")
clint_restore :: proc(data: rawptr, state: rv.Device_State) {
	clint := (^Clint)(data)
	state := state
	mem.copy(clint, &state, size_of(Clint))
}

@(private = "file")
clint_destroy :: proc(data: rawptr) {
	free((^Clint)(data))
}
