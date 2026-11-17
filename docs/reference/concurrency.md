# Concurrency: atomics, locks and memory ordering

What happens when more than one hart (or an interrupt handler) uses the
same memory, from beginner to advanced, alongside lessons 16 (an atomic
counter), 17 (a spinlock) and 18 (lr / sc and compare-and-swap). Same format as instructions.md.

## race-condition - Race conditions

*beginner*

Does: a race condition is a bug where the result depends on the timing of two harts (or of a hart and an interrupt) using the same memory.

How it works: count = count + 1 is three instructions, `lw`, `addi`, `sw`. If two harts run them at the same time, both can read the old value before either writes:
| hart 0 | hart 1 | count |
|---|---|---|
| lw t0, 0(a0) | | 5 |
| | lw t0, 0(a0) | 5 |
| addi t0, t0, 1 | addi t0, t0, 1 | 5 |
| sw t0, 0(a0) | | 6 |
| | sw t0, 0(a0) | 6 (should be 7) |
One update is lost. It only happens when the timing is just wrong, so it appears rarely and randomly.

For: recognising when you need an atomic instruction or a lock: whenever data is written by one hart (or handler) and read or written by another.

Watch out:
- One hart is not automatically safe: an interrupt handler that touches the same data can run between any two instructions.
- Being careful in the code doesn't help: the hardware can switch between any two instructions, so the fix has to come from the hardware (an atomic instruction) or from a lock built on one.

Related: amoswap.w amoswap.d ... (the AMOs), locks, lr.w lr.d sc.w sc.d

## locks - Locks

*intermediate*

Does: a lock (mutex) lets one hart at a time run a section of code (the critical section), so a multi-step update of shared data can't interleave with another hart's.

How it works: a spinlock is one word: 0 free, 1 taken. Taking it must be atomic, or two harts could both see 0 and both take it. xv6's acquire() and release():
```
acquire:
    li           t1, 0x1
    amoswap.w.aq t2, t1, (a0)    # write 1 and get the old value, in one step
    bnez         t2, acquire     # it was already 1: someone else has it, spin
    ...                          # critical section: plain loads and stores are safe
    amoswap.w.rl zero, zero, (a0)  # release: write 0
```
Exactly one hart gets 0 back. The others keep swapping in 1 and getting 1 back ("spinning") until it is released.

For: everything shared in a kernel: xv6 has locks for the process table, the disk buffer cache, the console, the memory allocator.

Watch out:
- Interrupts: if an interrupt handler on the same hart tries to take a lock that hart already holds, it spins forever (deadlock). xv6's acquire() therefore turns interrupts off first (push_off) and release() turns them back on.
- Deadlock between locks: hart 0 holds A and waits for B while hart 1 holds B and waits for A. The usual rule is to always take locks in the same order.
- Spinning wastes the CPU. For long waits (a disk read), xv6 uses sleep locks, which give the CPU to another process instead.
- Hold a lock for as little code as possible.

Related: race-condition, amoswap.w amoswap.d ... (the AMOs), memory-ordering, lr.w lr.d sc.w sc.d

## memory-ordering - Memory ordering, fences, acquire and release

*advanced*

Does: explains why atomic instructions are not quite enough on real hardware, and what `fence`, `.aq` and `.rl` are for.

How it works: a program's loads and stores don't necessarily reach memory, or become visible to other harts, in the order the program wrote them. Real CPUs reorder them for speed: a store waits in a store buffer while later loads go ahead, caches deliver some writes to other cores before others, out-of-order cores run independent instructions early. Compilers reorder too. On one hart nothing can tell, since each hart always sees its own accesses in order. But another hart can:
```
hart 0                      hart 1
sw  t0, 0(data)   # data    loop: lw t1, 0(ready); beqz t1, loop
sw  t1, 0(ready)  # = 1     lw  t2, 0(data)      # may still see the OLD data
```
Hart 1 can see ready = 1 and still read stale data, because the two stores (or the two loads) were reordered.

The rules for what other harts may see are the memory model. RISC-V's is RVWMO (weak memory ordering): almost any reordering is allowed unless the program asks otherwise. x86 is stricter (TSO: stores stay in order). Weak models let hardware be simpler and faster; the program marks the places where order matters:
- `fence rw, rw`: no load or store before the fence may appear after any load or store after it. The operands say which kinds are ordered (r = read, w = write; i, o for devices). Hart 0 above needs `fence w, w` between its two stores; hart 1 needs `fence r, r` between its two loads.
- `.aq` (acquire) on an atomic: no later memory access may appear before it. Put it on the instruction that takes a lock, so the critical section can't leak above it.
- `.rl` (release) on an atomic: no earlier memory access may appear after it. Put it on the instruction that releases the lock, so the critical section's stores are visible before the lock reads as free.
- `.aqrl`: both.

xv6 uses gcc's `__sync_synchronize()`, which is a `fence rw, rw`, inside acquire() and release() for the same purpose.

For: any code shared between harts without a lock (flags, queues, lock-free data structures), and device drivers, where writes to device registers must happen in order (`fence` with i / o).

Emulator: this emulator runs one hart that does every access in order, so nothing is ever reordered: `fence`, `.aq` and `.rl` are decoded but do nothing, and the bugs above can't happen here. They can on QEMU with several harts and on real chips, which is why correct code needs them anyway.

Watch out: an atomic instruction alone makes one access indivisible; it says nothing about the order of the other loads and stores around it. That is what .aq / .rl and fence add.

Related: fence, locks, amoswap.w amoswap.d ... (the AMOs), lr.w lr.d sc.w sc.d
