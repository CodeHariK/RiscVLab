# Terms: words the other docs use

Short explanations of words that come up everywhere in RISC-V and in
these docs. Same format as instructions.md.

## hart - Hardware thread

*term*

Does: one independent stream of instructions, with its own pc, its own x0..x31 and its own CSRs.

How it works:
- A simple CPU core is one hart.
- A core with simultaneous multithreading (hyper-threading) runs two or more harts that share its arithmetic units and caches.
- A 4-core chip without it has 4 harts. All harts see the same memory.

For: RISC-V says "hart" rather than "core" because the hart is what software sees: it fetches and runs instructions, takes traps, and has a number in mhartid.

Emulator: one hart. xv6 on QEMU normally starts several, and each picks its own stack by reading mhartid; we will boot it with one first.

Related: mhartid, fence

## register - Registers x0..x31 and their ABI names

*term*

Does: the 32 places inside the CPU where instructions take their operands and put their results. Each holds 64 bits on RV64. Instructions name them x0 to x31.

How it works: the calling convention (the ABI) gives each one a name and a job, so separately written functions can work together:
```
x0       zero   always 0; writes are thrown away
x1       ra     return address
x2       sp     stack pointer
x3, x4   gp tp  global pointer, thread pointer
x5-x7    t0-t2  temporaries: a call may change them
x8-x9    s0-s1  saved: a function must restore them before returning
x10-x17  a0-a7  arguments and return values (a0, a1)
x18-x27  s2-s11 saved
x28-x31  t3-t6  temporaries
```

For: a function that uses an s register saves it first (usually on the stack) and restores it before `ret`; t registers can be used freely but may be changed by any call.

Watch out: the CPU itself only treats x0 specially (and uses x1 / x5 as hints for calls and returns). The other jobs are a convention that code follows.

Related: pc, abi, stack

## pc - Program counter

*term*

Does: the address of the instruction being run. It is not one of x0..x31.

How it works: after each instruction pc moves on by 4, unless the instruction is a jump or a taken branch, which set it to the target, or a trap, which sets it to mtvec. Only `auipc` (and `jal` / `jalr`, for the return address) read it.

Related: auipc, jal, jalr, trap

## abi - Application binary interface

*term*

Does: the rules that let code written separately work together: which registers carry arguments and results, which must be preserved across a call, how the stack is laid out, how big each C type is.

How it works: in the RISC-V calling convention, arguments go in a0..a7, results come back in a0 (and a1), ra holds the return address, sp must stay 16-byte aligned, and s0..s11 must be the same after a call as before it.

For: calling C from assembly and back, system calls (number in a7, arguments in a0..a5), and reading compiler output.

Related: register, stack, ecall

## stack - The stack

*term*

Does: an area of memory where functions keep things that don't fit in registers: their return address, saved registers and local variables.

How it works: sp points at the top of the stack, and the stack grows down. A function makes room by subtracting from sp, stores what it must keep, and adds the same amount back before returning:
```
addi sp, sp, -0x10       # make room for 16 bytes
sd   ra, 8(sp)           # save the return address
...
ld   ra, 8(sp)           # restore it
addi sp, sp, 0x10        # free the room
ret
```
Each call that is still running has its own piece of the stack (its frame), so a function can even call itself (recursion).

Watch out: nothing stops the stack from growing past the space reserved for it; it then overwrites whatever lies below.

Related: .space, register, jal, ret

## immediate - Immediate value

*term*

Does: a constant written inside the instruction itself, e.g. the 5 in `addi t0, zero, 5`.

How it works: an instruction is 32 bits and most of them are taken, so immediates are small: 12 bits for `addi` and loads, 20 bits for `lui` and `auipc`. They are sign-extended. The Encoding panel shows which bits hold it; the B- and J-type formats scatter them around.

Related: sign-extension, lui, addi

## sign-extension - Sign and zero extension

*term*

Does: makes a short value fill a wider register.
- Sign extension copies the top bit into all the new bits, so a negative number stays negative: the byte 0xff becomes 0xffffffffffffffff (-1).
- Zero extension fills the new bits with zeros: the byte 0xff becomes 0xff (255).

For: loads (`lb` sign-extends, `lbu` zero-extends), immediates (always sign-extended), and the 32-bit word instructions (`addw` and friends sign-extend their result).

