# Lesson 16: An atomic counter
# Why count = count + 1 can lose updates when two harts share memory, and how one amoadd fixes it.
# Expect: exit 3
# Docs: race-condition, atomic, amoadd.w
#
# count = count + 1 is three instructions: lw, addi, sw. Two harts running
# them at the same time can both read the old value before either writes,
# and one update is lost (Docs, race-condition, shows the interleaving).
# amoadd.w does the read, the add and the write as one step that nothing
# can come between, and gives back the old value.
# With one hart both versions give the same answer here; what matters is
# that the amoadd is one instruction where the plain version is three.
# Watch the Memory tab: amoadd reads and writes the same word in one step.

    .section .text
    .globl _start
_start:
    # The unsafe way: three steps another hart could come between.
    la    t0, plain
    lw    t1, 0(t0)             # read 0
    addi  t1, t1, 1             # add
    sw    t1, 0(t0)             # write 1

    # The atomic way: one step.
    la    t0, counter
    li    t1, 1
    amoadd.w a1, t1, (t0)       # a1 = the old value 0; counter = 1
    amoadd.w a2, t1, (t0)       # a2 = 1; counter = 2

    lw    a0, 0(t0)             # a0 = 2
    add   a0, a0, a2            # + the old value the second amoadd returned (1) = 3
    ebreak

    .section .data
    .balign 4
plain:   .word 0
counter: .word 0
