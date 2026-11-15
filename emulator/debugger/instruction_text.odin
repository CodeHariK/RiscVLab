package rvdbg

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
	}
	return "?"
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
