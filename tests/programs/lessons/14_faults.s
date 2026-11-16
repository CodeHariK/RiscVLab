# Lesson 14: Faults
# Mistakes become traps too: an illegal instruction, a load from nowhere and a misaligned jump. The handler counts them.
# Expect: exit 55
# Docs: why-traps, Illegal_Instruction, Load_Access_Fault, Instruction_Address_Misaligned, mtval
#
# Three deliberate mistakes, each a different trap cause:
#    2  Illegal_Instruction             (mtval = the instruction's bits)
#    5  Load_Access_Fault               (mtval = the address)
#    0  Instruction_Address_Misaligned  (mtval = the jump target)
# The faulting instruction changes nothing else. One handler takes all
# three: it counts them in s0, adds the causes in s1 and skips each one.
# a0 = 3 traps * 16 + (2 + 5 + 0) = 55.

    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0
    li   s0, 0              # number of traps
    li   s1, 0              # sum of their mcause values
    .word 0xffffffff        # not a valid instruction: trap, mcause 2
    li   t1, 0x1000
    ld   t2, 0(t1)          # nothing in memory at 0x1000: trap, mcause 5
    la   t3, target
    addi t3, t3, 2          # target + 2 is not 4-byte aligned...
    jr   t3                 # ...so the jump traps, mcause 0 (mepc = this jr)
    slli a0, s0, 4          # a0 = traps * 16 + sum of causes
    add  a0, a0, s1         #    = 3 * 16 + (2 + 5 + 0) = 55
    csrw mtvec, zero
    ebreak

target:
    nop

    .balign 4
handler:
    addi s0, s0, 1          # count it
    csrr t5, mcause
    add  s1, s1, t5         # add up the causes
    csrr t6, mepc
    addi t6, t6, 4          # skip the faulting instruction
    csrw mepc, t6
    mret
