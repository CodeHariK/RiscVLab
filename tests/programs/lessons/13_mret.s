# Lesson 13: Returning from a trap with mret
# A full system-call round trip: ecall into the handler, then mret back, which also restores the interrupt-enable bit.
# Expect: exit 4
# Docs: trap-return, system-call, mret, mstatus
#
# The program turns interrupts on (mstatus.MIE = 1) first. Watch mstatus
# in the CSRs tab: the trap clears MIE and saves it in MPIE, and mret puts
# it back (MIE = MPIE) while jumping to mepc. With lesson 12's jr, MIE
# would stay 0. The call works like a real system call: request number in
# a7, argument in a0, answer back in a0 (1 + 1 + 1 = 3, plus MIE = 4).

    .section .text
    .globl _start
_start:
    la    t0, handler
    csrw  mtvec, t0
    csrsi mstatus, 8        # MIE = 1 (watch the bit in the CSRs tab)
    li    a0, 1             # argument
    li    a7, 1             # system call number
    ecall                   # into the handler: MIE becomes 0, MPIE 1
    csrr  t0, mstatus       # back after mret: MIE is 1 again
    srli  t0, t0, 3
    andi  t0, t0, 1         # t0 = MIE
    add   a0, a0, t0        # a0 = 3 (from the handler) + 1 (MIE) = 4
    csrw  mtvec, zero       # remove the handler before the final ebreak
    ebreak

    .balign 4
handler:
    csrr  s2, mstatus       # inside the handler: MIE = 0, MPIE = 1
    add   a0, a0, a7        # "do the system call": a0 = 1 + 1
    addi  a0, a0, 1         # ... + 1 = 3
    csrr  t1, mepc
    addi  t1, t1, 4         # return to the instruction after the ecall
    csrw  mepc, t1
    mret                    # pc = mepc, MIE = MPIE
