# Instructions: what each one is for

The debugger's Docs tab shows these entries: by default the one for the
instruction Next will run. Each entry covers one instruction or a small
family that differs only in size or signedness. The format, so the
debugger can read it:

- `## names - title`: the mnemonics (as the disassembler prints them),
  then a dash and a short title.
- An italic line with the encoding format and extension.
- Paragraphs starting with a label (`Does:`, `For:`, ...), and examples
  indented by four spaces.

Values in the examples are in hex, as in the debugger. The text is plain
ASCII, since the debugger's font only has ASCII characters.

## lui - Load upper immediate

*U-type, RV64I*

Does: rd = imm << 12. The 20-bit immediate becomes bits 31..12 of rd, the low 12 bits are zero, and the result is sign-extended to 64 bits.

For: building a constant too big for a 12-bit immediate. `lui` sets the upper 20 bits and an `addi` adds the low 12 bits. Also the first half of an absolute address.

Pseudo: `li rd, big_number` often assembles to `lui` + `addi` (or `addiw`).

Watch out: `addi` sign-extends its 12 bits, so when the low part is 0x800 or more it counts as negative. The assembler then adds 1 to the upper part to make up for it: `li t0, 0x12345fff` becomes `lui t0, 0x12346` + `addi t0, t0, -0x1`. Lesson 04 shows this.

Related: auipc, addi

Example:
    lui  t0, 0x12345       # t0 = 0x12345000
    addi t0, t0, 0x678     # t0 = 0x12345678

## auipc - Add upper immediate to pc

*U-type, RV64I*

Does: rd = pc + (imm << 12), where pc is the address of the `auipc` itself.

For: finding addresses relative to where the code is, without knowing where the program was loaded. Together with an `addi`, a load, a store or `jalr`, it reaches anything within +/- 2 GiB of the instruction.

Pseudo: `la rd, symbol` is `auipc` + `addi`; `call function` is `auipc ra, ...` + `jalr ra, ...(ra)`.

Watch out: the low 12 bits come from the next instruction, with the same sign trick as `lui` + `addi`: `addi -0x14` after `auipc 0x1` means 0x1000 - 0x14 = 0xfec past the `auipc`.

Related: lui, addi, jalr

Example:
    auipc t0, 0x1          # t0 = pc + 0x1000
    addi  t0, t0, 0x10     # t0 = pc + 0x1010: the address of a variable

## addi - Add immediate

*I-type, RV64I*

Does: rd = rs1 + imm. The immediate is 12 bits, sign-extended: -0x800 to 0x7ff. Overflow simply wraps around.

For: the most used instruction there is: adding small constants, counting loops up and down, moving pointers along an array, making room on the stack.

Pseudo: `li rd, small` is `addi rd, zero, small`; `mv rd, rs` is `addi rd, rs, 0`; `nop` is `addi zero, zero, 0`.

Watch out: there is no `subi`; subtract with a negative immediate: `addi t0, t0, -1`.

Related: add, addiw, lui

Example:
    addi sp, sp, -0x10     # make room for 16 bytes on the stack
    addi t1, t1, -1        # one fewer left

## slti sltiu - Set if less than immediate

*I-type, RV64I*

Does: rd = 1 if rs1 < imm, else 0. `slti` compares as signed numbers, `sltiu` as unsigned. The immediate is sign-extended in both.

For: turning a comparison into a 0 / 1 value you can store or add up, instead of branching.

Pseudo: `seqz rd, rs` (is it zero?) is `sltiu rd, rs, 1`.

Watch out: `sltiu` sign-extends the immediate and then compares unsigned, so `sltiu t0, t1, -1` compares with 0xffffffffffffffff: true for every value except that one.

Related: slt, sltu, blt, bltu

Example:
    slti  t0, a0, 0x0      # t0 = 1 if a0 is negative
    sltiu t1, a1, 1        # t1 = 1 if a1 == 0

## andi ori xori - Bitwise with an immediate

*I-type, RV64I*

Does: rd = rs1 & imm, rs1 | imm, rs1 ^ imm, bit by bit. The 12-bit immediate is sign-extended first.

For: masks. `andi` keeps chosen bits (e.g. the low byte), `ori` sets bits, `xori` flips bits.

Pseudo: `not rd, rs` is `xori rd, rs, -1`.

Watch out: because of sign extension, `andi t0, t0, 0x800` is not possible (0x800 does not fit); immediates 0x800..0xfff mean negative numbers with all high bits set.

