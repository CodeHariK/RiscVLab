# csr_check.s: self-checking test of the Zicsr instructions.
# Same convention as rv64i_check.s: a0 holds the check number; exit code 0
# means every check passed, otherwise it is the first failing check.

    .section .text
    .globl _start
_start:
    # 1: CSRRW (as csrw / csrr) writes and reads mscratch
    li   a0, 1
    li   t0, 0x1234
    csrw mscratch, t0
    csrr t1, mscratch
    bne  t0, t1, fail

    # 2: CSRRW returns the old value while writing the new one
    li   a0, 2
    li   t2, 0x55
    csrrw t3, mscratch, t2
    bne  t3, t0, fail             # old value 0x1234
    csrr t1, mscratch
    bne  t1, t2, fail             # now 0x55

    # 3: CSRRS sets bits and returns the old value
    li   a0, 3
    li   t5, 0x0a
    csrrs t4, mscratch, t5
    li   t6, 0x55
    bne  t4, t6, fail             # old value 0x55
    csrr t1, mscratch
    li   t6, 0x5f
    bne  t1, t6, fail             # 0x55 | 0x0a

    # 4: CSRRC clears bits
    li   a0, 4
    li   t0, 0x0f
    csrrc t1, mscratch, t0
    li   t6, 0x5f
    bne  t1, t6, fail             # old value 0x5f
    csrr t1, mscratch
    li   t6, 0x50
    bne  t1, t6, fail             # 0x5f & ~0x0f

    # 5: the immediate forms use the rs1 field as a 5-bit value
    li   a0, 5
    csrrwi t1, mscratch, 7
    li   t6, 0x50
    bne  t1, t6, fail
    csrrsi zero, mscratch, 8      # 7 | 8 = 15
    csrrci t1, mscratch, 1        # returns 15, leaves 14
    li   t6, 15
    bne  t1, t6, fail
    csrr t1, mscratch
    li   t6, 14
    bne  t1, t6, fail

    # 6: read-only machine information: mhartid = 0, mvendorid = 0
    li   a0, 6
    csrr t0, mhartid
    bnez t0, fail
    csrr t0, mvendorid
    bnez t0, fail

    # 7: misa says 64-bit (MXL = 2 in bits 63:62)
    li   a0, 7
    csrr t0, misa
    srli t0, t0, 62
    li   t1, 2
    bne  t0, t1, fail

    # 8: mepc drops the low two bits (instructions are 4-byte aligned)
    li   a0, 8
    li   t0, 0x80000007
    csrw mepc, t0
    csrr t1, mepc
    li   t2, 0x80000004
    bne  t1, t2, fail

    # 9: minstret counts retired instructions: two reads in a row differ by 1
    li   a0, 9
    csrr t0, minstret
    csrr t1, minstret
    sub  t2, t1, t0
    li   t3, 1
    bne  t2, t3, fail

    # 10: cycle (read-only copy) matches the count too
    li   a0, 10
    csrr t0, minstret
    csrr t1, cycle
    sub  t2, t1, t0
    li   t3, 1
    bne  t2, t3, fail

pass:
    li   a0, 0
fail:
    ebreak
