package rvdbg

import "core:fmt"
import rv "../core"

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
		return fmt.tprintf("%v", rv.Trap_Cause(value))
	case rv.CSR_MISA:
		return "RV64IMA"
	case rv.CSR_MINSTRET:
		return "instructions retired (= mcycle)"
	}
	return value_text(value)
}

// True if the last Next changed this CSR: a CSR instruction or MRET wrote
// it, or trap entry set it.
csr_changed_by_last_step :: proc(session: ^Session, address: u32) -> bool {
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
