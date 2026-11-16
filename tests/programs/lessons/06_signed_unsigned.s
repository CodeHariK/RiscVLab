# Lesson 06: Signed vs unsigned
# The same 64 bits compare differently as signed or unsigned numbers: slt vs sltu, blt vs bltu.
# Expect: exit 13
# Docs: slt, blt, two's-complement
#
# A register doesn't know whether it holds a signed or an unsigned number;
# the instruction decides. -1 is all 64 bits set: as a signed number it is
# below 1, but as an unsigned number it is the largest value there is.
#
#   slt  / blt    compare as signed numbers
#   sltu / bltu   compare as unsigned numbers
#
# a0 collects one bit per result, so the exit code shows them all.

    .section .text
    .globl _start
_start:
    addi t0, zero, -1       # t0 = -1 = 0xffffffffffffffff
    addi t1, zero, 1        # t1 = 1
    slt  t2, t0, t1         # signed:   is -1 < 1?          yes: t2 = 1
    sltu t3, t0, t1         # unsigned: is 0xffff...ff < 1? no:  t3 = 0
    addi a0, t2, 0          # bit 0 of a0 = slt result (1)
    slli t3, t3, 1
    add  a0, a0, t3         # bit 1 of a0 = sltu result (0)
    blt  t0, t1, signed_less  # signed compare: -1 < 1, so this branch is taken
    j    done               # (skipped)
signed_less:
    addi a0, a0, 4          # bit 2: the signed branch was taken
    bltu t0, t1, done       # unsigned compare: false, so this branch falls through
    addi a0, a0, 8          # bit 3: the unsigned branch was not taken
done:
    ebreak                  # a0 = 1 + 0 + 4 + 8 = 13
