# Supported instructions

What RiscVOdin executes today, with the encoding fields it decodes. Anything not listed raises `Illegal_Instruction`.

**Current status: RV64I base (all 52 instructions) + Zifencei + Zicsr. 59 in total.**

Formats: see the diagram at the top of `emulator/core/decode.odin`.
`imm` is always sign-extended to 64 bits. Arithmetic wraps modulo 2^64.

## By encoding format

The same instructions, grouped by bit layout instead of by job. The layouts are drawn at the top of `emulator/core/decode.odin`, and each one with an immediate has a decoder there (`imm_i`, `imm_s`, `imm_b`, `imm_u`, `imm_j`). R-type has no immediate.

| Format | Fields | Immediate | Instructions |
|---|---|---|---|
| **R** | funct7, rs2, rs1, funct3, rd | none | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, ADDW, SUBW, SLLW, SRLW, SRAW |
| **I** | imm[11:0], rs1, funct3, rd | 12 bits, `imm_i` | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI, ADDIW, SLLIW, SRLIW, SRAIW, LB, LH, LW, LD, LBU, LHU, LWU, JALR, FENCE, FENCE.I, ECALL, EBREAK, CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| **S** | imm[11:5], rs2, rs1, funct3, imm[4:0] | 12 bits, `imm_s` | SB, SH, SW, SD |
| **B** | imm[12\|10:5], rs2, rs1, funct3, imm[4:1\|11] | 13 bits (bit 0 always 0), `imm_b` | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| **U** | imm[31:12], rd | upper 20 bits, `imm_u` | LUI, AUIPC |
| **J** | imm[20\|10:1\|11\|19:12], rd | 21 bits (bit 0 always 0), `imm_j` | JAL |

Notes:

- **Shift-immediates** (SLLI, SRAI, ...) are I-type, but the low 6 bits of the immediate (5 for the *W forms) are the shift amount, and the upper bits act like a funct7 that picks logical or arithmetic.
- **CSR instructions** are I-type whose 12-bit immediate is the CSR address (not sign-extended); the immediate forms put a 5-bit value in the rs1 field.
- **ECALL and EBREAK** are I-type with every field fixed except imm (0 for ECALL, 1 for EBREAK), so the emulator matches the whole 32-bit word.
- **S and B** have the same register positions; B scrambles the immediate bits so that the sign bit is always bit 31 and most bits stay in the same place as S. **U and J** share the same relationship.
- **Unprivileged vs privileged:** everything here is from the unprivileged spec. Privileged instructions (MRET, SRET, WFI, SFENCE.VMA) arrive with the trap milestone, in `priv_*` files.

## Upper immediates (`rv64i_upper.odin`)

| Instruction | Format | Opcode | Effect |
|---|---|---|---|
| LUI rd, imm | U | 0110111 | rd = imm << 12 |
| AUIPC rd, imm | U | 0010111 | rd = pc + (imm << 12) |

## Jumps and branches (`rv64i_control.odin`)

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

## Loads and stores (`rv64i_load_store.odin`)

Address = rs1 + off. A miss on the bus raises `Load_Access_Fault` / `Store_Access_Fault`.

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

## Register-immediate arithmetic (`rv64i_alu.odin`)

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

## Register-register arithmetic (`rv64i_alu.odin`)

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

## 32-bit "word" arithmetic, RV64 only (`rv64i_alu_word.odin`)

Compute on the low 32 bits, then sign-extend the 32-bit result to 64 bits. Shift amounts are 5 bits.

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

## Fences and system (`rv64i_system.odin`)

| Instruction | Encoding | Effect today |
|---|---|---|
| FENCE | opcode 0001111, funct3 000 | no-op (one hart, memory accesses happen in order) |
| FENCE.I (Zifencei) | opcode 0001111, funct3 001 | no-op (no instruction cache to flush) |
| ECALL | 0x00000073 | trap `Ecall_From_M_Mode` (stops the machine until trap handling exists) |
| EBREAK | 0x00100073 | trap `Breakpoint`: the normal way for test programs to stop |

## CSR instructions, Zicsr (`zicsr.odin`)

Opcode 1110011 (SYSTEM), I-type with the CSR address in bits 31:20. Each puts the CSR's old value in rd. The CSRs themselves and their write rules are in `csr.odin`.

| Instruction | funct3 | Effect |
|---|---|---|
| CSRRW rd, csr, rs1 | 001 | rd = csr; csr = rs1 (no read if rd = x0) |
| CSRRS rd, csr, rs1 | 010 | rd = csr; csr \|= rs1 (no write if rs1 = x0) |
| CSRRC rd, csr, rs1 | 011 | rd = csr; csr &= ~rs1 (no write if rs1 = x0) |
| CSRRWI rd, csr, uimm | 101 | as CSRRW with the 5-bit value uimm |
| CSRRSI rd, csr, uimm | 110 | as CSRRS (no write if uimm = 0) |
| CSRRCI rd, csr, uimm | 111 | as CSRRC (no write if uimm = 0) |

Assembler shorthands: `csrr rd, csr` = CSRRS rd, csr, x0; `csrw csr, rs1` = CSRRW x0, csr, rs1. A CSR that isn't implemented, or a write to a read-only one, raises `Illegal_Instruction`.

Implemented CSRs: mvendorid, marchid, mimpid, mhartid (read-only, 0); mstatus (MIE, MPIE, MPP); misa (RV64I, writes ignored); mie; mtvec; mscratch; mepc; mcause; mtval; mip (writes ignored); mcycle, minstret (= instructions retired); cycle, instret (read-only copies).

## Not supported yet

| Extension | Needed for | Milestone |
|---|---|---|
| MRET, SRET, WFI, SFENCE.VMA | Returning from traps, privilege modes, paging | Traps + privilege |
| M (MUL, MULH*, DIV*, REM*, and *W forms) | Compiled C/Odin arithmetic | M extension |
| A (LR, SC, AMO*) | xv6 spinlocks | A extension |
| C (compressed 16-bit instructions) | Optional: smaller code | Maybe later |
