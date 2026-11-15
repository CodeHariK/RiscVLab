# Lesson 14: Faults
# Mistakes become traps too: an illegal instruction, a load from nowhere and a misaligned jump. The handler counts them.
# Expect: exit 55
#
# MISTAKES TRAP TOO
# When an instruction can't complete, the CPU doesn't crash: it takes a
# trap, exactly like ecall, and the handler decides what to do. That is
# how an OS survives a buggy program: the fault lands in the kernel, which
# can kill just that program (or fix the cause and let it retry).
#
# Kinds of traps:
#   faults            an instruction can't complete    this lesson
#   deliberate traps  ecall (system call), ebreak       lessons 12 and 13
#   interrupts        a timer, a device, another hart   later, with the timer
# Faults and deliberate traps are "exceptions" and happen at that
# instruction, every time, whether interrupts are enabled or not.
# Interrupts arrive between any two instructions (mcause bit 63 = 1).
#
# THE THREE FAULTS HERE
#   instruction            mcause                             mtval
#   .word 0xffffffff       2  Illegal_Instruction             the bits: 0xffffffff
#   ld from 0x1000         5  Load_Access_Fault               the address: 0x1000
#   jr to target + 2       0  Instruction_Address_Misaligned  the target
# mepc is always the instruction that failed, and that instruction changes
# nothing else: the ld leaves t2 alone, the jr doesn't move the pc. The
# handler sees the state exactly as it was just before the mistake.
#
# ONE HANDLER FOR ALL OF THEM
# Every trap arrives at mtvec, so the handler tells them apart with mcause
# (and mtval for the detail). This one counts the traps in s0, adds up the
# causes in s1, and skips each faulting instruction (mepc + 4), then mret.
# Result: a0 = traps * 16 + sum of causes = 3 * 16 + (2 + 5 + 0) = 55.

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
