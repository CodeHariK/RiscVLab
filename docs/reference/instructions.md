# Instructions: what each one is for

Every instruction the emulator runs, in plain words: what it does, how it
works with real numbers, what it is used for, and the usual mistakes.
Each entry covers one instruction or a small family that differs only in
size or signedness.

The debugger's Docs window shows these entries, by default the one for
the instruction Next will run. Values are in hex, as in the debugger.

Format of an entry (also read by the debugger): a `## names - title`
heading (the names exactly as the disassembler prints them), an italic
line, then sections that start with a label such as `Does:`. A section
continues with plain lines, `- ` bullets and fenced code blocks until the
next label. The text is plain ASCII, since the debugger's font only has
ASCII characters.

## lui - Load upper immediate

*U-type, RV64I*

Does: rd = imm << 12. The 20-bit immediate becomes bits 31..12 of rd; the low 12 bits are zero.

How it works:
1. `lui t0, 0x12345` shifts 0x12345 left by 12: 0x12345000.
2. The result is a 32-bit value, sign-extended to 64 bits: if bit 31 is 1, the upper 32 bits become all ones. `lui t0, 0x80000` gives 0xffffffff80000000.

For: building constants too big for a 12-bit immediate. `lui` sets the upper 20 bits and an `addi` (or `addiw`) adds the lower 12. The `li` pseudo-instruction does this for you.

Watch out:
- `addi` sign-extends its 12 bits, so a lower part of 0x800 or more counts as negative. The upper part must then be one higher: 0x12345800 is `lui 0x12346` then `addi -0x800`.
- Lesson 04 shows this step by step.

Related: auipc, addi, li, encodings#Upper immediates

Example:
```
lui  t0, 0x12345         # t0 = 0x12345000
addi t0, t0, 0x678       # t0 = 0x12345678
```

## auipc - Add upper immediate to pc

*U-type, RV64I*

Does: rd = pc + (imm << 12), where pc is the address of the `auipc` itself.

How it works: at 0x80000040, `auipc t4, 0x1` gives 0x80000040 + 0x1000 = 0x80001040. The next instruction adds the lower 12 bits to land exactly on the target.

For: finding addresses relative to the code, without knowing where the program was loaded. With an `addi`, a load, a store or `jalr` after it, it reaches anything within +/- 2 GiB.
- `la rd, label` is `auipc` + `addi`.
- `call function` is `auipc` + `jalr` (often shortened to one `jal` by the linker).

Watch out: the lower 12 bits come from the next instruction and are signed, so `addi -0x40` after `auipc 0x1` lands 0x1000 - 0x40 = 0xfc0 past the `auipc`. See `la` for the whole calculation.

Related: lui, addi, jalr, la, encodings#Upper immediates

Example:
```
auipc t4, 0x1            # t4 = pc + 0x1000
addi  t4, t4, -0x40      # t4 = the address of a variable
```

## addi - Add immediate

*I-type, RV64I*

Does: rd = rs1 + imm. The immediate is 12 bits, sign-extended: -0x800 to 0x7ff.

How it works: `addi t0, t0, -0x1` with t0 = 0x5 gives 0x4. Overflow wraps around: adding 1 to 0x7fffffffffffffff gives 0x8000000000000000.

For: the most used instruction there is.
- adding small constants and counting loops up or down;
- moving a pointer along an array;
- making room on the stack (`addi sp, sp, -0x10`).

Pseudo: several pseudo-instructions are `addi`:
```
li rd, small   ->  addi rd, zero, small
mv rd, rs      ->  addi rd, rs, 0x0
nop            ->  addi zero, zero, 0x0
```

Watch out: there is no `subi`; subtract with a negative immediate: `addi t0, t0, -0x1`.

Related: add, addiw, lui, encodings#Register-immediate arithmetic

Example:
```
addi sp, sp, -0x10       # make room for 16 bytes on the stack
addi t1, t1, -0x1        # one fewer left
```

## slti sltiu - Set if less than immediate

*I-type, RV64I*

Does: rd = 1 if rs1 < imm, else 0. `slti` compares as signed numbers, `sltiu` as unsigned. The immediate is sign-extended in both.

How it works: with a0 = 0xffffffffffffffff, `slti t0, a0, 0x0` gives 1 (it is -1, below 0), while `sltiu t0, a0, 0x1` gives 0 (it is the biggest unsigned number).

For: turning a comparison into a 0 / 1 value you can store or add up, instead of branching.

