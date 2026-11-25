package view

import "core:fmt"
import "core:strings"
import rv "../../core"
import state "../state"

// What the CSRs tab shows: which CSRs, in what order, and a readable
// meaning for each value.

// Trap-related CSRs first (machine, then supervisor), then the rest.
csr_view_order := [?]u32 {
	rv.CSR_MSTATUS,
	rv.CSR_MTVEC,
	rv.CSR_MEPC,
	rv.CSR_MCAUSE,
	rv.CSR_MTVAL,
	rv.CSR_MSCRATCH,
	rv.CSR_MEDELEG,
	rv.CSR_MIDELEG,
	rv.CSR_SSTATUS,
	rv.CSR_SIE,
	rv.CSR_SIP,
	rv.CSR_STVEC,
	rv.CSR_SEPC,
	rv.CSR_SCAUSE,
	rv.CSR_STVAL,
	rv.CSR_SSCRATCH,
	rv.CSR_MIE,
	rv.CSR_MIP,
	rv.CSR_MISA,
	rv.CSR_MINSTRET,
	rv.CSR_MCYCLE,
	rv.CSR_MHARTID,
	rv.CSR_MVENDORID,
	rv.CSR_MARCHID,
	rv.CSR_MIMPID,
}

// A short reading of the value, e.g. "MIE=1 MPIE=0 MPP=Machine".
csr_meaning :: proc(session: ^state.Session, address: u32, value: u64) -> string {
	switch address {
	case rv.CSR_MSTATUS:
		return fmt.tprintf(
			"MIE=%d MPIE=%d MPP=%v  SIE=%d SPIE=%d SPP=%v",
			(value & rv.MSTATUS_MIE) >> 3,
			(value & rv.MSTATUS_MPIE) >> 7,
			rv.mstatus_mpp(value),
			(value & rv.MSTATUS_SIE) >> 1,
			(value & rv.MSTATUS_SPIE) >> 5,
			rv.mstatus_spp(value),
		)
	case rv.CSR_SSTATUS:
		// The same bits as in mstatus: sstatus is a view of it.
		return fmt.tprintf(
			"SIE=%d SPIE=%d SPP=%v (mstatus's supervisor fields)",
			(value & rv.MSTATUS_SIE) >> 1,
			(value & rv.MSTATUS_SPIE) >> 5,
			rv.mstatus_spp(value),
		)
	case rv.CSR_MTVEC:
		if rv.mtvec_base(value) == 0 {
			return "no handler: traps stop the machine"
		}
		return handler_text(value)
	case rv.CSR_STVEC:
		if rv.mtvec_base(value) == 0 {
			return "not set"
		}
		return handler_text(value)
	case rv.CSR_MCAUSE, rv.CSR_SCAUSE:
		// mcause is 0 at reset, and 0 is also a real cause
		// (Instruction_Address_Misaligned). Nothing has written it since
		// Reset, neither a trap nor a csrw, so the 0 is the reset value.
		// (Prev keeps this right: it takes back the write too.) The same
		// for scause.
		if state.last_write_csr(session, address) == 0 {
			return "no trap yet"
		}
		return cause_text(value)
	case rv.CSR_MEDELEG:
		return delegated_text(value)
	case rv.CSR_MIDELEG:
		if value == 0 {
			return "nothing delegated: every interrupt goes to machine mode"
		}
		return interrupt_bits_text(value, "to supervisor", machine = false)
	case rv.CSR_SIE:
		return interrupt_bits_text(value, "enabled (delegated only)", machine = false)
	case rv.CSR_SIP:
		return interrupt_bits_text(value, "pending (delegated only)", machine = false)
	case rv.CSR_MIE:
		return interrupt_bits_text(value, "enabled")
	case rv.CSR_MIP:
		return interrupt_bits_text(value, "pending")
	case rv.CSR_MISA:
		return misa_text(value)
	case rv.CSR_MINSTRET:
		return "instructions retired"
	case rv.CSR_MCYCLE:
		return "clock cycles (one per instruction here)"
	}
	return value_text(value)
}

