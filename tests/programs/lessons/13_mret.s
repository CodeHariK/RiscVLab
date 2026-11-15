# Lesson 13: Returning from a trap with mret
# A full system-call round trip: ecall into the handler, then mret back, which also restores the interrupt-enable bit.
# Expect: exit 4
#
# WHY mret AND NOT jr
# A trap changes more than the pc, and the way back has to undo all of it:
#
#                        trap entry      jr mepc+4 (lesson 12)   mret
#   pc                   -> mtvec        restored                restored (= mepc)
#   mstatus.MIE          -> 0            stays 0                 = MPIE (as before)
#   privilege level      -> machine      stays machine           = MPP (as before)
#
# - Interrupts: trap entry turns them off (MIE = 0, the old value kept in
#   MPIE) so the handler is not interrupted halfway. With jr they would
#   stay off after the first trap.
# - Privilege: a trap from a user program raises the level to machine.
#   Only mret can bring it back down; jr would leave the user program
#   running with full power.
# So a handler sets mepc to where it should return (for ecall, mepc + 4)
# and ends with mret:  pc = mepc, MIE = MPIE, MPIE = 1, privilege = MPP.
# Lesson 12 got away with jr only because everything runs in machine mode
# and nothing had turned interrupts on. This lesson turns MIE on first, so
# you can watch the trap clear it and mret restore it: open the CSRs tab
# and look at mstatus as you step over the ecall and the mret.
#
# A SYSTEM CALL
# A system call is a program asking the kernel to do something it may not
# do itself: write to the screen, read a file, start a process. Registers
# carry the request, by convention (the same in Linux and xv6):
#   1. the program puts the request number in a7 and arguments in a0..a5
#   2. ecall traps into the kernel's handler
#   3. the handler reads a7, does the work, and puts the result in a0
#   4. it sets mepc to mepc + 4 and mrets
#   5. the program continues after the ecall with the answer in a0
# To the program it looks like a function call into the kernel. In xv6,
# write(fd, buf, n) is a few instructions: a7 = 16, then ecall. A real
# kernel also saves every other register on entry and restores them
# before mret; this handler only uses registers the program doesn't need.
# Here: request 1 in a7, argument 1 in a0, the "kernel" answers 3 in a0.

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
