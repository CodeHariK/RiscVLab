package view

import "core:fmt"
import rv "../../core"
import state "../state"

// What the CSRs tab shows: which CSRs, in what order, and a readable
// meaning for each value.

// Trap-related CSRs first, then the rest.
csr_view_order := [?]u32 {
	rv.CSR_MSTATUS,
	rv.CSR_MTVEC,
	rv.CSR_MEPC,
	rv.CSR_MCAUSE,
	rv.CSR_MTVAL,
	rv.CSR_MSCRATCH,
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
csr_meaning :: proc(cpu: ^rv.Cpu, address: u32, value: u64) -> string {
	switch address {
	case rv.CSR_MSTATUS:
		return fmt.tprintf(
			"MIE=%d MPIE=%d MPP=%v",
			(value & rv.MSTATUS_MIE) >> 3,
			(value & rv.MSTATUS_MPIE) >> 7,
			rv.Privilege((value & rv.MSTATUS_MPP) >> rv.MSTATUS_MPP_SHIFT),
		)
	case rv.CSR_MTVEC:
		if value == 0 {
			return "no handler: traps stop the machine"
		}
		mode := "vectored" if value & 0b11 == 1 else "direct"
		return fmt.tprintf("handler at 0x%x (%s)", value &~ 0b11, mode)
	case rv.CSR_MCAUSE:
		if cpu.csr.mepc == 0 && value == 0 {
			return "no trap yet"
		}
		return cause_text(value)
	case rv.CSR_MIE:
		return interrupt_bits_text(value, "enabled")
	case rv.CSR_MIP:
		return interrupt_bits_text(value, "pending (driven by the devices)")
	case rv.CSR_MISA:
		return "RV64IMA"
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

// mie / mip: the three machine interrupt bits.
@(private)
interrupt_bits_text :: proc(value: u64, what: string) -> string {
	return fmt.tprintf(
		"%s: software=%d timer=%d external=%d",
		what,
		(value & rv.MIP_MSIP) >> 3,
		(value & rv.MIP_MTIP) >> 7,
		(value & rv.MIP_MEIP) >> 11,
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
	if record.trap_taken {
		switch address {
		case rv.CSR_MSTATUS, rv.CSR_MEPC, rv.CSR_MCAUSE, rv.CSR_MTVAL:
			return true
		}
	}
	return false
}
