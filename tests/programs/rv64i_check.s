# rv64i_check.s: self-checking RV64I test.
# Before each check, a0 is set to the check number. A failed check jumps to
# `fail`, which stops with that number still in a0. When every check passes,
# a0 is set to 0. So the emulator's exit code is 0 for pass, or the number of
# the first failing check.

    .section .text
    .globl _start
_start:
    li   sp, 0x80100000     # scratch memory, 1 MiB into RAM

    # 1: ADD
    li   a0, 1
    li   t0, 5
    li   t1, 7
    add  t2, t0, t1
    li   t3, 12
    bne  t2, t3, fail

    # 2: SUB going negative
    li   a0, 2
    sub  t2, t0, t1
    li   t3, -2
    bne  t2, t3, fail

    # 3: SD / LD round trip of a full 64-bit value
    li   a0, 3
    li   t0, 0x123456789abcdef0
    sd   t0, 0(sp)
    ld   t1, 0(sp)
    bne  t0, t1, fail

    # 4: LW sign-extends bit 31
    li   a0, 4
    li   t0, 0x80000000
    sw   t0, 8(sp)
    lw   t1, 8(sp)
    li   t2, -2147483648
    bne  t1, t2, fail

    # 5: LWU zero-extends
    li   a0, 5
    lwu  t1, 8(sp)
    bne  t1, t0, fail

    # 6: LB sign-extends, LBU zero-extends
    li   a0, 6
    li   t0, 0xff
    sb   t0, 16(sp)
    lb   t1, 16(sp)
    li   t2, -1
    bne  t1, t2, fail
    lbu  t1, 16(sp)
    bne  t1, t0, fail

    # 7: ADDIW wraps at 32 bits and sign-extends
    li   a0, 7
    li   t0, 0x7fffffff
    addiw t1, t0, 1
    li   t2, -2147483648
    bne  t1, t2, fail

    # 8: SRAI keeps the sign
    li   a0, 8
    li   t0, -16
    srai t1, t0, 2
    li   t2, -4
    bne  t1, t2, fail

    # 9: SRLI uses a 6-bit shift amount on RV64
    li   a0, 9
    li   t0, -1
    srli t1, t0, 60
    li   t2, 15
    bne  t1, t2, fail

    # 10: SLT is signed, SLTU is unsigned
    li   a0, 10
    li   t0, -1
    li   t1, 1
    slt  t2, t0, t1
    sltu t3, t0, t1
    li   t4, 1
    bne  t2, t4, fail
    bnez t3, fail

    # 11: JAL / JALR call and return
    li   a0, 11
    li   t5, 0
    jal  ra, set_t5
    li   t6, 42
    bne  t5, t6, fail

    # 12: SUBW / SRAW on 32-bit values
    li   a0, 12
    li   t0, 0
    li   t1, 1
    subw t2, t0, t1         # -1 as a 32-bit result, sign-extended
    li   t3, -1
    bne  t2, t3, fail
    li   t0, 0x80000000
    li   t1, 4
    sraw t2, t0, t1         # 0x80000000 >> 4 (arithmetic, 32-bit)
    li   t3, 0xfffffffff8000000
    bne  t2, t3, fail

pass:
    li   a0, 0
fail:
    ebreak

set_t5:
    li   t5, 42
    ret
