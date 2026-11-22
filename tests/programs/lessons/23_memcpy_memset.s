# Lesson 23: A real memcpy and memset
# memcpy and memset for any length and alignment, the way libc writes them: single bytes up to an 8-byte boundary, 8 bytes at a time for the middle, single bytes for the rest.
# Expect: exit 4
# Docs: memcpy, xor, bltu, ld, sd, mul
#
# Lesson 22 copied 64 bytes that started on an 8-byte boundary. Real
# callers pass any address and any length, so a real memcpy works in
# three parts:
#
#   head   single bytes until dst is a multiple of 8
#   body   8 bytes at a time (ld / sd) while 8 or more are left
#   tail   single bytes for the last 0 to 7
#
# For example memcpy(dst + 3, src + 3, 47), the first call below:
#
#   offset:  3 4 5 6 7 | 8 ......... 47 | 48 49
#   part:    head (5)  | body (5 x 8)   | tail (2)
#
# The body needs dst and src aligned at the same time, so their low 3
# bits must match: (dst ^ src) & 7 == 0 (xor has a 1 wherever the two
# differ). If they don't match, moving dst to a boundary leaves src off
# one, and memcpy copies every byte singly instead. The second call
# shows that case, and minstret shows what it costs.
#
# memset is the same three parts with a store and no load. Its body
# stores 8 copies of the byte at once: c * 0x0101010101010101 puts c in
# every byte of a register (0xab -> 0xabababababababab).
#
# Registers in the functions (as in C: memcpy(dst, src, n), memset(dst, c, n)):
#   a0, a1, a2  dst, src or c, n; a0 is returned unchanged, as in C
#   t3          the dst address as it moves
#   t1, t4      the byte or 8 bytes on their way; memset's 8-byte pattern
# In _start: s1 and s2 are what each memcpy cost; s3 counts the checks
# that pass.
#
# Watch the Memory tab at dst1: 5 bytes land one at a time, then 8 at a
# time, then the last 2 singly. dst2 fills one byte per trip throughout.

    .section .text
    .globl _start
_start:
    # 1. Same alignment (both + 3): head, body and tail.
    csrr  s0, minstret
    la    a0, dst1 + 3
    la    a1, src + 3
    li    a2, 47
    jal   ra, memcpy
    csrr  s1, minstret
    sub   s1, s1, s0            # s1 = 111

    # 2. Different alignment (+ 4 and + 3): every byte singly.
    csrr  s0, minstret
    la    a0, dst2 + 4
    la    a1, src + 3
    li    a2, 47
    jal   ra, memcpy
    csrr  s2, minstret
    sub   s2, s2, s0            # s2 = 342

    # 3. memset(buf + 1, 0xab, 21): head 7, body 8, tail 6.
    la    a0, buf + 1
    li    a1, 0xab
    li    a2, 21
    jal   ra, memset

    # Checks: each one adds 1 to s3.
    li    s3, 0
    la    a0, dst1 + 3
    la    a1, src + 3
    li    a2, 47
    jal   ra, copied_exactly    # copy 1 is right
    add   s3, s3, a0
    la    a0, dst2 + 4
    la    a1, src + 3
    li    a2, 47
    jal   ra, copied_exactly    # copy 2 is right
    add   s3, s3, a0
    la    a0, buf + 1
    li    a1, 0xab
    li    a2, 21
    jal   ra, filled_exactly    # the memset is right
    add   s3, s3, a0
    sltu  t0, s1, s2            # 1: 111 < 342, the 8-byte body paid off
    add   a0, s3, t0            # a0 = 4
    ebreak

# memcpy(a0 = dst, a1 = src, a2 = n): copies n bytes, returns dst.
memcpy:
    mv    t3, a0                # t3 moves; a0 stays dst, the return value
    xor   t0, a0, a1
    andi  t0, t0, 7             # the low 3 bits where dst and src differ
    bnez  t0, memcpy_tail       # never both aligned: copy every byte singly
