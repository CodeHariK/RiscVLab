# sum.s: adds 1..10 into a0, then stops with EBREAK.
# Expected: the emulator exits with code 55.

    .section .text
    .globl _start
_start:
    li   a0, 0              # a0 = running sum
    li   t0, 1              # t0 = i
    li   t1, 11             # t1 = loop end (exclusive)
loop:
    add  a0, a0, t0         # sum += i
    addi t0, t0, 1          # i++
    blt  t0, t1, loop       # while i < 11
    ebreak
