# trap_check.s: self-checking test of trap entry.
# A handler is installed in mtvec. Each check makes one trap happen; the
# handler saves mcause, mepc, mtval and mstatus in s2..s5 and returns to
# the instruction after the one that trapped (mepc + 4). The check then
# compares the saved values. (Returning with a plain jump keeps this test
# to trap entry only; MRET is the next step.)
#
# Exit code: 0 = all passed, otherwise the number of the first failing check.

    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0

    # 1: ECALL from machine mode: mcause 11, mepc = the ecall, mtval 0
    li   a0, 1
ecall_site:
    ecall
    li   t0, 11
    bne  s2, t0, fail
    la   t0, ecall_site
    bne  s3, t0, fail
    bnez s4, fail

    # 2: illegal instruction: mcause 2, mtval = the instruction's bits
    li   a0, 2
illegal_site:
    .word 0xffffffff
    li   t0, 2
    bne  s2, t0, fail
    la   t0, illegal_site
    bne  s3, t0, fail
    li   t0, 0xffffffff
    bne  s4, t0, fail

    # 3: load from an address with nothing there: mcause 5, mtval = address
    li   a0, 3
    li   t1, 0x1000
    ld   t2, 0(t1)
    li   t0, 5
    bne  s2, t0, fail
    li   t0, 0x1000
    bne  s4, t0, fail

    # 4: jump to a misaligned target: mcause 0, mepc = the jump, mtval = target
    li   a0, 4
    la   t1, misaligned_target
    addi t1, t1, 2
jump_site:
    jr   t1
    li   t0, 0
    bne  s2, t0, fail
    la   t0, jump_site
    bne  s3, t0, fail
    bne  s4, t1, fail

    # 5: mstatus on entry: MIE copied to MPIE, MIE cleared, MPP = machine (3)
    li   a0, 5
    csrsi mstatus, 8            # MIE = 1 before the trap
    ebreak                      # with a handler, EBREAK traps too: mcause 3
    li   t0, 3
    bne  s2, t0, fail
    li   t0, 0x1888             # MPP | MPIE | MIE
    and  t1, s5, t0
    li   t0, 0x1880             # MPP = 3, MPIE = 1, MIE = 0
    bne  t1, t0, fail

    # Done: clear mtvec so the final EBREAK stops the machine.
pass:
    li   a0, 0
fail:
    csrw mtvec, zero
    ebreak

misaligned_target:
    nop
    nop

# The trap handler. Must be 4-byte aligned (mtvec drops the low bits).
    .balign 4
handler:
    csrr s2, mcause
    csrr s3, mepc
    csrr s4, mtval
    csrr s5, mstatus
    addi t6, s3, 4
    jr   t6