memcpy_head:                    # single bytes until dst is a multiple of 8
    andi  t0, t3, 7
    beqz  t0, memcpy_body       # dst aligned, so src is too
    beqz  a2, memcpy_done
    lbu   t1, 0(a1)
    sb    t1, 0(t3)
    addi  a1, a1, 1
    addi  t3, t3, 1
    addi  a2, a2, -1
    j     memcpy_head
memcpy_body:                    # 8 bytes at a time
    li    t2, 8
memcpy_body_loop:
    bltu  a2, t2, memcpy_tail   # fewer than 8 left
    ld    t1, 0(a1)
    sd    t1, 0(t3)
    addi  a1, a1, 8
    addi  t3, t3, 8
    addi  a2, a2, -8
    j     memcpy_body_loop
memcpy_tail:                    # single bytes for what is left
    beqz  a2, memcpy_done
    lbu   t1, 0(a1)
    sb    t1, 0(t3)
    addi  a1, a1, 1
    addi  t3, t3, 1
    addi  a2, a2, -1
    j     memcpy_tail
memcpy_done:
    ret

# memset(a0 = dst, a1 = c, a2 = n): fills n bytes with the byte c,
# returns dst.
memset:
    mv    t3, a0
    andi  a1, a1, 0xff          # only the low byte counts
    li    t0, 0x0101010101010101
    mul   t4, a1, t0            # t4 = c in all 8 bytes: 0xabababababababab
memset_head:
    andi  t0, t3, 7
    beqz  t0, memset_body
    beqz  a2, memset_done
    sb    a1, 0(t3)
    addi  t3, t3, 1
    addi  a2, a2, -1
    j     memset_head
memset_body:
    li    t2, 8
memset_body_loop:
    bltu  a2, t2, memset_tail
    sd    t4, 0(t3)             # 8 bytes of c in one store
    addi  t3, t3, 8
    addi  a2, a2, -8
    j     memset_body_loop
memset_tail:
    beqz  a2, memset_done
    sb    a1, 0(t3)
    addi  t3, t3, 1
    addi  a2, a2, -1
    j     memset_tail
memset_done:
    ret

# a0 = 1 if the a2 bytes at a0 equal those at a1, and the bytes just
# before and just after them are still 0 (nothing written outside).
copied_exactly:
    lbu   t0, -1(a0)
    add   t1, a0, a2
    lbu   t1, 0(t1)
    or    t0, t0, t1
    bnez  t0, not_exact
copied_loop:
    lbu   t0, 0(a0)
    lbu   t1, 0(a1)
    bne   t0, t1, not_exact
    addi  a0, a0, 1
    addi  a1, a1, 1
    addi  a2, a2, -1
    bnez  a2, copied_loop
    li    a0, 1
    ret

# a0 = 1 if the a2 bytes at a0 are all a1, and the bytes either side
# are still 0.
filled_exactly:
    lbu   t0, -1(a0)
    add   t1, a0, a2
    lbu   t1, 0(t1)
    or    t0, t0, t1
    bnez  t0, not_exact
filled_loop:
    lbu   t0, 0(a0)
    bne   t0, a1, not_exact
    addi  a0, a0, 1
    addi  a2, a2, -1
    bnez  a2, filled_loop
    li    a0, 1
    ret

not_exact:
    li    a0, 0
    ret

    .section .data
    .balign 8
# The bytes 0x00 to 0x3f, as in lesson 22.
src:
    .dword 0x0706050403020100, 0x0f0e0d0c0b0a0908
    .dword 0x1716151413121110, 0x1f1e1d1c1b1a1918
    .dword 0x2726252423222120, 0x2f2e2d2c2b2a2928
    .dword 0x3736353433323130, 0x3f3e3d3c3b3a3938
dst1:
    .space 64                   # copy 1 writes bytes 3 to 49
dst2:
    .space 64                   # copy 2 writes bytes 4 to 50
buf:
    .space 32                   # memset writes bytes 1 to 21
