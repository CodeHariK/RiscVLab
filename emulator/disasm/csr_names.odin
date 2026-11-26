package disasm

import rv "../core"

// Names of the CSRs this emulator implements, as assemblers and objdump
// spell them. Used by the disassembler and the debugger. Returns "" for
// any other address (the disassembler then prints it in hex, as objdump
// does for CSRs it doesn't know).
csr_name :: proc(address: u32) -> string {
	switch address {
	case rv.CSR_MVENDORID: return "mvendorid"
	case rv.CSR_MARCHID: return "marchid"
	case rv.CSR_MIMPID: return "mimpid"
	case rv.CSR_MHARTID: return "mhartid"
	case rv.CSR_MSTATUS: return "mstatus"
	case rv.CSR_MISA: return "misa"
	case rv.CSR_MEDELEG: return "medeleg"
	case rv.CSR_MIDELEG: return "mideleg"
	case rv.CSR_MIE: return "mie"
	case rv.CSR_MTVEC: return "mtvec"
	case rv.CSR_MSCRATCH: return "mscratch"
	case rv.CSR_MEPC: return "mepc"
	case rv.CSR_MCAUSE: return "mcause"
	case rv.CSR_MTVAL: return "mtval"
	case rv.CSR_MIP: return "mip"
	case rv.CSR_MCOUNTEREN: return "mcounteren"
	case rv.CSR_SCOUNTEREN: return "scounteren"
	case rv.CSR_MENVCFG: return "menvcfg"
	case rv.CSR_STIMECMP: return "stimecmp"
	case rv.CSR_SSTATUS: return "sstatus"
	case rv.CSR_SIE: return "sie"
	case rv.CSR_SIP: return "sip"
	case rv.CSR_STVEC: return "stvec"
	case rv.CSR_SSCRATCH: return "sscratch"
	case rv.CSR_SEPC: return "sepc"
	case rv.CSR_SCAUSE: return "scause"
	case rv.CSR_STVAL: return "stval"
	case rv.CSR_MCYCLE: return "mcycle"
	case rv.CSR_MINSTRET: return "minstret"
	case rv.CSR_CYCLE: return "cycle"
	case rv.CSR_TIME: return "time"
	case rv.CSR_INSTRET: return "instret"
	}
	return ""
}
