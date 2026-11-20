# Lesson 22: Copying memory
# Copy 64 bytes twice: one byte per iteration (lbu / sb), then 8 bytes per iteration (ld / sd), and count what each copy cost with minstret.
# Expect: exit 3
# Docs: memcpy, lbu, ld, sb, sd, minstret
#
# RISC-V has no "copy memory" instruction: memcpy is a loop of loads and
# stores. A load or store moves 1, 2, 4 or 8 bytes, so the question is
# how many bytes each trip round the loop moves:
#
#   loop          moves per trip   trips for 64 bytes   instructions
#   lbu / sb      1 byte           64                   64 * 6 = 384
#   ld  / sd      8 bytes          8                    8 * 6  = 48
#
# Both loops are the same six instructions; only the size and the step
# change. 8 bytes is the most RV64I can move at once (a register is 64
# bits). Real memcpy works this way: 8 bytes at a time, and single bytes
# only for the last 0 to 7 bytes, or to reach an 8-byte boundary first
# (here all three buffers start on one: .balign 8).
#
# Registers:
#   a0, a1, a2  where to, where from, bytes left (as memcpy(dst, src, n))
#   t0          the byte or 8 bytes on their way
#   s1, s3      instructions each copy took (minstret after - before)
#
# Watch the Memory tab at dst1 fill one byte per trip, then dst2 eight
# at a time, and compare s1 with s3 in the Registers tab.

    .section .text
    .globl _start
_start:
    # Copy 1: one byte per trip.
    la    a0, dst1              # where to
    la    a1, src               # where from
    li    a2, 64                # bytes to copy
    csrr  s0, minstret          # instructions so far
copy_bytes:
    lbu   t0, 0(a1)             # 1 byte in
    sb    t0, 0(a0)             # 1 byte out
    addi  a1, a1, 1
    addi  a0, a0, 1
    addi  a2, a2, -1
    bnez  a2, copy_bytes        # 64 trips
    csrr  s1, minstret
    sub   s1, s1, s0            # s1 = 385: the loop's 384, plus the first csrr

    # Copy 2: 8 bytes per trip.
    la    a0, dst2
    la    a1, src
    li    a2, 64
    csrr  s2, minstret
copy_dwords:
    ld    t0, 0(a1)             # 8 bytes in
    sd    t0, 0(a0)             # 8 bytes out
    addi  a1, a1, 8
    addi  a0, a0, 8
    addi  a2, a2, -8
    bnez  a2, copy_dwords       # 8 trips
    csrr  s3, minstret
    sub   s3, s3, s2            # s3 = 49: the loop's 48, plus the first csrr

    # Check: both copies match src, and the 8-byte copy was cheaper.
    la    a0, dst1
    jal   ra, same_as_src       # a0 = 1 if dst1 matches
    mv    s4, a0
    la    a0, dst2
    jal   ra, same_as_src       # a0 = 1 if dst2 matches
    add   s4, s4, a0
    sltu  t0, s3, s1            # 1: 49 < 385
    add   a0, s4, t0            # a0 = 3
    ebreak

# a0 = 1 if the 64 bytes at a0 are the same as src, else 0. Compares 8
# bytes at a time, like the second copy.
same_as_src:
    la    a1, src
    li    a2, 8                 # 8 * 8 bytes
compare:
    ld    t0, 0(a0)
    ld    t1, 0(a1)
    bne   t0, t1, differs
    addi  a0, a0, 8
    addi  a1, a1, 8
    addi  a2, a2, -1
    bnez  a2, compare
    li    a0, 1
    ret
differs:
    li    a0, 0
    ret

    .section .data
    .balign 8
# 64 bytes, numbered 0x00 to 0x3f so a copied byte is easy to spot in the
# Memory tab (little-endian: the first .dword's lowest byte, 0x00, comes
# first).
src:
    .dword 0x0706050403020100, 0x0f0e0d0c0b0a0908
    .dword 0x1716151413121110, 0x1f1e1d1c1b1a1918
    .dword 0x2726252423222120, 0x2f2e2d2c2b2a2928
    .dword 0x3736353433323130, 0x3f3e3d3c3b3a3938
dst1:
    .space 64                   # filled by the byte copy
dst2:
    .space 64                   # filled by the 8-byte copy
