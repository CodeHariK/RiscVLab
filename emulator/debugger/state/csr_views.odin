package state

import rv "../../core"

// sstatus, sie and sip are views (core/csr.odin): sstatus shows mstatus's
// supervisor fields, sie and sip show mie and mip through mideleg. So one
// write can change two rows: a csrw sie changes mie too, a csrw mie
// changes sie only if the bits it changed are delegated, and a csrw
// mideleg changes what sie and sip show without writing either.
//
// The undo record names only the CSR the instruction wrote. For these six
// rows the debugger works out the value before the step instead (from
// the record and the CSRs now, after the step) and compares it with the
// value now: a row is marked only if its value really changed.

// The views and the CSRs behind them.
CSR_VIEW_ROWS :: [?]u32{rv.CSR_MSTATUS, rv.CSR_SSTATUS, rv.CSR_MIE, rv.CSR_SIE, rv.CSR_MIP, rv.CSR_SIP}

// True if the step `record` changed this view row's value, other than by
// naming it (a write to its partner, or to mideleg). False for CSRs that
// aren't one of CSR_VIEW_ROWS. `cpu` is the hart right after that step.
csr_changed_through_view :: proc(cpu: ^rv.Cpu, record: rv.Undo_Record, address: u32) -> bool {
	switch address {
	case rv.CSR_MSTATUS, rv.CSR_SSTATUS, rv.CSR_MIE, rv.CSR_SIE, rv.CSR_MIP, rv.CSR_SIP:
		now, _ := rv.csr_read(cpu, address)
		return csr_before_step(cpu, record, address) != now
	}
	return false
}

// The value a CSR had before the step `record` describes. A view's is
// worked out from the CSRs behind it; a CSR written through its view gets
// back the bits that write could change (the same merges as csr_restore).
@(private = "file")
csr_before_step :: proc(cpu: ^rv.Cpu, record: rv.Undo_Record, address: u32) -> u64 {
	switch address {
	case rv.CSR_SSTATUS:
		return csr_before_step(cpu, record, rv.CSR_MSTATUS) & rv.SSTATUS_MASK
	case rv.CSR_SIE:
		return csr_before_step(cpu, record, rv.CSR_MIE) & csr_before_step(cpu, record, rv.CSR_MIDELEG)
	case rv.CSR_SIP:
		return csr_before_step(cpu, record, rv.CSR_MIP) & csr_before_step(cpu, record, rv.CSR_MIDELEG)
	}
	now, _ := rv.csr_read(cpu, address)
	if record.trap_taken && address == rv.CSR_MSTATUS {
		return record.trap_mstatus
	}
	if !record.csr_changed {
		return now
	}
	if record.csr_address == address {
		return record.csr_old
	}
	// Written through its view. mideleg is as it was: this step wrote
	// the view, not mideleg.
	mideleg := cpu.csr.mideleg
	switch {
	case address == rv.CSR_MSTATUS && record.csr_address == rv.CSR_SSTATUS:
		return (now &~ rv.SSTATUS_MASK) | (record.csr_old & rv.SSTATUS_MASK)
	case address == rv.CSR_MIE && record.csr_address == rv.CSR_SIE:
		return (now &~ mideleg) | (record.csr_old & mideleg)
	case address == rv.CSR_MIP && record.csr_address == rv.CSR_SIP:
		writable := rv.MIP_SSIP & mideleg
		return (now &~ writable) | (record.csr_old & writable)
	}
	return now
}