Related: and, or, xor

Example:
    andi t0, a0, 0xff      # keep the low byte
    xori t1, t1, -1        # flip every bit

## slli srli srai - Shift by a constant

*I-type (shift), RV64I*

Does: shift rs1 left or right by shamt (0 to 63) bits. `slli` fills with zeros from the right; `srli` (logical) fills with zeros from the left; `srai` (arithmetic) copies the sign bit in from the left.

For: multiplying or dividing by powers of two, packing and unpacking bit fields, turning an array index into a byte offset (`slli t0, t0, 3` for 8-byte elements).

Watch out: `srai` on a negative number rounds toward minus infinity: -5 >> 1 is -3, not -2 as division would give.

Related: sll, srl, sra, slliw

Example:
    slli t0, t1, 3         # t0 = t1 * 8
    srai t2, t2, 1         # t2 / 2, keeping the sign

## add sub - Add, subtract

*R-type, RV64I*

Does: rd = rs1 + rs2, or rd = rs1 - rs2, on all 64 bits. Overflow wraps around; there are no flags.

For: arithmetic on two registers, adding an offset to a base address.

Pseudo: `neg rd, rs` is `sub rd, zero, rs`.

Watch out: the same instruction does signed and unsigned arithmetic: the bits come out the same either way. Lesson 02 shows the wrap-around.

Related: addi, addw, subw

Example:
    add a0, a0, t2         # sum += number
    sub t0, t1, t2

## slt sltu - Set if less than

*R-type, RV64I*

