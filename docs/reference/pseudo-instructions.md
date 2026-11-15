# Pseudo-instructions: shorthand the assembler expands

A pseudo-instruction is a name the assembler accepts but the CPU does not
have. The assembler replaces it with one or more real instructions.

That is why the Source tab (what you wrote) and the Disassembly tab (what
is in memory) can look different: the disassembler here prints the real
instructions, so the Disassembly tab always shows the expansion. One
source line can then take several presses of Next.

The debugger's Docs window shows the entry for a pseudo-instruction when
the source line being run uses one, above the entry for the real
instruction. The expansions below were checked with the GNU assembler
(`riscv64-elf-as`, RV64).

Format of an entry (also read by the debugger): a `## names - title`
heading, an italic line, then sections that start with a label such as
`Does:` or `Becomes:`. A section continues with plain lines, `- ` bullets
and fenced code blocks until the next label. The text is plain ASCII,
since the debugger's font only has ASCII characters.

## li - Load immediate

*pseudo-instruction: 1 to 8 real instructions*

Does: puts a constant (any 64-bit number) into a register.

Becomes: as few instructions as the value needs.
- Fits in 12 signed bits (-0x800 to 0x7ff): one `addi` from zero.
- Fits in 32 signed bits: `lui` for the upper 20 bits, then `addiw` for the lower 12.
- Anything bigger: a chain of `lui`, `addiw`, `slli` and `addi`, up to 8 instructions.
```
li t0, 5             ->  addi  t0, zero, 0x5
li t1, 0x12345678    ->  lui   t1, 0x12345
                         addiw t1, t1, 0x678
li t3, -1            ->  addi  t3, zero, -0x1
```

How it works: for 0x12345800 the lower 12 bits are 0x800, which `addiw` reads as a negative number (-0x800). So the assembler starts one higher in the upper part and subtracts:
```
lui   t5, 0x12346        # t5 = 0x12346000
addiw t5, t5, -0x800     # t5 = 0x12346000 - 0x800 = 0x12345800
```
0x80000000 does not fit in 32 signed bits (as a signed 32-bit number it is negative), so `lui` alone would give 0xffffffff80000000. The assembler builds it another way:
```
addiw t6, zero, 0x1      # t6 = 1
slli  t6, t6, 0x1f       # t6 = 1 << 31 = 0x80000000
```

For: any constant, without working out the split yourself.

Watch out:
- One `li` can be several instructions, so Next may stay on the same source line for a few presses.
- Lesson 04 builds constants with `lui` + `addi` by hand, then lets `li` do it.

Related: lui, addi, addiw, la

Example:
```
li a0, 0x6e              # a0 = 110
li t0, 0x10000000        # a device address: lui t0, 0x10000
```

## la lla - Load address

*pseudo-instruction: 2 real instructions*

Does: puts the address of a label (a variable, an array, a function) into a register. It loads the address, not the value stored there.

Becomes: `auipc` + `addi`.
```
la t4, x    ->  auipc t4, 0x1          # t4 = pc + 0x1000
                addi  t4, t4, -0x40    # t4 = t4 - 0x40 = address of x
```

How it works: the assembler does not know where the program will be loaded, so it does not use the absolute address. It works out how far the label is from the `auipc` instruction, and splits that distance in two:
1. The `auipc` sits at 0x80000040 and `x` is at 0x80001000, so the distance is 0x80001000 - 0x80000040 = 0xfc0.
2. The lower 12 bits of 0xfc0 are 0xfc0. `addi` reads 12 bits as signed, so 0xfc0 means -0x40.
3. To make up for the negative lower part, the upper part is one higher: 0x1, so `auipc` adds 0x1 << 12 = 0x1000.
4. `auipc t4, 0x1` gives 0x80000040 + 0x1000 = 0x80001040.
5. `addi t4, t4, -0x40` gives 0x80001040 - 0x40 = 0x80001000, the address of `x`.

The linker fills in the two numbers once it knows where everything is (the `%pcrel_hi` / `%pcrel_lo` relocations). Because only the distance matters, the code still works if the whole program is loaded somewhere else.

For:
- walking through an array or reading a variable: `la` the address, then `lw` / `ld` from it;
- putting a function's address somewhere, e.g. a trap handler into mtvec.

