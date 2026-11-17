package view

import "core:strings"

// Small helpers for describing an instruction in words, from its
// mnemonic (as the disassembler prints it).

// "lw" from "lw t2,0(t0)".
first_word :: proc(text: string) -> string {
	if space := strings.index_byte(text, ' '); space >= 0 {
		return text[:space]
	}
	return text
}

// SLL / SRL / SRA and their I and W forms.
is_shift :: proc(mnemonic: string) -> bool {
	return strings.has_prefix(mnemonic, "sll") || strings.has_prefix(mnemonic, "srl") || strings.has_prefix(mnemonic, "sra")
}

// The *W instructions compute on 32 bits and sign-extend the result.
word_note :: proc(mnemonic: string) -> string {
	return ", on the low 32 bits, then sign-extended" if strings.has_suffix(mnemonic, "w") else ""
}

// Maps an arithmetic mnemonic (any of its I / W variants) to an operator.
operator :: proc(mnemonic: string) -> string {
	switch mnemonic {
	case "add", "addi", "addw", "addiw":
		return "+"
	case "sub", "subw":
		return "-"
	case "and", "andi":
		return "&"
	case "or", "ori":
		return "|"
	case "xor", "xori":
		return "^"
	case "sll", "slli", "sllw", "slliw":
		return "<<"
	case "srl", "srli", "srlw", "srliw":
		return ">> (logical, fills with zeros)"
	case "sra", "srai", "sraw", "sraiw":
		return ">> (arithmetic, keeps the sign)"
	case "mul", "mulw", "mulh", "mulhsu", "mulhu":
		return "*"
	case "div", "divu", "divw", "divuw":
		return "/"
	case "rem", "remu", "remw", "remuw":
		return "%"
	}
	return "?"
}

// What else an M instruction does to its result: which half of the
// product, signed or unsigned, and the defined results for divide by zero
// and overflow (`b` is the divisor). "" for everything else.
muldiv_note :: proc(mnemonic: string, a: u64, b: u64) -> string {
	switch mnemonic {
	case "mulh":
		return " (the high 64 bits of the 128-bit product, signed x signed)"
	case "mulhsu":
		return " (the high 64 bits of the 128-bit product, signed x unsigned)"
	case "mulhu":
		return " (the high 64 bits of the 128-bit product, unsigned x unsigned)"
	case "mul":
		return " (the low 64 bits of the product)"
	}
	is_divide := strings.has_prefix(mnemonic, "div") || strings.has_prefix(mnemonic, "rem")
	if !is_divide {
		return ""
	}
	word := strings.has_suffix(mnemonic, "w")
	divisor_zero := b == 0 if !word else u32(b) == 0
	if divisor_zero {
		if strings.has_prefix(mnemonic, "div") {
			return ": divide by zero gives all ones (defined, no trap)"
		}
		return ": divide by zero gives the dividend (defined, no trap)"
	}
	signed := !strings.has_suffix(strings.trim_suffix(mnemonic, "w"), "u")
	overflow := (i64(a) == min(i64) && i64(b) == -1) if !word else (i32(u32(a)) == min(i32) && i32(u32(b)) == -1)
	if signed && overflow {
		return ": overflow (the answer doesn't fit), defined as the dividend / 0"
	}
	if signed {
		return " (signed, rounds toward zero)"
	}
	return " (unsigned)"
}

// The comparison a branch makes, and whether it will be taken now.
branch_comparison :: proc(mnemonic: string, a: u64, b: u64) -> (text: string, taken: bool) {
	switch mnemonic {
	case "beq":
		return "==", a == b
	case "bne":
		return "!=", a != b
	case "blt":
		return "< (signed)", i64(a) < i64(b)
	case "bge":
		return ">= (signed)", i64(a) >= i64(b)
	case "bltu":
		return "< (unsigned)", a < b
	case "bgeu":
		return ">= (unsigned)", a >= b
	}
	return "?", false
}