Does: rd = 1 if rs1 < rs2, else 0. `slt` treats both as signed (two's complement), `sltu` as unsigned.

For: comparisons that give a value (0 or 1) rather than a jump, e.g. to count how many items are smaller.

Pseudo: `snez rd, rs` (is it non-zero?) is `sltu rd, zero, rs`; `sltz` and `sgtz` are `slt` with zero.

Watch out: 0xffffffffffffffff is -1 to `slt` and the biggest number to `sltu`. Lesson 06 compares both.

Related: slti, sltiu, blt, bltu

Example:
    slt  t0, a0, a1        # a0 < a1 as signed numbers?
    sltu t1, a0, a1        # ... as unsigned numbers?

## and or xor - Bitwise on two registers

*R-type, RV64I*

Does: rd = rs1 & rs2, rs1 | rs2, rs1 ^ rs2, bit by bit.

For: masks that don't fit an immediate, combining flags, swapping or comparing bit patterns (`xor` gives 0 exactly when the two are equal).

Related: andi, ori, xori

Example:
    and t0, t1, t2
    xor t3, a0, a1         # 0 if a0 == a1

## sll srl sra - Shift by a register

*R-type, RV64I*

Does: like `slli` / `srli` / `srai`, but the amount comes from rs2. Only its low 6 bits are used (0 to 63).

For: shifts by an amount known only while running, e.g. building a mask `1 << n`.

Watch out: shifting by 64 is shifting by 0, since only the low 6 bits of rs2 count.

Related: slli, srli, srai, sllw

Example:
    addi t0, zero, 1
    sll  t0, t0, a0        # t0 = 1 << a0

## addiw slliw srliw sraiw addw subw sllw srlw sraw - 32-bit word operations

*I-type and R-type, RV64I*

Does: the same as the instruction without the `w`, but computed on the low 32 bits of the operands; the 32-bit result is then sign-extended to fill all 64 bits of rd. Shift amounts are 0 to 31.

For: `int` (32-bit) arithmetic in C on a 64-bit machine: results wrap at 32 bits, exactly as C's `int` does. Also used by `li` for some constants.

Pseudo: `sext.w rd, rs` (sign-extend the low 32 bits) is `addiw rd, rs, 0`.

Watch out: the result is always sign-extended, even for `srliw`: shifting 0x80000000 right by 0 gives 0xffffffff80000000. Lesson 10 shows this.

Related: addi, add, sub, slli, sll

Example:
    addiw t0, t0, 1        # 0x7fffffff + 1 = 0xffffffff80000000 (int overflow)
    addw  a0, a0, a1

## lb lh lw ld lbu lhu lwu - Load from memory

*I-type, RV64I*

Does: rd = the value at address rs1 + imm. `b` = 1 byte, `h` = 2 bytes (half word), `w` = 4 bytes (word), `d` = 8 bytes (double word). Without `u`, the value is sign-extended to 64 bits; with `u`, zero-extended. `ld` loads all 64 bits, so it has no `u` form.

For: reading variables, array elements and struct fields, and restoring registers saved on the stack. RISC-V only does arithmetic on registers, so every value in memory is loaded first.

Watch out: pick the signed or unsigned form to match the data: byte 0xff loads as -1 with `lb` and as 0xff (255) with `lbu`. Bytes are stored lowest first (little-endian). Lesson 07 shows both.

Related: sb sh sw sd, auipc

Example:
    lw  t2, 0(t0)          # t2 = the 32-bit number at address t0
    ld  ra, 8(sp)          # restore the return address from the stack
    lbu t6, 0(t4)          # one byte, 0 to 0xff

## sb sh sw sd - Store to memory

*S-type, RV64I*

Does: write the low 1, 2, 4 or 8 bytes of rs2 to address rs1 + imm.

For: writing variables and array elements, and saving registers on the stack (e.g. `ra` before calling another function).

Watch out: the operand order looks backwards: in `sw a0, 0(t3)` the value is the first operand and the address the second. Stores don't change any register, so the Registers panel stays the same; watch the Memory tab instead.

Related: lb lh lw ld

Example:
    sw a0, 0(t3)           # store the sum into the variable at t3
    sd ra, 8(sp)           # save the return address on the stack

## beq bne - Branch if equal, not equal

*B-type, RV64I*

Does: if rs1 == rs2 (`beq`) or rs1 != rs2 (`bne`), jump to pc + offset; otherwise continue with the next instruction. The offset reaches +/- 4 KiB.

For: `if` statements and loops.

Pseudo: `beqz rs, label` is `beq rs, zero, label`; `bnez rs, label` is `bne rs, zero, label`; `j label` is `jal zero, label` (not a branch).

Watch out: there are no condition flags in RISC-V: every branch compares two registers itself.

Related: blt bge bltu bgeu, jal

Example:
    bnez t1, loop          # repeat while t1 != 0

## blt bge bltu bgeu - Branch on less than / greater or equal

*B-type, RV64I*

Does: jump to pc + offset if rs1 < rs2 (`blt`) or rs1 >= rs2 (`bge`), comparing as signed numbers; `bltu` / `bgeu` compare as unsigned.

For: counting loops (`blt i, n, loop`), range checks, and comparing addresses (always unsigned).

Pseudo: `bgt`, `ble`, `bgtu`, `bleu` are these with the operands swapped; `bltz`, `bgez`, `blez`, `bgtz` compare with zero.

Watch out: an unsigned compare against 0xffffffffffffffff is very different from a signed compare against -1. Lesson 06.

Related: beq bne, slt sltu

Example:
    blt t0, t1, loop       # while t0 < t1
    bgeu a0, a1, done      # unsigned: a0 >= a1

## jal - Jump and link

*J-type, RV64I*

Does: rd = pc + 4 (the return address), then jump to pc + offset. The offset reaches +/- 1 MiB.

For: calling a function: `jal ra, function` saves where to come back to in `ra`. With rd = zero it is a plain jump.

Pseudo: `j label` is `jal zero, label`; `jal label` (one operand) means `jal ra, label`; `call` uses `auipc` + `jalr` when the target may be further away.

Watch out: a function that calls another function overwrites `ra`, so it must save its own `ra` (usually on the stack) first. Lessons 08 and 09.

Related: jalr, auipc

Example:
    jal ra, square         # call square; it returns to the next instruction

## jalr - Jump and link register

*I-type, RV64I*

Does: rd = pc + 4, then jump to (rs1 + imm) with bit 0 cleared. The target comes from a register.

For: returning from a function (`jalr zero, 0(ra)`), calling through a function pointer, and far calls together with `auipc`.

Pseudo: `ret` is `jalr zero, 0(ra)`; `jr rs` is `jalr zero, 0(rs)`.

Watch out: the target is worked out from rs1 before rd is written, so `jalr ra, 0(ra)` works.

Related: jal, auipc

Example:
    jalr zero, 0(ra)       # ret: back to the caller

## fence - Memory ordering fence

*I-type, RV64I*

Does: makes sure memory accesses before the fence are seen by other harts and devices before those after it. The operands (e.g. `iorw, iorw`) say which kinds of access are ordered: device input/output (i, o), memory reads and writes (r, w).

For: multi-core code and device drivers: publishing data before a flag, or making sure a write to a device register happens before the next one.

Watch out: this emulator has one hart that does everything in order, so `fence` does nothing here. It will matter for devices later.

Related: fence.i

Example:
    fence rw, rw

## fence.i - Instruction fence (Zifencei)

*I-type, Zifencei*

Does: makes sure instructions fetched after it see earlier stores to memory.

For: code that writes code: loaders, JIT compilers. Without it, a CPU with an instruction cache may still run the old bytes.

Watch out: there is no instruction cache in this emulator, so it does nothing here.

Related: fence

Example:
    fence.i

## ecall - Environment call

*I-type, RV64I (privileged behaviour)*

Does: raises an environment-call trap. The cause depends on the current privilege: `Ecall_From_U_Mode` (8), `Ecall_From_S_Mode` (9) or `Ecall_From_M_Mode` (11). mepc gets the address of the `ecall` itself.

For: asking more privileged code to do something: a user program asks the kernel (a system call, e.g. xv6's `write`), the kernel asks the firmware. By convention the request number goes in `a7` and arguments in `a0`..`a5`.

Watch out: the handler must add 4 to mepc before `mret`, or it returns to the `ecall` and runs it again. With no handler (mtvec = 0) this emulator stops. Lessons 12 and 13.

Related: mret, ebreak, csrrw (mtvec)

Example:
    addi a7, zero, 0x10    # system call number: 16 is xv6's write
    ecall

## ebreak - Breakpoint

*I-type, RV64I (privileged behaviour)*

Does: raises a `Breakpoint` trap (cause 3).

For: debuggers place it where execution should stop. The test programs and lessons here end with it: with no trap handler set up, the emulator stops, and a0 holds the result.

Related: ecall

Example:
    ebreak                 # a0 = result; the program ends here

## mret - Return from a machine-mode trap

*I-type, privileged*

Does: pc = mepc; the privilege level goes back to the one saved in mstatus.MPP; MIE = MPIE (interrupts back to how they were); MPIE = 1; MPP = the least privileged mode.

For: the last instruction of a trap handler, going back to the interrupted code. Also how a kernel enters user mode the first time: set mepc to the user program and MPP to user, then `mret`.

Watch out: for `ecall`, mepc points at the `ecall` itself; add 4 first or it runs again. Lesson 13.

Related: ecall, csrrw (mepc, mstatus)

Example:
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    mret

## csrrw csrrwi - CSR read and write

*I-type (CSR), Zicsr*

Does: in one step: rd = old value of the CSR, then CSR = rs1 (or the 5-bit unsigned immediate for `csrrwi`). If rd is zero the CSR is not read at all.

For: setting a CSR to a value (e.g. the trap handler address in `mtvec`) or swapping a register with a CSR (e.g. with `mscratch` at the start of a trap handler).

Pseudo: `csrw csr, rs` is `csrrw zero, csr, rs`; `csrwi` likewise.

Watch out: CSRs keep only the bits they support (WARL: "write any, read legal"): writing a value and reading it back can give something else, e.g. mstatus.MPP here is always machine mode. The step details say when this happens.

Related: csrrs, csrrc, mret

Example:
    la   t0, handler
    csrw mtvec, t0         # traps now jump to handler

## csrrs csrrsi - CSR read and set bits

*I-type (CSR), Zicsr*

Does: rd = old value of the CSR, then set the CSR bits that are 1 in rs1 (or the immediate). If rs1 is zero (or the immediate is 0) the CSR is not written, so it is a pure read.

For: reading a CSR (the most common use), and turning on single bits such as mstatus.MIE.

Pseudo: `csrr rd, csr` is `csrrs rd, csr, zero`; `csrs csr, rs` is `csrrs zero, csr, rs`.

Watch out: reading some CSRs has meaning by itself: `minstret` counts instructions as they retire.

Related: csrrw, csrrc

Example:
    csrr  t0, mcause       # why did we trap?
    csrsi mstatus, 0x8     # set MIE: interrupts on

## csrrc csrrci - CSR read and clear bits

*I-type (CSR), Zicsr*

Does: rd = old value of the CSR, then clear the CSR bits that are 1 in rs1 (or the immediate). With rs1 zero (or immediate 0) the CSR is not written.

For: turning off single bits, e.g. disabling interrupts (mstatus.MIE) around code that must not be interrupted.

Pseudo: `csrc csr, rs` is `csrrc zero, csr, rs`; `csrci` likewise.

Related: csrrw, csrrs

Example:
    csrci mstatus, 0x8     # clear MIE: interrupts off