Watch out:
- `la` gives the address. To get the value, load from it: `la t0, total` then `lw t1, 0(t0)`.
- Pressing Next twice stays on the `la` line: once for `auipc`, once for `addi`.
- In position-independent code (`-fPIC`), `la` instead loads the address from a table (`auipc` + `ld`). `lla` always means the `auipc` + `addi` form. The programs here are not position-independent, so `la` and `lla` are the same.

Related: auipc, addi, lw, ld

Example:
```
la  t0, numbers          # t0 = address of the array
lw  t1, 0(t0)            # t1 = numbers[0]
lw  t2, 4(t0)            # t2 = numbers[1] (4 bytes further)
```

## mv - Copy a register

*pseudo-instruction: 1 real instruction*

Does: copies one register into another.

Becomes:
```
mv rd, rs   ->  addi rd, rs, 0x0
```

How it works: adding 0 leaves the value unchanged, so `addi` with immediate 0 is a copy. The base ISA has no separate copy instruction because this one does the job.

For: keeping a value before it is overwritten, e.g. moving a function's result out of a0 before the next call puts its own result there.

Related: addi

Example:
```
mv s0, a0                # keep the result in a saved register
```

## nop - Do nothing

*pseudo-instruction: 1 real instruction*

Does: nothing, except move on to the next instruction.

Becomes:
```
nop   ->  addi zero, zero, 0x0       # encoded 0x00000013
```

How it works: it writes to x0, and writes to x0 are thrown away.

For: padding code to an alignment, and leaving a spot to place a breakpoint or patch later.

Related: addi

Example:
```
nop
```

## not neg negw sext.w - Flip, negate, sign-extend

*pseudo-instructions: 1 real instruction each*

Does: one-operand operations.
- `not`: flips every bit.
- `neg`: negates (0 - value).
- `negw`: negates the low 32 bits and sign-extends.
- `sext.w`: keeps the low 32 bits and sign-extends them to 64.

Becomes:
```
not    rd, rs   ->  xori  rd, rs, -0x1    # x ^ all ones = flipped bits
neg    rd, rs   ->  sub   rd, zero, rs    # 0 - x
negw   rd, rs   ->  subw  rd, zero, rs
sext.w rd, rs   ->  addiw rd, rs, 0x0     # 32-bit add of 0, then sign-extend
```

For: the base ISA leaves these out because a two-operand instruction with zero or -1 does the same.

Watch out: `sext.w` copies bit 31 into the upper 32 bits: 0x00000000ffffffff becomes 0xffffffffffffffff (-1).

Related: xori, sub, subw, addiw

Example:
```
neg    t0, t1            # t0 = -t1
sext.w a0, a0            # treat a0 as a 32-bit int
```

## seqz snez sltz sgtz - Compare with zero, as 0 or 1

*pseudo-instructions: 1 real instruction each*

Does: sets rd to 1 or 0.
- `seqz`: 1 if rs == 0.
- `snez`: 1 if rs != 0.
- `sltz`: 1 if rs < 0.
- `sgtz`: 1 if rs > 0.

Becomes:
```
seqz rd, rs   ->  sltiu rd, rs, 0x1     # unsigned: only 0 is below 1
snez rd, rs   ->  sltu  rd, zero, rs    # unsigned: 0 < rs unless rs is 0
sltz rd, rs   ->  slt   rd, rs, zero
sgtz rd, rs   ->  slt   rd, zero, rs
```

For: checking a result without branching, e.g. counting how many checks passed (lesson 11 adds up `seqz` results).

Related: sltiu, sltu, slt

Example:
```
addi a1, t4, -0x50       # a1 = 0 if t4 == 0x50
seqz a1, a1              # a1 = 1 if t4 was 0x50, else 0
```

## beqz bnez blez bgez bltz bgtz - Branch on a comparison with zero

*pseudo-instructions: 1 real branch each*

Does: branches by comparing one register with zero.

Becomes: the real branch, with `zero` as the other operand.
```
beqz rs, label  ->  beq rs, zero, label
bnez rs, label  ->  bne rs, zero, label
bltz rs, label  ->  blt rs, zero, label
bgez rs, label  ->  bge rs, zero, label
blez rs, label  ->  bge zero, rs, label   # 0 >= rs
bgtz rs, label  ->  blt zero, rs, label   # 0 <  rs
```

For: loops that count down to zero, and checks such as "stop when the pointer is null".

Related: beq bne, blt bge

Example:
```
loop:
    addi t1, t1, -0x1
    bnez t1, loop            # bne t1, zero, loop
```

