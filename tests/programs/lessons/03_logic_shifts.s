# Lesson 03: Logic and shifts
# Combine bits with and / or / xor, and compare logical with arithmetic right shifts.
# Expect: exit 15
#
#   and  rd, a, b   1 where both bits are 1       1100 and 1010 = 1000
#   or   rd, a, b   1 where either bit is 1       1100 or  1010 = 1110
#   xor  rd, a, b   1 where the bits differ       1100 xor 1010 = 0110
#   slli rd, a, n   shift left by n (fills with zeros): multiply by 2^n
#   srli rd, a, n   shift right, filling with zeros       (logical)
#   srai rd, a, n   shift right, copying the sign bit     (arithmetic)
#
# Watch the registers in hex to see the bit patterns.

    .section .text
    .globl _start
_start:
    addi t0, zero, 0b1100   # t0 = 12
    addi t1, zero, 0b1010   # t1 = 10
    and  t2, t0, t1         # t2 = 0b1000 = 8
    or   t3, t0, t1         # t3 = 0b1110 = 14
    xor  t4, t0, t1         # t4 = 0b0110 = 6
    xori t5, t0, -1         # xor with all ones flips every bit: ~12 = -13 (the "not" shorthand)
    slli t6, t1, 4          # 10 << 4 = 160 (10 * 16)
    addi s0, zero, -16      # s0 = -16 = 0xfffffffffffffff0
    srli s1, s0, 60         # logical: zeros come in from the left, leaving 0xf = 15
    srai s2, s0, 2          # arithmetic: the sign bit is copied in, so -16 / 4 = -4
    addi a0, s1, 0          # a0 = 15
    ebreak
