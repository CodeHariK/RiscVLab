# Lesson 12: Traps: ecall and a handler
# Install a trap handler in mtvec; ecall jumps to it, and the CPU records why (mcause) and where (mepc).
# Expect: exit 11
#
# On a trap the CPU saves the trapping instruction's address in mepc, the
# reason in mcause (11 = ecall from machine mode), extra detail in mtval,
# and jumps to the address in mtvec. Watch the CSRs tab as you step over
# the ecall.

    .section .text
    .globl _start
_start:
    la   t0, handler
    csrw mtvec, t0          # traps now go to `handler`
    ecall                   # a system call: trap!
    addi a0, s0, 0          # back here: the handler saved mcause in s0 (11)
    csrw mtvec, zero        # remove the handler, so the ebreak below stops the program
    ebreak                  # (with a handler set, ebreak would trap to it instead)

    .balign 4
handler:
    csrr s0, mcause         # why: 11 = Ecall_From_M_Mode
    csrr s1, mepc           # where: the address of the ecall
    addi s1, s1, 4          # skip over it
    jr   s1                 # return by jumping there (lesson 13 uses mret)
