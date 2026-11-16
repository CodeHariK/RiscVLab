# Lesson 18: lr / sc and compare-and-swap
# Build your own atomic step: lr reserves an address, sc stores only if nothing came in between, and the loop retries when it fails.
# Expect: exit 12
# Docs: lr.w, atomic, memory-ordering
#
# lr.w loads a value and reserves its address. sc.w stores only if the
# reservation still holds, and sets rd: 0 = stored, 1 = failed (the
# reservation was lost: another hart wrote there, a trap happened, or
# there was no lr). On failure the loop tries again. Here it makes a
# compare-and-swap: "if value is still 5, make it 9", the building block
# of lock-free code. Then an sc with no lr before it fails, and a trap
# between lr and sc breaks the reservation (the handler just returns).
# a0 = value (9) + the lone sc failed (1) + the sc after the trap failed
# (1) + it stored nothing (1) = 12.

    .section .text
    .globl _start
_start:
    # Compare-and-swap: if value == 5, value = 9.
    la    s1, value
    li    t1, 5                 # expected
    li    t2, 9                 # new
cas:
    lr.w  t3, (s1)              # load and reserve
    bne   t3, t1, cas_done      # not what we expected: give up
    sc.w  t4, t2, (s1)          # store if still reserved; t4 = 0 if it did
    bnez  t4, cas               # lost the reservation: try again
cas_done:

    # An sc with no lr before it fails and stores nothing.
    sc.w  t5, t1, (s1)          # t5 = 1; value stays 9

    # A trap between lr and sc breaks the reservation.
    la    t0, handler
    csrw  mtvec, t0
    la    s2, other
    lr.w  t3, (s2)              # reserve `other`
    ecall                       # trap: the reservation is cleared
    sc.w  t6, t1, (s2)          # fails: t6 = 1, other stays 0
    csrw  mtvec, zero

    lw    a0, 0(s1)             # 9
    add   a0, a0, t5            # + 1
    add   a0, a0, t6            # + 1
    lw    t3, 0(s2)
    seqz  t3, t3                # + 1: other was not written
    add   a0, a0, t3            # = 12
    ebreak

    .balign 4
handler:                        # skip the ecall and return
    csrr  t0, mepc
    addi  t0, t0, 4
    csrw  mepc, t0
    mret

    .section .data
    .balign 4
value: .word 5
other: .word 0
