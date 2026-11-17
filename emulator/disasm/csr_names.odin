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
	case rv.CSR_MIE: return "mie"
	case rv.CSR_MTVEC: return "mtvec"
	case rv.CSR_MSCRATCH: return "mscratch"
	case rv.CSR_MEPC: return "mepc"
	case rv.CSR_MCAUSE: return "mcause"
	case rv.CSR_MTVAL: return "mtval"
	case rv.CSR_MIP: return "mip"
	case rv.CSR_MCYCLE: return "mcycle"
	case rv.CSR_MINSTRET: return "minstret"
	case rv.CSR_CYCLE: return "cycle"
	case rv.CSR_INSTRET: return "instret"
	}
	return ""
}
