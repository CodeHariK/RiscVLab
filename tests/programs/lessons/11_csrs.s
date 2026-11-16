# Lesson 11: CSRs
# Read and write control and status registers (mhartid, mscratch, minstret); open the CSRs tab to watch them.
# Expect: exit 3
# Docs: csr-overview, csr-addresses, csrrs, mscratch, minstret
#
# CSRs are registers inside the CPU that describe and control it. They are
# separate from x0..x31 and only reachable with the CSR instructions:
#
#   csrr  rd, csr        read                      (csrrs rd, csr, zero)
#   csrw  csr, rs1       write                     (csrrw zero, csr, rs1)
#   csrrsi rd, csr, n    read, then set the bits of n
#   csrrci rd, csr, n    read, then clear the bits of n

    .section .text
    .globl _start
_start:
    csrr  t0, mhartid       # which hart (core) this is: 0
    li    t1, 0x55
    csrw  mscratch, t1      # mscratch is free for software to use: store 0x55
    csrrsi t2, mscratch, 0x0a   # t2 = old value 0x55; mscratch = 0x55 | 0x0a = 0x5f
    csrrci t3, mscratch, 0x0f   # t3 = old value 0x5f; mscratch = 0x5f & ~0x0f = 0x50
    csrr  t4, mscratch      # t4 = 0x50
    csrr  t5, minstret      # instructions retired so far
    csrr  t6, minstret      # one more: the csrr above retired
    addi  a1, t4, -0x50
    seqz  a1, a1            # 1 if mscratch ended as 0x50
    sub   a2, t6, t5        # 1: the counter moved by one instruction
    seqz  a3, t0            # 1 if this is hart 0
    add   a0, a1, a2
    add   a0, a0, a3        # a0 = 3
    ebreak
