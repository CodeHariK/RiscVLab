package disasm

import rv "../core"

// ABI names for x0..x31, as used by assemblers, objdump and the debugger.
//
//   zero      hard-wired zero          ra        return address
//   sp        stack pointer            gp / tp   global / thread pointer
//   t0..t6    temporaries              s0..s11   saved registers
//   a0..a7    arguments and return values
@(rodata)
register_abi_names := [rv.REGISTER_COUNT]string {
	"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
	"s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
	"a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
	"s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
}

register_name :: #force_inline proc(index: u32) -> string {
	return register_abi_names[index & 0x1F]
}
