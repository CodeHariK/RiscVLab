# Lesson 09: Recursion and the stack
# sum(n) = n + sum(n - 1) calls itself, saving its return address and n on the stack each time.
# Expect: exit 15
# Docs: stack, sd, ret
#
# A call overwrites ra, so a function that calls another must save its own
# ra first. Values are saved on the stack: a region of memory the stack
# pointer sp points into. It grows down: subtract from sp to make room,
# add back to free it. Each call level gets its own 16 bytes (a "frame").
#
# Open the Stack tab to watch the frames being pushed and popped.

    .section .text
    .globl _start
_start:
    la   sp, stack_top      # the stack starts at the end of the reserved area
    addi a0, zero, 5
    jal  ra, sum            # a0 = sum(5)
    ebreak                  # a0 = 5 + 4 + 3 + 2 + 1 = 15

# sum(a0): returns a0 + (a0 - 1) + ... + 1
sum:
    beqz a0, sum_return     # sum(0) = 0: nothing to save
    addi sp, sp, -16        # make room for two 8-byte values
    sd   ra, 8(sp)          # save our return address (the call below overwrites ra)
    sd   a0, 0(sp)          # save n
    addi a0, a0, -1
    jal  ra, sum            # a0 = sum(n - 1)
    ld   t0, 0(sp)          # get n back
    add  a0, a0, t0         # a0 = n + sum(n - 1)
    ld   ra, 8(sp)          # get our return address back
    addi sp, sp, 16         # free the frame
sum_return:
    ret                     # back to whoever called us

    .section .bss
    .balign 16
stack:     .space 512       # 512 bytes reserved for the stack (zeroed, not stored in the file)
stack_top:
