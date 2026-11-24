# Instruction encodings

How every instruction is laid out in its 32 bits, the major opcodes,
what the emulator supports, and each instruction's opcode and funct
values. One page; the debugger's Docs window shows it whole. Same format
as instructions.md.

## encodings - Instruction encodings

*formats, opcodes, and every instruction's bits*

Does: every instruction is 32 bits, cut into fields. There are six layouts, called formats; the italic line under each instruction entry's heading names its format (R-type, I-type, ...). The debugger's Encoding tab colours the next instruction's fields.

Fields:
```
 31        25 24   20 19   15 14  12 11         7 6      0
|   funct7   |  rs2  |  rs1  |funct3|     rd     | opcode |  R  two registers: add, sub, mul
|       imm[11:0]    |  rs1  |funct3|     rd     | opcode |  I  immediate: addi, loads, jalr
| imm[11:5]  |  rs2  |  rs1  |funct3|  imm[4:0]  | opcode |  S  stores: sw
|imm[12|10:5]|  rs2  |  rs1  |funct3| imm[4:1|11]| opcode |  B  branches: beq
|             imm[31:12]            |     rd     | opcode |  U  upper immediate: lui, auipc
|     imm[20|10:1|11|19:12]         |     rd     | opcode |  J  jump: jal
```
- opcode (bits 6..0): the instruction's group, the major opcode. Its low two bits are always 11 (other values mark the 16-bit instructions of the C extension).
- rd, rs1, rs2: register numbers, 5 bits each (x0..x31).
- funct3, funct7: which instruction in the group; add and sub differ only in funct7.
- imm: the immediate, a constant inside the instruction, sign-extended to 64 bits when used. imm[4:1|11] lists which immediate bits sit there, left to right.

How it works: the layouts are chosen so a CPU can decode them quickly:
1. rs1, rs2 and rd are always in the same bits, so the registers can be read before the format is known.
2. The immediate's sign bit is always bit 31, so sign extension can start at once.
3. S and B put their immediate bits in the same places as far as they can, and so do U and J. That is why B and J look scrambled: a branch offset is always even, so B has no imm[0], and imm[11] takes its place in bit 7.
A worked example, `addi a0, a0, 1` = 0x00150513:
| Field | Bits | Value | Means |
|---|---|---|---|
| imm[11:0] | 31..20 | 000000000001 | 1 |
| rs1 | 19..15 | 01010 | x10 (a0) |
| funct3 | 14..12 | 000 | addi, in the OP-IMM group |
| rd | 11..7 | 01010 | x10 (a0) |
| opcode | 6..0 | 0010011 | OP-IMM |
The major opcodes:
| opcode | Group | Format | Instructions |
|---|---|---|---|
| 0110111 | LUI | U | lui |
| 0010111 | AUIPC | U | auipc |
| 1101111 | JAL | J | jal |
| 1100111 | JALR | I | jalr |
| 1100011 | BRANCH | B | beq bne blt bge bltu bgeu |
| 0000011 | LOAD | I | lb lh lw ld lbu lhu lwu |
| 0100011 | STORE | S | sb sh sw sd |
| 0010011 | OP-IMM | I | addi slti sltiu xori ori andi slli srli srai |
| 0110011 | OP | R | add sub sll slt sltu xor srl sra or and; the M extension's mul, div, rem |
| 0011011 | OP-IMM-32 | I | addiw slliw srliw sraiw |
| 0111011 | OP-32 | R | addw subw sllw srlw sraw; mulw divw divuw remw remuw |
| 0001111 | MISC-MEM | I | fence fence.i |
| 0101111 | AMO | R | lr sc and the AMOs |
| 1110011 | SYSTEM | I | ecall ebreak mret wfi, and the CSR instructions |

For: reading the Encoding tab, a hex dump or a disassembler's output, and knowing why big constants take two instructions: only 12 bits (I, S) or 20 bits (U) of immediate fit.

Emulator: decode.odin pulls the fields out (opcode, rd, rs1, rs2, funct3, funct7, and imm_i to imm_j, sign-extended); execute.odin picks the group by opcode. `imm` is always sign-extended to 64 bits, and arithmetic wraps modulo 2^64. It runs the RV64I base (all 52 instructions) + M (13) + A (22) + Zifencei + Zicsr + MRET and WFI. 96 in total. Anything else raises Illegal_Instruction. The tables below give each group's opcode and funct values, by the file in emulator/core that runs it.

Watch out:
- immediates are signed: addi's 12 bits go from -2048 to 2047, so 0x800 as an immediate means -2048 (see li, lui).
- the shifts (slli, srli, srai) are I-type, but only the low 6 bits of the immediate are the amount; the top bits pick logical or arithmetic.

### Not supported yet

| Extension | Needed for | Milestone |
|---|---|---|
| SRET, supervisor CSRs | Supervisor mode (xv6's kernel runs there) | Supervisor and user modes |
| `time` CSR (`rdtime`), Sstc's `stimecmp` | xv6's timer | Supervisor and user modes |
| SFENCE.VMA, `satp` | Paging | Sv39 |
| C (compressed 16-bit instructions) | Optional: smaller code | Maybe later |
Notes:
- CSR instructions are I-type whose 12-bit immediate is the CSR address (not sign-extended); the immediate forms put a 5-bit value in the rs1 field.
- ECALL, EBREAK, MRET and WFI have every field fixed, so the emulator matches the whole 32-bit word.
- Unprivileged vs privileged: everything here is from the unprivileged spec except MRET (`privilege.odin`) and WFI (`rv64i_system.odin`, next to ECALL and EBREAK, which share its opcode). SRET and SFENCE.VMA come with supervisor mode and paging.

### Upper immediates (rv64i_upper.odin)

Lui and auipc put a 20-bit immediate into bits 31..12.
| Instruction | Format | Opcode | Effect |
|---|---|---|---|
| LUI rd, imm | U | 0110111 | rd = imm << 12 |
| AUIPC rd, imm | U | 0010111 | rd = pc + (imm << 12) |

### Jumps and branches (rv64i_control.odin)

Jal, jalr and the six branches.
| Instruction | Format | Opcode | funct3 | Effect |
|---|---|---|---|---|
| JAL rd, off | J | 1101111 | | rd = pc + 4; pc += off |
| JALR rd, off(rs1) | I | 1100111 | 000 | rd = pc + 4; pc = (rs1 + off) & ~1 |
| BEQ rs1, rs2, off | B | 1100011 | 000 | if rs1 == rs2: pc += off |
| BNE | B | 1100011 | 001 | if rs1 != rs2 |
| BLT | B | 1100011 | 100 | if rs1 < rs2 (signed) |
| BGE | B | 1100011 | 101 | if rs1 >= rs2 (signed) |
| BLTU | B | 1100011 | 110 | if rs1 < rs2 (unsigned) |
| BGEU | B | 1100011 | 111 | if rs1 >= rs2 (unsigned) |
A jump or taken branch to an address that isn't 4-byte aligned raises `Instruction_Address_Misaligned`.

### Loads and stores (rv64i_load_store.odin)

Every load (I-type) and store (S-type). Address = rs1 + off. A miss on the bus raises `Load_Access_Fault` / `Store_Access_Fault`.
| Instruction | Format | Opcode | funct3 | Effect |
|---|---|---|---|---|
| LB rd, off(rs1) | I | 0000011 | 000 | rd = sign-extend(8-bit load) |
| LH | I | 0000011 | 001 | rd = sign-extend(16-bit load) |
| LW | I | 0000011 | 010 | rd = sign-extend(32-bit load) |
| LD | I | 0000011 | 011 | rd = 64-bit load |
| LBU | I | 0000011 | 100 | rd = zero-extend(8-bit load) |
| LHU | I | 0000011 | 101 | rd = zero-extend(16-bit load) |
| LWU | I | 0000011 | 110 | rd = zero-extend(32-bit load) |
| SB rs2, off(rs1) | S | 0100011 | 000 | store low 8 bits of rs2 |
| SH | S | 0100011 | 001 | store low 16 bits |
| SW | S | 0100011 | 010 | store low 32 bits |
| SD | S | 0100011 | 011 | store 64 bits |

### Register-immediate arithmetic (rv64i_alu.odin)

Arithmetic and logic between a register and a 12-bit immediate, and the shifts by a constant.
| Instruction | Format | Opcode | funct3 | Bits 31..26 | Effect |
|---|---|---|---|---|---|
| ADDI rd, rs1, imm | I | 0010011 | 000 | | rd = rs1 + imm |
| SLTI | I | 0010011 | 010 | | rd = (rs1 < imm) signed ? 1 : 0 |
| SLTIU | I | 0010011 | 011 | | rd = (rs1 < imm) unsigned ? 1 : 0 |
| XORI | I | 0010011 | 100 | | rd = rs1 ^ imm |
| ORI | I | 0010011 | 110 | | rd = rs1 \| imm |
| ANDI | I | 0010011 | 111 | | rd = rs1 & imm |
| SLLI rd, rs1, shamt | I | 0010011 | 001 | 000000 | rd = rs1 << shamt (6-bit) |
| SRLI | I | 0010011 | 101 | 000000 | rd = rs1 >> shamt (logical) |
| SRAI | I | 0010011 | 101 | 010000 | rd = rs1 >> shamt (arithmetic) |

### Register-register arithmetic (rv64i_alu.odin)

Arithmetic and logic between two registers.
| Instruction | Format | Opcode | funct3 | funct7 | Effect |
|---|---|---|---|---|---|
| ADD rd, rs1, rs2 | R | 0110011 | 000 | 0000000 | rd = rs1 + rs2 |
| SUB | R | 0110011 | 000 | 0100000 | rd = rs1 - rs2 |
| SLL | R | 0110011 | 001 | 0000000 | rd = rs1 << (rs2 & 63) |
| SLT | R | 0110011 | 010 | 0000000 | rd = (rs1 < rs2) signed |
| SLTU | R | 0110011 | 011 | 0000000 | rd = (rs1 < rs2) unsigned |
| XOR | R | 0110011 | 100 | 0000000 | rd = rs1 ^ rs2 |
| SRL | R | 0110011 | 101 | 0000000 | rd = rs1 >> (rs2 & 63) logical |
| SRA | R | 0110011 | 101 | 0100000 | rd = rs1 >> (rs2 & 63) arithmetic |
| OR | R | 0110011 | 110 | 0000000 | rd = rs1 \| rs2 |
| AND | R | 0110011 | 111 | 0000000 | rd = rs1 & rs2 |

### 32-bit word arithmetic (RV64 only, rv64i_alu_word.odin)

The *w instructions. Compute on the low 32 bits, then sign-extend the 32-bit result to 64 bits. Shift amounts are 5 bits.
| Instruction | Format | Opcode | funct3 | funct7 | Effect |
|---|---|---|---|---|---|
| ADDIW rd, rs1, imm | I | 0011011 | 000 | | rd = sext32(rs1 + imm) |
| SLLIW rd, rs1, shamt | I | 0011011 | 001 | 0000000 | rd = sext32(rs1[31:0] << shamt) |
| SRLIW | I | 0011011 | 101 | 0000000 | rd = sext32(rs1[31:0] >> shamt) logical |
| SRAIW | I | 0011011 | 101 | 0100000 | rd = sext32(rs1[31:0] >> shamt) arithmetic |
| ADDW rd, rs1, rs2 | R | 0111011 | 000 | 0000000 | rd = sext32(rs1 + rs2) |
| SUBW | R | 0111011 | 000 | 0100000 | rd = sext32(rs1 - rs2) |
| SLLW | R | 0111011 | 001 | 0000000 | rd = sext32(rs1[31:0] << (rs2 & 31)) |
| SRLW | R | 0111011 | 101 | 0000000 | logical, 32-bit |
| SRAW | R | 0111011 | 101 | 0100000 | arithmetic, 32-bit |

### M extension: multiply and divide (rv64m.odin)

The M extension. R-type, funct7 = 0000001, sharing the OP and OP-32 opcodes with ADD and ADDW. Integers only (floating point is the separate F and D extensions).
| Instruction | Opcode | funct3 | Effect |
|---|---|---|---|
| MUL rd, rs1, rs2 | 0110011 | 000 | rd = low 64 bits of rs1 * rs2 (same for signed and unsigned) |
| MULH | 0110011 | 001 | rd = high 64 bits of the 128-bit product, signed x signed |
| MULHSU | 0110011 | 010 | high 64 bits, rs1 signed x rs2 unsigned |
| MULHU | 0110011 | 011 | high 64 bits, unsigned x unsigned |
| DIV | 0110011 | 100 | rd = rs1 / rs2, signed, rounded toward zero |
| DIVU | 0110011 | 101 | rd = rs1 / rs2, unsigned |
| REM | 0110011 | 110 | rd = rs1 % rs2, signed (sign of the dividend) |
| REMU | 0110011 | 111 | rd = rs1 % rs2, unsigned |
| MULW | 0111011 | 000 | rd = sext32(low 32 bits of rs1 * rs2) |
| DIVW / DIVUW | 0111011 | 100 / 101 | 32-bit signed / unsigned divide, result sign-extended |
| REMW / REMUW | 0111011 | 110 / 111 | 32-bit signed / unsigned remainder, result sign-extended |
Division never traps. The results the spec defines for the two cases with no real answer:
| Case | DIV / DIVU | REM / REMU |
|---|---|---|
| divide by zero | all ones (-1 / 2^64-1) | the dividend |
| signed overflow: -2^63 / -1 | the dividend (-2^63) | 0 |
The W forms follow the same table on 32-bit values. OP-32 has no MULH forms: funct3 001..011 there is illegal.

### A extension: atomics (rv64a.odin)

The A extension: lr, sc and the AMOs. R-type, opcode 0101111 (AMO). funct5 (bits 31..27) picks the operation; bit 26 is aq and bit 25 rl (ordering hints, no effect with one in-order hart); funct3 010 = .W, 011 = .D. The address is rs1 with no offset and must be aligned to the size.
| Instruction | funct5 | Effect |
|---|---|---|
| LR.W / LR.D rd, (rs1) | 00010 | rd = memory (sign-extended for .W); reserve the address. rs2 must be 0 |
| SC.W / SC.D rd, rs2, (rs1) | 00011 | if the reservation holds: memory = rs2, rd = 0; else rd = 1. The reservation is used up |
| AMOSWAP | 00001 | rd = memory; memory = rs2 |
| AMOADD | 00000 | rd = memory; memory += rs2 |
| AMOXOR / AMOAND / AMOOR | 00100 / 01100 / 01000 | rd = memory; memory ^= / &= / \|= rs2 |
| AMOMIN / AMOMAX | 10000 / 10100 | signed min / max |
| AMOMINU / AMOMAXU | 11000 / 11100 | unsigned min / max |
Misaligned: LR raises Load_Address_Misaligned, SC and AMOs Store_Address_Misaligned. Outside RAM (nothing there, or a device: atomics work on RAM only): Load_Access_Fault for LR, Store_Access_Fault for SC and AMOs. Trap entry clears the reservation, and undo restores it.

### Fences and system (rv64i_system.odin, privilege.odin)

The fences, ecall, ebreak, and the privileged mret and wfi.
| Instruction | Encoding | Effect today |
|---|---|---|
| FENCE | opcode 0001111, funct3 000 | no-op (one hart, memory accesses happen in order) |
| FENCE.I (Zifencei) | opcode 0001111, funct3 001 | no-op (no instruction cache to flush) |
| ECALL | 0x00000073 | trap `Ecall_From_M_Mode` (the cause follows the current privilege level) |
| EBREAK | 0x00100073 | trap `Breakpoint`; with no handler set up, the normal way for test programs to stop |
| MRET (privileged) | 0x30200073 | return from a trap: pc = mepc, privilege = MPP, MIE = MPIE, MPIE = 1 (`privilege.odin`) |
| WFI (privileged) | 0x10500073 | no-op: "wait for interrupt" is only a hint, and time here counts steps, so a loop around WFI still reaches its timer interrupt |

### CSR instructions (Zicsr, zicsr.odin)

The six CSR instructions. Opcode 1110011 (SYSTEM), I-type with the CSR address in bits 31:20. Each puts the CSR's old value in rd. The CSRs themselves and their write rules are in `csr.odin`.
```
 bits:  31 .. 20       | 19 .. 15 | 14 .. 12 | 11 .. 7 | 6 .. 0
 field: csr            | rs1/uimm | funct3   | rd      | opcode

 0x300029f3 = csrrs s3, mstatus, zero
        0011 0000 0000 | 00000    | 010      | 10011   | 1110011
        0x300, mstatus | zero     | csrrs    | s3 (19) | SYSTEM
```
In the i forms (CSRRWI, CSRRSI, CSRRCI) the rs1 field holds a 5-bit constant, uimm (0 to 31), instead of a register number.
| Instruction | funct3 | Effect |
|---|---|---|
| CSRRW rd, csr, rs1 | 001 | rd = csr; csr = rs1 (no read if rd = x0) |
| CSRRS rd, csr, rs1 | 010 | rd = csr; csr \|= rs1 (no write if rs1 = x0) |
| CSRRC rd, csr, rs1 | 011 | rd = csr; csr &= ~rs1 (no write if rs1 = x0) |
| CSRRWI rd, csr, uimm | 101 | as CSRRW with the 5-bit value uimm |
| CSRRSI rd, csr, uimm | 110 | as CSRRS (no write if uimm = 0) |
| CSRRCI rd, csr, uimm | 111 | as CSRRC (no write if uimm = 0) |
Assembler shorthands: `csrr rd, csr` = CSRRS rd, csr, x0; `csrw csr, rs1` = CSRRW x0, csr, rs1. A CSR that isn't implemented, or a write to a read-only one, raises `Illegal_Instruction`.
Implemented CSRs: the table in csr-addresses lists every one by number, with its level and access.

Related: lui, addi, add, lb, beq, jal, mul, lr.w, csrrw, csr-addresses, immediate, sign-extension, two's-complement, emulator
