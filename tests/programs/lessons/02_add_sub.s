# Lesson 02: add, sub and wrap-around
# Subtract to get negative numbers, and see that 64-bit arithmetic wraps around instead of trapping.
# Expect: exit 1
#
# Registers hold 64 bits. Negative numbers use two's complement: -1 is all
# 64 bits set (0xffffffffffffffff), -7 is 0xfffffffffffffff9.
# Adding past the largest value simply wraps around: RISC-V has no
# overflow trap, so programs check for overflow themselves if they care.

    .section .text
    .globl _start
_start:
    addi t0, zero, 10       # t0 = 10
    addi t1, zero, 3        # t1 = 3
    sub  t2, t0, t1         # t2 = 10 - 3 = 7
    sub  t3, t1, t0         # t3 = 3 - 10 = -7 (look at its hex value)
    add  t4, t2, t3         # t4 = 7 + (-7) = 0
    addi t5, zero, -1       # t5 = -1: all 64 bits set
    addi t6, t5, 1          # -1 + 1 wraps around to 0
    or   a0, t4, t6         # a0 = 0 only if both t4 and t6 are 0
    sltiu a0, a0, 1         # a0 = 1 if a0 == 0, else 0 (the "seqz" shorthand)
    ebreak                  # exit code 1 means both results were 0
