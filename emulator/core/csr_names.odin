package rv

// Names of the CSRs this emulator implements, as assemblers and objdump
// spell them. Used by the disassembler and the debugger. Returns "" for
// any other address (the disassembler then prints it in hex, as objdump
// does for CSRs it doesn't know).
csr_name :: proc(address: u32) -> string {
	switch address {
	case CSR_MVENDORID: return "mvendorid"
	case CSR_MARCHID: return "marchid"
	case CSR_MIMPID: return "mimpid"
	case CSR_MHARTID: return "mhartid"
	case CSR_MSTATUS: return "mstatus"
	case CSR_MISA: return "misa"
	case CSR_MIE: return "mie"
	case CSR_MTVEC: return "mtvec"
	case CSR_MSCRATCH: return "mscratch"
	case CSR_MEPC: return "mepc"
	case CSR_MCAUSE: return "mcause"
	case CSR_MTVAL: return "mtval"
	case CSR_MIP: return "mip"
	case CSR_MCYCLE: return "mcycle"
	case CSR_MINSTRET: return "minstret"
	case CSR_CYCLE: return "cycle"
	case CSR_INSTRET: return "instret"
	}
	return ""
}