Pseudo:
```
seqz rd, rs   ->  sltiu rd, rs, 0x1     # is it zero?
```

Watch out: `sltiu` sign-extends the immediate and then compares unsigned, so `sltiu t0, t1, -0x1` compares with 0xffffffffffffffff: true for every value except that one.

Related: slt, sltu, blt, bltu, encodings#Register-immediate arithmetic

Example:
```
slti  t0, a0, 0x0        # t0 = 1 if a0 is negative
sltiu t1, a1, 0x1        # t1 = 1 if a1 == 0
```

## andi ori xori - Bitwise with an immediate

*I-type, RV64I*

Does: rd = rs1 & imm, rs1 | imm, or rs1 ^ imm, bit by bit. The 12-bit immediate is sign-extended first.

How it works: with a0 = 0x12345678, `andi t0, a0, 0xff` keeps the low byte: 0x78. `ori t0, t0, 0x100` then sets bit 8: 0x178.

For: masks.
- `andi` keeps chosen bits and clears the rest;
- `ori` sets bits;
- `xori` flips bits.

Pseudo:
```
not rd, rs   ->  xori rd, rs, -0x1
```

Watch out: because of sign extension, immediates 0x800 to 0xfff can't be written; -0x800 to -0x1 have all the high bits set. `andi t0, t0, -0x8` clears the low 3 bits (rounds down to a multiple of 8).

Related: and, or, xor, encodings#Register-immediate arithmetic

Example:
```
andi t0, a0, 0xff        # keep the low byte
xori t1, t1, -0x1        # flip every bit
```

## slli srli srai - Shift by a constant

*I-type (shift), RV64I*

Does: shifts rs1 by shamt (0 to 0x3f) bits.
- `slli`: left, filling with zeros from the right.
- `srli`: right (logical), filling with zeros from the left.
- `srai`: right (arithmetic), copying the sign bit in from the left.

How it works: with t1 = 0xfffffffffffffff0 (-0x10):
- `srli t0, t1, 0x4` gives 0x0fffffffffffffff (a huge positive number);
- `srai t0, t1, 0x4` gives 0xffffffffffffffff (-0x1, the sign kept).

For:
- multiplying or dividing by powers of two;
- turning an array index into a byte offset: `slli t0, t0, 0x3` for 8-byte elements;
- packing and unpacking bit fields.

Watch out: `srai` rounds toward minus infinity: -0x5 >> 1 is -0x3, while dividing -5 by 2 in C (or with `div`) gives -2.

Related: sll, srl, sra, slliw, encodings#Register-immediate arithmetic

Example:
```
slli t0, t1, 0x3         # t0 = t1 * 8
srai t2, t2, 0x1         # t2 / 2, keeping the sign
```

## add sub - Add, subtract

*R-type, RV64I*

Does: rd = rs1 + rs2, or rd = rs1 - rs2, on all 64 bits.

How it works: overflow wraps around and nothing records it; there are no flags. 0x0 - 0x1 gives 0xffffffffffffffff, which is -1 as a signed number.

For: arithmetic on two registers, and adding an offset to a base address.

Pseudo:
```
neg rd, rs   ->  sub rd, zero, rs
```

Watch out: the same instruction serves signed and unsigned numbers; the bits come out the same either way. Lesson 02 shows the wrap-around.

Related: addi, addw, subw, encodings#Register-register arithmetic

Example:
```
add a0, a0, t2           # sum += number
sub t0, t1, t2
```

## slt sltu - Set if less than

*R-type, RV64I*

Does: rd = 1 if rs1 < rs2, else 0. `slt` treats both as signed numbers, `sltu` as unsigned.

How it works: 0xffffffffffffffff is -1 to `slt` and the biggest number to `sltu`, so with t0 = 0xffffffffffffffff and t1 = 0x1:
- `slt a0, t0, t1` gives 1 (-1 < 1);
- `sltu a0, t0, t1` gives 0.

For: comparisons that give a value instead of a jump, e.g. counting how many items are smaller.

Pseudo:
```
snez rd, rs   ->  sltu rd, zero, rs
sltz rd, rs   ->  slt  rd, rs, zero
sgtz rd, rs   ->  slt  rd, zero, rs
```

Watch out: pick signed or unsigned to match the data. Addresses are always unsigned. Lesson 06 compares both.

Related: slti, sltiu, blt, bltu, encodings#Register-register arithmetic

Example:
```
slt  t0, a0, a1          # a0 < a1 as signed numbers?
sltu t1, a0, a1          # ... as unsigned numbers?
```