// mcause as a name: "Illegal_Instruction", "Machine_Timer_Interrupt",
// "interrupt 9" for another interrupt (bit 63 set), or the number for a
// value that names no cause (software can write any).
@(private)
cause_text :: proc(value: u64) -> string {
	for cause in rv.Trap_Cause {
		if u64(cause) == value {
			return fmt.tprintf("%v", cause)
		}
	}
	if value & rv.INTERRUPT_BIT != 0 {
		return fmt.tprintf("interrupt %d", value &~ rv.INTERRUPT_BIT)
	}
	return fmt.tprintf("%s: not a cause this hart raises", value_text(value))
}

// mie / mip / mideleg: the interrupt bits, machine then supervisor:
// "pending: M software=0 timer=1 external=0, S software=0 timer=0 external=0".
// mideleg has only the supervisor ones (machine = false).
@(private)
interrupt_bits_text :: proc(value: u64, what: string, machine := true) -> string {
	supervisor := fmt.tprintf(
		"S software=%d timer=%d external=%d",
		(value & rv.MIP_SSIP) >> 1,
		(value & rv.MIP_STIP) >> 5,
		(value & rv.MIP_SEIP) >> 9,
	)
	if !machine {
		return fmt.tprintf("%s: %s", what, supervisor)
	}
	return fmt.tprintf(
		"%s: M software=%d timer=%d external=%d, %s",
		what,
		(value & rv.MIP_MSIP) >> 3,
		(value & rv.MIP_MTIP) >> 7,
		(value & rv.MIP_MEIP) >> 11,
		supervisor,
	)
}

// True if the last Next changed this CSR: a CSR instruction or MRET wrote
// it, or trap entry set it.
csr_changed_by_last_step :: proc(session: ^state.Session, address: u32) -> bool {
	record, has_record := session.last_step.?
	if !has_record {
		return false
	}
	if record.csr_changed && record.csr_address == address {
		return true
	}
	// A view or the CSR behind it, changed through the other, or sie / sip
	// changed by a write to mideleg (state/csr_views.odin).
	if state.csr_changed_through_view(&session.machine.cpu, record, address) {
		return true
	}
	if record.trap_taken {
		switch address {
		case rv.CSR_MSTATUS:
			return true
		case rv.CSR_MEPC, rv.CSR_MCAUSE, rv.CSR_MTVAL:
			return !record.trap_to_supervisor
		case rv.CSR_SEPC, rv.CSR_SCAUSE, rv.CSR_STVAL:
			return record.trap_to_supervisor
		}
	}
	return false
}

// misa read from its bits: the width (MXL), the extension letters in the
// usual order, and the modes below machine (S and U are bits too, but
// modes, not instruction sets). "RV64IMA, modes: machine, supervisor, user"
@(private = "file")
misa_text :: proc(value: u64) -> string {
	builder := strings.builder_make(context.temp_allocator)
	widths := [4]string{"?", "32", "64", "128"}
	fmt.sbprintf(&builder, "RV%s", widths[value >> 62])
	for letter in "IEMAFDQCV" {
		if value & (u64(1) << u64(letter - 'A')) != 0 {
			strings.write_rune(&builder, letter)
		}
	}
	strings.write_string(&builder, ", modes: machine")
	if value & (u64(1) << u64('S' - 'A')) != 0 {
		strings.write_string(&builder, ", supervisor")
	}
	if value & (u64(1) << u64('U' - 'A')) != 0 {
		strings.write_string(&builder, ", user")
	}
	return strings.to_string(builder)
}

// mtvec or stvec as a handler address and mode (they share a layout).
@(private = "file")
handler_text :: proc(value: u64) -> string {
	mode := "vectored" if rv.mtvec_mode(value) == rv.MTVEC_VECTORED else "direct"
	return fmt.tprintf("handler at 0x%x (%s)", rv.mtvec_base(value), mode)
}

// medeleg as the exceptions it sends to supervisor mode:
// "to supervisor: Illegal_Instruction, Ecall_From_U_Mode".
@(private = "file")
delegated_text :: proc(value: u64) -> string {
	if value == 0 {
		return "nothing delegated: every exception goes to machine mode"
	}
	builder := strings.builder_make(context.temp_allocator)
	strings.write_string(&builder, "to supervisor:")
	first := true
	for cause in rv.Trap_Cause {
		if rv.trap_is_interrupt(cause) || value & (u64(1) << rv.trap_cause_number(cause)) == 0 {
			continue
		}
		strings.write_string(&builder, " " if first else ", ")
		fmt.sbprintf(&builder, "%v", cause)
		first = false
	}
	return strings.to_string(builder)
}
