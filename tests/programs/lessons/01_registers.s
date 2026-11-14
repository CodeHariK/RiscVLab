# Lesson 01: Registers and addi
# Put small numbers into registers with addi, and see that x0 always stays zero.
# Expect: exit 12
#
# RISC-V has 32 integer registers, x0..x31, each 64 bits wide. Assemblers
# also give them ABI names (t0 = x5, a0 = x10, ...); the debugger shows both.
#
#   addi rd, rs1, imm     rd = rs1 + imm
#
# imm is a 12-bit signed number (-2048..2047). Register x0 (called zero)
# always reads as 0, so "addi rd, zero, 5" simply loads 5 into rd.

    .section .text
    .globl _start
_start:
    addi t0, zero, 5        # t0 = 0 + 5
    addi t1, zero, 7        # t1 = 0 + 7
    addi t2, t0, 0          # t2 = t0 + 0: this is how a register is copied (the "mv" shorthand)
    addi zero, zero, 99     # a write to x0 is thrown away: watch it stay 0
    addi t3, t1, -2         # immediates can be negative: t3 = 7 - 2 = 5
    add  a0, t0, t1         # add takes two registers: a0 = 5 + 7 = 12
    ebreak                  # stop here; the emulator's exit code is a0 (12)
