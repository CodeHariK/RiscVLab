# mret_check.s: self-checking test of MRET (return from a trap handler).
# The handler counts how often it ran (s6), saves mstatus as it was inside
# the handler (s5), moves mepc past the trapping instruction and returns
# with MRET.
#
# Exit code: 0 = all passed, otherwise the number of the first failing check.

    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0
    li   s6, 0

    # 1: MRET returns to mepc: execution continues after the ECALL
    li   a0, 1
    ecall
    li   t0, 1
    bne  s6, t0, fail               # the handler ran exactly once

    # 2: MRET restores MIE from MPIE
    li   a0, 2
    csrsi mstatus, 8                # MIE = 1
    ecall                           # entry: MPIE = 1, MIE = 0; MRET: MIE = 1
    csrr t0, mstatus
    andi t0, t0, 8
    beqz t0, fail

    # 3: inside the handler MIE was 0
    li   a0, 3
    andi t1, s5, 8
    bnez t1, fail

    # 4: after MRET, MPIE = 1 and MPP = user (the least privileged mode,
    #    so a second MRET can't go back up by mistake)
    li   a0, 4
    csrr t0, mstatus
    li   t1, 0x1880                 # MPP | MPIE
    and  t2, t0, t1
    li   t1, 0x0080                 # MPP = 00 (user), MPIE = 1
    bne  t2, t1, fail

    # 5: MRET jumps to whatever mepc holds, even without a trap. MPP is
    #    set to machine first, or this MRET would drop into user mode.
    li   a0, 5
    li   t0, 0x1800
    csrs mstatus, t0                # MPP = 11 (machine)
    la   t0, after_jump
    csrw mepc, t0
    mret
    j    fail                       # skipped if MRET jumped
after_jump:

    # Done: clear mtvec so the final EBREAK stops the machine.
pass:
    li   a0, 0
fail:
    csrw mtvec, zero
    ebreak

    .balign 4
handler:
    csrr s5, mstatus
    addi s6, s6, 1
    csrr t6, mepc
    addi t6, t6, 4                  # skip the instruction that trapped
    csrw mepc, t6
    mret