## bgt ble bgtu bleu - Branch on greater than / less or equal

*pseudo-instructions: 1 real branch each*

Does: branches on a > b or a <= b (signed, or unsigned with `u`).

Becomes: the opposite comparison with the operands swapped, since a > b is the same as b < a.
```
bgt  a, b, label  ->  blt  b, a, label
ble  a, b, label  ->  bge  b, a, label
bgtu a, b, label  ->  bltu b, a, label
bleu a, b, label  ->  bgeu b, a, label
```

For: writing the comparison the way you think of it. The CPU only has "less than" and "greater or equal"; swapping the operands gives the other two.

Watch out: in the Disassembly tab the two registers appear in the other order.

Related: blt bge bltu bgeu

Example:
```
bgt a0, a1, bigger       # blt a1, a0, bigger
```

## j jr - Jump

*pseudo-instructions: 1 real instruction each*

Does: jumps without saving a return address.

Becomes:
```
j  label  ->  jal  zero, label
jr rs     ->  jalr zero, 0(rs)
```

How it works: `jal` and `jalr` always write the return address to rd. With rd = zero that write is thrown away, which leaves a plain jump.

For:
- `j`: the end of an `if`, the top of a loop.
- `jr`: jumping to an address computed while running, e.g. a jump table.

Related: jal, jalr

Example:
```
    j done                   # skip the else part
```

## call tail - Call a function anywhere

*pseudo-instructions: 2 real instructions, or 1 after linking*

Does: `call f` calls f and saves the return address in `ra`. `tail f` jumps to f without saving one.

Becomes: `auipc` + `jalr`, which reaches anywhere within +/- 2 GiB:
```
call f  ->  auipc ra, %pcrel_hi(f)
            jalr  ra, %pcrel_lo(f)(ra)
tail f  ->  auipc t1, %pcrel_hi(f)
            jalr  zero, %pcrel_lo(f)(t1)
```
When f turns out to be close enough, the linker shrinks the pair to a single `jal` ("relaxation"), as it does in the programs here:
```
call f  ->  jal ra, f
tail f  ->  jal zero, f
```

For:
- `call`: calling a function that might be more than 1 MiB away, the most `jal` can reach.
- `tail`: ending a function by jumping into another one, which then returns straight to our caller ("tail call").

Watch out: `call` overwrites `ra`. A function that calls another must save its own `ra` first, usually on the stack (lesson 09).

Related: jal, jalr, auipc, ret

Example:
```
call sum                 # ra = return address; jump to sum
```

## ret - Return from a function

*pseudo-instruction: 1 real instruction*

Does: goes back to just after the `jal` / `call` that called this function.

Becomes:
```
ret   ->  jalr zero, 0(ra)
```

How it works: the call left the return address in `ra`. `jalr` jumps there, and rd = zero means nothing new is saved.

Watch out: if this function called another one, `ra` was overwritten and must be restored first, usually loaded back from the stack.

Related: jalr, jal, call

Example:
```
ld   ra, 8(sp)           # restore the return address
addi sp, sp, 0x10        # free the stack space
ret
```

## csrr csrw csrs csrc csrwi csrsi csrci - CSR shorthand

*pseudo-instructions: 1 real instruction each*

Does: the everyday CSR operations.
- `csrr`: read a CSR.
- `csrw`: write a CSR.
- `csrs` / `csrc`: set / clear the CSR bits that are 1 in a register.
- `csrwi`, `csrsi`, `csrci`: the same with a 5-bit constant (0 to 0x1f).

Becomes: the full CSR instruction, with zero for the half you don't want.
```
csrr  rd, csr     ->  csrrs  rd, csr, zero    # set no bits = read only
csrw  csr, rs     ->  csrrw  zero, csr, rs    # old value thrown away
csrs  csr, rs     ->  csrrs  zero, csr, rs
csrc  csr, rs     ->  csrrc  zero, csr, rs
csrwi csr, n      ->  csrrwi zero, csr, n
csrsi csr, n      ->  csrrsi zero, csr, n
csrci csr, n      ->  csrrci zero, csr, n
```

How it works: every CSR instruction reads the old value into rd and writes a new value, in one step. Using zero as rd skips the read; using zero as the source of a set or clear skips the write.

Related: csrrw csrrwi, csrrs csrrsi, csrrc csrrci

Example:
```
csrr t0, mhartid         # which hart this is
csrw mscratch, t1        # store t1 in mscratch
```
