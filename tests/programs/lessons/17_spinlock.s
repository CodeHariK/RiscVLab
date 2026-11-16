# Lesson 17: A spinlock
# Take a lock with amoswap like xv6's acquire, update shared data inside it, and release it.
# Expect: exit 3
# Docs: locks, amoswap.w, memory-ordering
#
# The lock is one word: 0 free, 1 taken. acquire swaps a 1 in with
# amoswap and looks at what came back: 0 means it was free and is now
# ours; 1 means another hart has it, so try again ("spin"). Inside the
# lock, plain loads and stores are safe for the data it protects. Release
# swaps 0 back in. The .aq / .rl suffixes keep memory accesses from moving
# out of the locked section (Docs, memory-ordering); with one in-order
# hart they change nothing here.
# a0 = shared (1) + what a second hart would have seen while we held the
# lock (1: busy) + the lock is free again afterwards (1) = 3.

    .section .text
    .globl _start
_start:
    la    s0, lock
    li    t1, 1
acquire:
    amoswap.w.aq t2, t1, (s0)   # lock = 1; t2 = the old value (0: it was free)
    bnez  t2, acquire           # 1: another hart holds it, spin

    la    t3, shared            # critical section: only the lock holder gets here
    lw    t4, 0(t3)
    addi  t4, t4, 1
    sw    t4, 0(t3)             # shared = 1

    amoswap.w t5, t1, (s0)      # what a second hart's acquire would see now: t5 = 1, busy

    amoswap.w.rl zero, zero, (s0)  # release: lock = 0

    lw    a0, 0(t3)             # 1
    add   a0, a0, t5            # + 1 (it was busy)
    lw    t6, 0(s0)
    seqz  t6, t6                # 1 if the lock is free again
    add   a0, a0, t6            # = 3
    ebreak

    .section .data
    .balign 4
lock:   .word 0                 # 0 = free, 1 = taken
shared: .word 0                 # the data the lock protects