Related: two's-complement, lb lh lw ld lbu lhu lwu, addiw

## two's-complement - Negative numbers

*term*

Does: how negative numbers are stored: -x is stored as (2^64 - x). -1 is 0xffffffffffffffff, -2 is 0xfffffffffffffffe.

How it works: with 64 bits the signed range is -2^63 (0x8000000000000000) to 2^63 - 1 (0x7fffffffffffffff); in Odin these are `min(i64)` and `max(i64)`. There is one more negative number than positive: -2^63 has no positive partner, so negating it or dividing it by -1 overflows back to -2^63 (see `div`).

Adding works the same for signed and unsigned numbers, so one `add` serves both. The top bit tells the sign. Only comparisons, right shifts, extension and division need to know which kind a number is; that is why `slt` / `sltu`, `sra` / `srl` and `lb` / `lbu` come in pairs.

Related: sign-extension, slt sltu, blt bge bltu bgeu, div divu rem remu

## little-endian - Byte order

*term*

Does: a multi-byte value is stored lowest byte first. The word 0x0000000a is stored as the bytes 0a 00 00 00.

For: knowing what the Memory tab's Bytes view shows. The Words view reads each 4 bytes back as a number, so code there looks like the Disassembly tab's hex column.

Related: lb lh lw ld, .word

## word - Byte, half word, word, double word

*term*

Does: the sizes RISC-V names: byte = 8 bits, half word = 16, word = 32, double word = 64.

Watch out: on x86 a "word" is 16 bits. In RISC-V, `lw` loads 32 bits and `ld` 64.

Related: lb lh lw ld, .byte .half .word .dword

## retire - Retiring an instruction

*term*

Does: an instruction retires when it finishes and its result counts. One that traps does not retire.

For: the instret / minstret counters count retired instructions. The toolbar's step number is the same count, so a step that trapped into a handler doesn't add to it.

Related: mcycle minstret cycle instret

## warl - WARL: write any, read legal

*term*

Does: a rule for CSR fields: software may write any value, but the field only keeps values the hardware supports, and reads always give a legal value.

How it works: here mstatus.MPP only supports machine mode, so writing 0 into it still reads back 0b11. The step details say when a CSR kept something other than what was written.

For: software can find out what the hardware supports by writing a value and reading it back.

Related: mstatus, csrrw

## isa - ISA and extensions

*term*

Does: the instruction set architecture: the list of instructions and registers a CPU promises to have. RISC-V names a base and extensions.

How it works:
- RV64I: the 64-bit base integer instructions.
- M: multiply and divide. A: atomic instructions. C: compressed 16-bit instructions. F, D: floating point.
- Zicsr: the CSR instructions.
- Zifencei: one instruction, `fence.i`: "make the instructions I fetch next see the stores I just made". CPUs with separate instruction and data caches need it after writing code into memory (a loader, a JIT). It used to be in the base ISA and was split out because some designs need a different mechanism. Names starting with Z are small extensions without a single letter.

M, F and D: M is integer multiply and divide only. Floating point is separate: F (32-bit floats) and D (64-bit doubles), with their own registers f0..f31. xv6 doesn't use floating point, so this emulator won't need F or D.

This emulator implements RV64IM + Zicsr + Zifencei (plus machine-mode traps). xv6 needs rv64ima, so A comes next.

Related: misa

## exception - Exceptions and interrupts

*term*

Does: the two kinds of trap.
- An exception is caused by the instruction being run: a bad load, an illegal instruction, `ecall`. It happens at that instruction, every time.
- An interrupt comes from outside: a timer, a device. It arrives between instructions, at any time, when enabled.

For: mcause's top bit says which one it was. Exceptions are taken no matter what; interrupts only when mstatus.MIE and the bit in mie allow them.

Related: trap, mcause, mie mip

## assembler - Assembler and linker

*term*

Does:
- The assembler (`riscv64-elf-as`) turns a .s file into machine code: an object file (.o) with sections and symbols, where addresses of labels in other places are still left open.
- The linker (`riscv64-elf-ld`) joins object files, places each section at an address (from the linker script), fills in the open addresses, and writes the ELF executable.

How it works: here `make` in tests/programs runs both, then `objcopy` makes the raw .bin and `objdump` the .dis listing. The emulator only loads the result; it never assembles anything.

Related: elf, link.ld, la
