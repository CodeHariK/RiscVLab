package view

import "core:fmt"

// How numbers are written everywhere in the debugger: always hex, so values
// can be compared at a glance across panels. A value small enough to read
// as a plain number also gets its decimal in brackets:
//
//     0x6e (110)    0xffffffffffffffff (-1)    0x80001000    0x4
//
// 0x0 - 0x9 read the same in both bases, so they get no bracket. Counts
// (steps, instructions, bytes, line numbers) stay plain decimal; they are
// not values the program computes. The Encoding strip still shows each
// field's bits in binary, since the bit layout is what it teaches.

// Below this (as a signed number) a value is "small" and gets a decimal.
SMALL_VALUE_LIMIT :: 0x10000

// A 64-bit value, as short as possible: 0x6e (110).
value_text :: proc(value: u64) -> string {
	return fmt.tprintf("0x%x%s", value, decimal_suffix(value))
}

// A full register: all 16 hex digits, 0x000000000000006e (110).
register_value_text :: proc(value: u64) -> string {
	return fmt.tprintf("0x%016x%s", value, decimal_suffix(value))
}

// A signed amount (immediate, offset) with its sign in front: -0x14 (-20).
signed_text :: proc(value: i64) -> string {
	magnitude := u64(value) if value >= 0 else u64(0) - u64(value)
	sign := "-" if value < 0 else ""
	if magnitude >= 10 && magnitude < SMALL_VALUE_LIMIT {
		return fmt.tprintf("%s0x%x (%d)", sign, magnitude, value)
	}
	return fmt.tprintf("%s0x%x", sign, magnitude)
}

// " (110)" for a small value read as signed, "" otherwise.
@(private)
decimal_suffix :: proc(value: u64) -> string {
	signed := i64(value)
	if (signed >= 10 && signed < SMALL_VALUE_LIMIT) || (signed < 0 && signed > -SMALL_VALUE_LIMIT) {
		return fmt.tprintf(" (%d)", signed)
	}
	return ""
}