## and or xor - Bitwise on two registers

*R-type, RV64I*

Does: rd = rs1 & rs2, rs1 | rs2, or rs1 ^ rs2, bit by bit.

How it works: `xor` gives 0 exactly where the bits are the same, so `xor t0, a0, a1` is 0 if a0 == a1.

For: masks that don't fit an immediate, combining flags, comparing bit patterns.

Related: andi, ori, xori, encodings#Register-register arithmetic

Example:
```
and t0, t1, t2
xor t3, a0, a1           # 0 if a0 == a1
```

## sll srl sra - Shift by a register

*R-type, RV64I*

Does: like `slli` / `srli` / `srai`, but the shift amount comes from rs2. Only the low 6 bits of rs2 are used (0 to 0x3f).

For: shifts by an amount known only while running, e.g. building the mask 1 << n.

Watch out: shifting by 0x40 is shifting by 0, since only the low 6 bits of rs2 count.

Related: slli, srli, srai, sllw, encodings#Register-register arithmetic

Example:
```
addi t0, zero, 0x1
sll  t0, t0, a0          # t0 = 1 << a0
```

## addiw slliw srliw sraiw addw subw sllw srlw sraw - 32-bit word operations

*I-type and R-type, RV64I*

Does: the same as the instruction without the `w`, but on the low 32 bits only. The 32-bit result is then sign-extended to fill all 64 bits of rd. Shift amounts are 0 to 0x1f.

How it works: with t0 = 0x7fffffff (the largest 32-bit int):
- `addi  t0, t0, 0x1` gives 0x0000000080000000 (fine in 64 bits);
- `addiw t0, t0, 0x1` gives 0xffffffff80000000: the 32-bit result 0x80000000 has bit 31 set, so it becomes negative, exactly like C's `int` overflowing.

For: C's `int` (32-bit) arithmetic on a 64-bit machine. `li` also uses `addiw` for some constants.

Pseudo:
```
sext.w rd, rs   ->  addiw rd, rs, 0x0
negw   rd, rs   ->  subw  rd, zero, rs
```

Watch out: the result is always sign-extended, even for `srliw`: `srliw t0, t0, 0x0` on 0x80000000 gives 0xffffffff80000000. Lesson 10 shows this.

Related: addi, add, sub, slli, sll, encodings#32-bit word arithmetic

Example:
```
addiw t0, t0, 0x1        # 32-bit add
addw  a0, a0, a1
```

## mul - Multiply

*R-type, M extension*

Does: rd = the low 64 bits of rs1 * rs2.

How it works: multiplying two 64-bit numbers gives up to 128 bits; `mul` keeps the low half and the high half is dropped, so a result that doesn't fit wraps around, like `add`. With t0 = 0x6 and t1 = 0x7, `mul a0, t0, t1` gives 0x2a (42).

For: everyday multiplication: array index times element size (when it isn't a power of two), area, scaling.

Watch out:
- The low half is the same whether the numbers are signed or unsigned, so there is only one `mul`. The high half differs: see `mulh`.
- A product that needs more than 64 bits silently wraps: 2^40 * 2^40 gives 0x0. Use `mulh` to see the part that didn't fit.

Related: mulh mulhsu mulhu, mulw, slli (multiplying by a power of two), encodings#M extension: multiply and divide

Example:
```
li    t0, 6
li    t1, 7
mul   a0, t0, t1         # a0 = 0x2a (42)
li    t2, 1
slli  t2, t2, 40         # t2 = 2^40
mul   t3, t2, t2         # 2^80 doesn't fit: the low half is 0x0
```

## mulh mulhsu mulhu - High half of a multiply

*R-type, M extension*

Does: rd = the high 64 bits of the 128-bit product rs1 * rs2. The three differ in how they read the operands:
- `mulh`: signed x signed.
- `mulhsu`: rs1 signed x rs2 unsigned.
- `mulhu`: unsigned x unsigned.

How it works: a register holds 64 bits, so the 128-bit product comes in two halves, each with its own instruction:
| high 64 bits | low 64 bits |
|---|---|
| mulh | mul |
Think of 2-digit decimal registers. 99 * 99 = 9801: the low half (`mul`) is 01, the high half (`mulh`) is 98, the part that didn't fit. Nothing overflows: `mul` and `mulh` together hold the whole product.

In binary: 2^40 * 2^40 = 2^80. `mul` gives 0x0 and `mulhu` gives 0x10000 (bit 80 - 64 = bit 16).

Signedness only changes the high half. With both operands 0xffffffffffffffff:
| Instruction | Reads the operands as | Product | Result |
|---|---|---|---|
| mulh | -1 * -1 | 1 | high half 0x0 |
| mulhsu | -1 * (2^64 - 1) | -(2^64 - 1) | high half 0xffffffffffffffff |
| mulhu | (2^64 - 1) * (2^64 - 1) | 2^128 - 2^65 + 1 | high half 0xfffffffffffffffe |
| mul | (all three) | | low half 0x1 |
Lesson 15 shows the wrap-around and both high halves.

For:
- Detecting overflow: the product fits in 64 bits only if the high half is just the sign extension of the low half (all zeros, or all ones for a negative result).
- Full 128-bit products for big numbers (cryptography, arbitrary precision). `mulhsu` is for a signed top word times an unsigned lower word.
- Dividing by a constant without `div`: compilers turn x / 10 into `mulhu` by about 2^64 / 10, then a shift, which is much faster.
- Fixed-point math, where the useful result sits across the two halves.

Watch out: there are no 32-bit (W) forms of these.

Related: mul, div divu rem remu, encodings#M extension: multiply and divide

Example:
```
li    t2, 1
slli  t2, t2, 40         # t2 = 2^40
mul   t3, t2, t2         # low half of 2^80:  0x0
mulhu t4, t2, t2         # high half of 2^80: 0x10000 (2^16)
li    t5, -1             # 0xffffffffffffffff
mulh  s2, t5, t5         # -1 * -1 = 1: high half 0x0
mulhu s3, t5, t5         # (2^64 - 1)^2: high half 0xfffffffffffffffe
```

## div divu rem remu - Divide and remainder

*R-type, M extension*

Does: `div` / `divu`: rd = rs1 / rs2. `rem` / `remu`: rd = the remainder. Without `u` the numbers are signed, with `u` unsigned.

How it works: signed division rounds toward zero, as in C, and the remainder takes the sign of the dividend:
| Division | Quotient | Remainder | Note |
|---|---|---|---|
| 7 / 2 | 3 | 1 | |
| -7 / 2 | -3 | -1 | not -4 remainder 1 |
| 7 / -2 | -3 | 1 | |
dividend = divisor * quotient + remainder always holds.

Division never traps. Two cases have no real answer, so the spec defines one:
| Case | div / divu | rem / remu |
|---|---|---|
| divide by zero | all ones (-1 / 2^64-1) | the dividend |
| -2^63 / -1 (div only) | the dividend (-2^63) | 0 |
The second case is overflow: the smallest i64 is -2^63 (0x8000000000000000, `min(i64)` in Odin), but the largest is 2^63 - 1, so +2^63 does not fit. Two's complement has one more negative number than positive ones. Many CPUs (x86) crash on this division; RISC-V gives the dividend back. Software that cares checks the divisor first. Lesson 15 runs each of these cases.

For: averages, converting numbers to decimal digits (`remu` by 10, `divu` by 10), wrapping an index around a buffer (`remu` by its size).

Watch out:
- Division is slow on real hardware (tens of cycles); compilers avoid it for constants (see `mulh`) and powers of two (`srli` / `srai`).
- `srai` by 1 is not the same as `div` by 2 for negative numbers: -7 >> 1 is -4, -7 / 2 is -3.

Related: mul, mulh mulhsu mulhu, divw, two's-complement, encodings#M extension: multiply and divide

Example:
```
li   t0, 42
li   t1, 5
div  a0, t0, t1          # 0x8
rem  a1, t0, t1          # 0x2: 42 = 5 * 8 + 2

li   t0, -7
li   t1, 2
div  s4, t0, t1          # -3, rounded toward zero (not -4)
rem  s5, t0, t1          # -1: -7 = 2 * -3 + -1

divu s6, t0, zero        # divide by zero: all ones, no trap
rem  s7, t0, zero        # divide by zero: the dividend, -7

li   t2, 1
slli t2, t2, 63          # -2^63, the smallest i64
li   t3, -1
div  s8, t2, t3          # overflow: the dividend, -2^63
rem  s9, t2, t3          # overflow: 0x0
```

## mulw divw divuw remw remuw - 32-bit multiply and divide

*R-type, M extension (RV64 only)*

Does: like `mul`, `div`, `divu`, `rem`, `remu`, but on the low 32 bits of the operands; the 32-bit result is then sign-extended to 64 bits, like every W instruction.

How it works:
- `mulw` with 0x10000 * 0x10000 = 2^32: the low 32 bits are 0, so the result is 0x0.
- Only the low 32 bits of the operands count: `divw` of 0x100000006 by 3 divides 6 by 3 = 0x2.
- The special cases are the 32-bit versions: divide by zero gives all ones; -2^31 / -1 gives -2^31 (0xffffffff80000000).
- Even `divuw` sign-extends its result: 2^32 - 1 becomes 0xffffffffffffffff.

For: C's 32-bit `int` and `unsigned` arithmetic on a 64-bit machine.

Related: mul, div divu rem remu, addiw slliw srliw sraiw addw subw sllw srlw sraw, encodings#M extension: multiply and divide

Example:
```
mulw a0, a0, a1          # 32-bit int multiply
divw a2, a0, a1
```

## lb lh lw ld lbu lhu lwu - Load from memory

*I-type, RV64I*

Does: rd = the value at address rs1 + imm.
- Size: `b` = 1 byte, `h` = 2 bytes (half word), `w` = 4 bytes (word), `d` = 8 bytes (double word).
- Without `u` the value is sign-extended to 64 bits; with `u` it is zero-extended. `ld` loads all 64 bits, so it has no `u` form.

How it works: `lw t2, 0(t0)` with t0 = 0x80001000:
1. The address is t0 + 0x0 = 0x80001000.
2. The 4 bytes there are 0a 00 00 00. RISC-V is little-endian (lowest byte first), so they read as 0x0000000a.
3. Bit 31 is 0, so sign extension adds zeros: t2 = 0xa.

With the byte 0xff in memory, `lb` gives 0xffffffffffffffff (-1) and `lbu` gives 0xff.

For: reading variables, array elements and struct fields, and restoring registers saved on the stack. RISC-V only computes on registers, so every value in memory is loaded first.

Watch out:
- Pick the signed or unsigned form to match the data (lesson 07 shows both).
- The address is rs1 + imm; the register holds an address, not the value.

Related: sb sh sw sd, la, auipc, encodings#Loads and stores

Example:
```
lw  t2, 0(t0)            # t2 = the 32-bit number at address t0
ld  ra, 8(sp)            # restore the return address from the stack
lbu t6, 0(t4)            # one byte, 0x0 to 0xff
```

## sb sh sw sd - Store to memory

*S-type, RV64I*

Does: writes the low 1, 2, 4 or 8 bytes of rs2 to address rs1 + imm.

How it works: `sw a0, 0(t3)` with a0 = 0x6e and t3 = 0x80001010 writes the 4 bytes 6e 00 00 00 at 0x80001010 (lowest byte first).

For: writing variables and array elements, and saving registers on the stack, e.g. `ra` before calling another function.

Watch out:
- The operand order looks backwards: the value comes first, the address second.
- A store changes no register, so the Registers panel stays the same; watch the Memory tab instead.

Related: lb lh lw ld, encodings#Loads and stores

Example:
```
sw a0, 0(t3)             # store the sum into the variable at t3
sd ra, 8(sp)             # save the return address on the stack
```

## beq bne - Branch if equal, not equal

*B-type, RV64I*

Does: if rs1 == rs2 (`beq`) or rs1 != rs2 (`bne`), jump to pc + offset; otherwise go on to the next instruction.

How it works: the offset is stored in the instruction relative to the branch itself, reaching +/- 4 KiB. A loop branching back 0x10 bytes from 0x80000020 jumps to 0x80000010.

For: `if` statements and loops.

Pseudo:
```
beqz rs, label  ->  beq rs, zero, label
bnez rs, label  ->  bne rs, zero, label
```

Watch out: RISC-V has no condition flags: every branch compares two registers itself.

Related: blt bge bltu bgeu, jal, encodings#Jumps and branches

Example:
```
bnez t1, loop            # repeat while t1 != 0
```

## blt bge bltu bgeu - Branch on less than / greater or equal

*B-type, RV64I*

Does: jump to pc + offset if rs1 < rs2 (`blt`) or rs1 >= rs2 (`bge`), comparing as signed numbers. `bltu` / `bgeu` compare as unsigned.

How it works: with t0 = 0xffffffffffffffff and t1 = 0x1, `blt t0, t1` jumps (-1 < 1) but `bltu t0, t1` does not.

For: counting loops (`blt i, n, loop`), range checks, and comparing addresses (always unsigned).

Pseudo: the other comparisons swap the operands or use zero:
```
bgt  a, b, label  ->  blt  b, a, label
ble  a, b, label  ->  bge  b, a, label
bltz rs, label    ->  blt  rs, zero, label
```

Related: beq bne, slt sltu, encodings#Jumps and branches

Example:
```
blt  t0, t1, loop        # while t0 < t1
bgeu a0, a1, done        # unsigned: a0 >= a1
```

## jal - Jump and link

*J-type, RV64I*

Does: rd = pc + 4 (the return address), then jump to pc + offset. The offset reaches +/- 1 MiB.

How it works: `jal ra, square` at 0x80000010: ra = 0x80000014, and execution continues at `square`. When `square` ends with `ret`, it jumps back to 0x80000014.

For: calling a function: `jal ra, function`. With rd = zero it is a plain jump.

Pseudo:
```
j label     ->  jal zero, label
jal label   ->  jal ra, label
call label  ->  jal ra, label    # when the linker finds it close enough
```

Watch out: a function that calls another overwrites `ra`, so it must save its own `ra` first, usually on the stack. Lessons 08 and 09.

Related: jalr, auipc, ret, encodings#Jumps and branches

Example:
```
jal ra, square           # call square; it returns to the next instruction
```

## jalr - Jump and link register

*I-type, RV64I*

Does: rd = pc + 4, then jump to (rs1 + imm) with bit 0 cleared. The target comes from a register.

How it works: `jalr zero, 0(ra)` with ra = 0x80000014 jumps to 0x80000014 and saves nothing (rd = zero).

For: returning from a function, calling through a function pointer, and far calls together with `auipc`.

Pseudo:
```
ret     ->  jalr zero, 0(ra)
jr rs   ->  jalr zero, 0(rs)
```

Watch out: the target is worked out before rd is written, so `jalr ra, 0(ra)` works.

Related: jal, auipc, ret, encodings#Jumps and branches

Example:
```
jalr zero, 0(ra)         # ret: back to the caller
```

## lr.w lr.d sc.w sc.d - Load-reserved, store-conditional

*R-type (atomic), A extension*

Does:
- `lr.w` / `lr.d`: rd = the value at address rs1 (sign-extended for .w), and reserve that address.
- `sc.w` / `sc.d`: store rs2 at address rs1, but only if the reservation still holds. rd = 0 if it stored, 1 if it didn't. Either way the reservation is used up.

How it works: the pair turns any read-modify-write into an atomic one. Read with `lr`, compute, write with `sc`; if `sc` fails, something may have touched the value in between, so go back and try again:
```
retry:
    lr.w  t0, (a0)           # read and reserve
    addi  t0, t0, 0x1        # compute
    sc.w  t1, t0, (a0)       # write if nothing came in between
    bnez  t1, retry          # t1 = 1: it failed, try again
```
The reservation breaks when another hart writes the reserved memory, on a trap, or at the next `sc`. The address has no offset, and must be aligned to the size (4 or 8), or it traps.

For: operations no single AMO does, such as compare-and-swap ("if it is still 5, make it 9"), the building block of lock-free data structures. Lesson 18 does one.

Watch out:
- An `sc` can fail even when nothing seems to have happened: on one hart, a trap between `lr` and `sc` is enough. Always loop.
- Keep the code between `lr` and `sc` short and simple (no other loads, stores or calls); the spec only promises eventual success for short loops like the one above.
- `sc` writes rd: 0 means success, the opposite of most "true" flags.

Related: amoswap.w amoadd.w (the AMOs), locks, memory-ordering, fence, encodings#A extension: atomics

Example:
```
cas:
    lr.w  t3, (s1)           # load and reserve
    bne   t3, t1, done       # not the expected value: give up
    sc.w  t4, t2, (s1)       # store the new value if still reserved
    bnez  t4, cas            # someone touched it: try again
done:
```

## amoswap.w amoswap.d amoadd.w amoadd.d amoand.w amoand.d amoor.w amoor.d amoxor.w amoxor.d amomin.w amomin.d amomax.w amomax.d amominu.w amominu.d amomaxu.w amomaxu.d - Atomic memory operations

*R-type (atomic), A extension*

Does: in one indivisible step: rd = the value in memory at rs1, then memory = (that value) op rs2.
- `amoswap`: memory = rs2 (exchange).
- `amoadd`, `amoand`, `amoor`, `amoxor`: memory = old +, &, |, ^ rs2.
- `amomin` / `amomax`: the smaller / larger, signed; `amominu` / `amomaxu`: unsigned.
- `.w` works on 32 bits (the old value is sign-extended into rd), `.d` on 64.

How it works: `amoadd.w a1, t1, (t0)` with 41 in memory and t1 = 1: a1 = 41 and memory = 42. Nothing, not another hart nor an interrupt, can come between the read and the write, so two harts adding at the same time never lose an update. The address has no offset and must be aligned to the size, or it traps (Store_Address_Misaligned).

For:
- Counters shared between harts: `amoadd`.
- Locks: `amoswap` a 1 in; getting a 0 back means you took the lock (xv6's acquire). Release by swapping 0 in.
- Setting and clearing flag bits: `amoor` / `amoand`.
- Keeping a running maximum or minimum: `amomax` / `amomin`.

Watch out:
- With rd = zero the old value is thrown away: `amoswap.w zero, zero, (a0)` just stores 0 atomically (a lock release).
- The suffixes `.aq` / `.rl` / `.aqrl` (e.g. `amoswap.w.aq`) add memory ordering: see memory-ordering. They don't change what the instruction computes.
- Atomics are for RAM. Each region of a real memory map says whether it supports them, and device regions often don't. This emulator raises an access fault for lr, sc or an AMO on a device address (Store_Access_Fault, or Load_Access_Fault for lr).

Related: lr.w lr.d sc.w sc.d, locks, memory-ordering, add sub, mmio, encodings#A extension: atomics

Example:
```
amoadd.w     a1, t1, (t0)    # atomic counter += t1; a1 = the old value
amoswap.w.aq t2, t1, (s0)    # take a lock: t2 = 0 if it was free
amoswap.w.rl zero, zero, (s0)  # release it
```

## fence - Memory ordering fence

*I-type, RV64I*

Does: makes memory accesses before the fence visible to other harts and devices before the accesses after it. The operands say which kinds are ordered: device input / output (i, o) and memory reads / writes (r, w).

For: multi-core code and device drivers, e.g. writing data before setting the flag that says it is ready.

Watch out: this emulator has one hart that does everything in order, so `fence` does nothing here. It matters on real multi-core CPUs and with devices; see memory-ordering for why.

Related: fence.i, memory-ordering, locks, encodings#Fences and system

Example:
```
fence rw, rw
```

## fence.i - Instruction fence (Zifencei)

*I-type, Zifencei*

Does: makes instructions fetched after it see earlier stores to memory.

For: code that writes code (loaders, JIT compilers). A CPU with an instruction cache might otherwise still run the old bytes.

Watch out: this emulator has no instruction cache, so it does nothing here.

Related: fence, encodings#Fences and system

Example:
```
fence.i
```

## ecall - Environment call

*I-type, RV64I (privileged behaviour)*

Does: raises an environment-call trap: the CPU jumps to the trap handler in mtvec.

How it works:
1. mepc = the address of the `ecall` itself.
2. mcause = 0xb (`Ecall_From_M_Mode`), or 0x8 / 0x9 from user / supervisor mode.
3. mstatus saves the interrupt-enable bit and the privilege level.
4. pc = the handler address in mtvec.

For: asking more privileged code to do something. A user program asks the kernel (a system call, e.g. xv6's `write`), the kernel asks the firmware. By convention the request number goes in `a7` and the arguments in `a0` to `a5`.

Watch out:
- The handler must add 4 to mepc before `mret`, or it returns to the `ecall` and runs it again.
- With no handler (mtvec's base address is 0) this emulator stops instead. Lessons 12 and 13.

Related: mret, ebreak, mtvec, system-call, encodings#Fences and system

Example:
```
addi a7, zero, 0x10      # system call number: 16 is xv6's write
ecall
```

## ebreak - Breakpoint

*I-type, RV64I (privileged behaviour)*

Does: raises a `Breakpoint` trap (mcause = 0x3).

For: debuggers place it where execution should stop. The programs here end with it: with no trap handler set up, the emulator stops, and a0 holds the result.

Related: ecall, encodings#Fences and system

Example:
```
ebreak                   # a0 = result; the program ends here
```

## mret - Return from a machine-mode trap

*I-type, privileged*

Does: returns from a trap handler to the code that was interrupted.

How it works:
1. pc = mepc.
2. The privilege level goes back to the one saved in mstatus.MPP.
3. Interrupts go back to how they were: MIE = MPIE, then MPIE = 1.
4. MPP = the least privileged mode.

For: the last instruction of a trap handler. Also how a kernel starts a user program the first time: set mepc to the program and MPP to user mode, then `mret`.

Watch out:
- After an `ecall`, mepc points at the `ecall` itself; add 4 first or it runs again. Lesson 13.
- A plain `jr` to mepc + 4 gets back to the right place but leaves interrupts off and the privilege level raised. See trap-return.

Related: ecall, mepc, mstatus, trap-return, system-call, encodings#Fences and system

Example:
```
csrr t0, mepc
addi t0, t0, 0x4         # skip the ecall
csrw mepc, t0
mret
```


## wfi - Wait for interrupt

*I-type, privileged*

Does: tells the hart it has nothing to do until an interrupt arrives. On real hardware the hart can stop and save power; the next interrupt (even one that is pending but not enabled) wakes it, and it carries on after the wfi.

How it works: wfi is only a hint. The spec allows a hart to treat it as a nop, and then the software's own loop does the waiting:
```
idle:
wfi                      # sleep until something happens
j     idle               # (an interrupt handler ran; look for work again)
```

For: an OS's idle loop: xv6's scheduler runs wfi when no process is ready, instead of spinning at full power.

Emulator: a nop. Time counts steps here (see emulator-time), so a loop around wfi still reaches its timer interrupt. Jumping the clock ahead to the next alarm instead can come later, as a speed-up.

Watch out: wfi doesn't turn interrupts on. If none can be taken (mie or mstatus.MIE off), a real hart may sleep for ever, or keep going: code mustn't rely on either.

Related: interrupt, clint, emulator-time, encodings#Fences and system
## csrrw csrrwi - CSR read and write

*I-type (CSR), Zicsr*

Does: in one step, rd = the old value of the CSR, then the CSR = rs1 (or a 5-bit constant for `csrrwi`). If rd is zero the CSR is not read at all.

How it works: with mscratch = 0x55 and t1 = 0x7, `csrrw t0, mscratch, t1` gives t0 = 0x55 and mscratch = 0x7.

For: setting a CSR to a value, e.g. the trap handler address in mtvec, or swapping a register with a CSR, e.g. with mscratch at the start of a trap handler.

Pseudo:
```
csrw  csr, rs  ->  csrrw  zero, csr, rs
csrwi csr, n   ->  csrrwi zero, csr, n
```

Watch out: CSRs keep only the bits they support (WARL: "write any, read legal"). Reading back can give something else than what was written; here mstatus.MPP ignores supervisor mode (0b01), which the hart doesn't have yet. The step details say when this happens.

Related: csrrs, csrrc, mret, encodings#CSR instructions

Example:
```
la   t0, handler
csrw mtvec, t0           # traps now jump to handler
```

## csrrs csrrsi - CSR read and set bits

*I-type (CSR), Zicsr*

Does: rd = the old value of the CSR, then set the CSR bits that are 1 in rs1 (or in the constant). With rs1 = zero (or constant 0) nothing is written, so it is a pure read.

How it works: with mscratch = 0x55, `csrrsi t2, mscratch, 0xa` gives t2 = 0x55 and mscratch = 0x55 | 0xa = 0x5f.

For: reading a CSR (the most common use) and turning on single bits, such as mstatus.MIE.

Pseudo:
```
csrr rd, csr   ->  csrrs  rd, csr, zero
csrs csr, rs   ->  csrrs  zero, csr, rs
csrsi csr, n   ->  csrrsi zero, csr, n
```

Watch out: reading some CSRs means something by itself: `minstret` counts the instructions finished so far.

Related: csrrw, csrrc, encodings#CSR instructions

Example:
```
csrr  t0, mcause         # why did we trap?
csrsi mstatus, 0x8       # set MIE: interrupts on
```

## csrrc csrrci - CSR read and clear bits

*I-type (CSR), Zicsr*

Does: rd = the old value of the CSR, then clear the CSR bits that are 1 in rs1 (or in the constant). With rs1 = zero (or constant 0) nothing is written.

How it works: with mscratch = 0x5f, `csrrci t3, mscratch, 0xf` gives t3 = 0x5f and mscratch = 0x5f & ~0xf = 0x50.

For: turning off single bits, e.g. disabling interrupts (mstatus.MIE) around code that must not be interrupted.

Pseudo:
```
csrc  csr, rs  ->  csrrc  zero, csr, rs
csrci csr, n   ->  csrrci zero, csr, n
```

Related: csrrw, csrrs, encodings#CSR instructions

Example:
```
csrci mstatus, 0x8       # clear MIE: interrupts off
```
