package rvdbg

import "core:strings"

// The reference docs shown in the Docs window (docs_view.odin), read from
// docs/reference/*.md and embedded in the binary, so the same text reads
// well on GitHub and in the debugger.
//
// An entry starts with a heading naming what it covers, then a dash and a
// title, and runs until the next heading:
//
//   ## lb lh lw ld lbu lhu lwu - Load from memory
//
// The names are what the Docs window looks entries up by: for instructions,
// the mnemonic exactly as the disassembler prints it.

@(rodata)
embedded_instruction_docs := #load("../../docs/reference/instructions.md", string)
@(rodata)
embedded_pseudo_docs := #load("../../docs/reference/pseudo-instructions.md", string)
@(rodata)
embedded_directive_docs := #load("../../docs/reference/directives.md", string)
@(rodata)
embedded_csr_docs := #load("../../docs/reference/csrs.md", string)
@(rodata)
embedded_trap_docs := #load("../../docs/reference/traps.md", string)
@(rodata)
embedded_elf_docs := #load("../../docs/reference/elf.md", string)
@(rodata)
embedded_term_docs := #load("../../docs/reference/terms.md", string)

// Which file an entry comes from; the Docs window's list is grouped by it.
Doc_Group :: enum {
	Instructions,
	Pseudo_Instructions,
	Directives,
	Csrs,
	Traps,
	Elf,
	Terms,
}

doc_group_names := [Doc_Group]string {
	.Instructions        = "Instructions",
	.Pseudo_Instructions = "Pseudo-instructions",
	.Directives          = "Assembler directives",
	.Csrs                = "CSRs",
	.Traps               = "Traps and privilege",
	.Elf                 = "ELF and memory",
	.Terms               = "Terms",
}

Doc_Entry :: struct {
	group: Doc_Group,
	names: []string, // e.g. {"lb", "lh", ...}; point into the embedded text
	title: string, // "Load from memory"
	lines: []string, // the body, without trailing blank lines
	// Heading and body in lower case, for the search (search.odin).
	search_heading: string,
	search_body: string,
}

Docs :: struct {
	entries: [dynamic]Doc_Entry,
}

docs: Docs

// Splits the embedded files into entries. Called once at startup.
docs_load :: proc() {
	docs_add_file(embedded_instruction_docs, .Instructions)
	docs_add_file(embedded_pseudo_docs, .Pseudo_Instructions)
	docs_add_file(embedded_directive_docs, .Directives)
	docs_add_file(embedded_csr_docs, .Csrs)
	docs_add_file(embedded_trap_docs, .Traps)
	docs_add_file(embedded_elf_docs, .Elf)
	docs_add_file(embedded_term_docs, .Terms)
}

docs_destroy :: proc() {
	for entry in docs.entries {
		delete(entry.names)
		delete(entry.lines)
		delete(entry.search_heading)
		delete(entry.search_body)
	}
	delete(docs.entries)
}

// The entry covering `name` (e.g. "lw"), or -1.
docs_find :: proc(name: string) -> int {
	for entry, index in docs.entries {
		for entry_name in entry.names {
			if entry_name == name {
				return index
			}
		}
	}
	return -1
}

// Entry indices that match the docs search: entries whose heading matches
// first, then those where only the body does. All of them, in order, when
// the search is empty.
docs_filtered :: proc() -> []int {
	query := search_text(&view.docs_search)
	matches := make([dynamic]int, context.temp_allocator)
	for entry, index in docs.entries {
		if search_matches(query, entry.search_heading) {
			append(&matches, index)
		}
	}
	if query == "" {
		return matches[:]
	}
	for entry, index in docs.entries {
		if !search_matches(query, entry.search_heading) && search_matches(query, entry.search_body) {
			append(&matches, index)
		}
	}
	return matches[:]
}

// "lb lh lw ... - Load from memory": the entry's heading, for lists.
docs_heading :: proc(entry: Doc_Entry) -> string {
	return strings.concatenate({strings.join(entry.names, " ", context.temp_allocator), " - ", entry.title}, context.temp_allocator)
}

@(private = "file")
docs_add_file :: proc(text: string, group: Doc_Group) {
	lines := strings.split_lines(text)
	defer delete(lines)

	current := -1
	body: [dynamic]string
	for line in lines {
		if strings.has_prefix(line, "## ") {
			docs_finish_entry(current, &body)
			current = docs_start_entry(line[3:], group)
			continue
		}
		if current >= 0 {
			append(&body, line)
		}
	}
	docs_finish_entry(current, &body)
	delete(body)
}

@(private = "file")
docs_start_entry :: proc(heading: string, group: Doc_Group) -> int {
	names_part, title := heading, ""
	if dash := strings.index(heading, " - "); dash >= 0 {
		names_part, title = heading[:dash], heading[dash + 3:]
	}
	append(&docs.entries, Doc_Entry{group = group, names = strings.fields(names_part), title = title})
	return len(docs.entries) - 1
}

// Gives the entry its body (trailing blank lines dropped) and empties
// `body` for the next one.
@(private = "file")
docs_finish_entry :: proc(index: int, body: ^[dynamic]string) {
	if index < 0 {
		return
	}
	end := len(body)
	for end > 0 && strings.trim_space(body[end - 1]) == "" {
		end -= 1
	}
	start := 0
	for start < end && strings.trim_space(body[start]) == "" {
		start += 1
	}
	lines := make([]string, end - start)
	copy(lines, body[start:end])
	entry := &docs.entries[index]
	entry.lines = lines
	heading := strings.join({strings.join(entry.names, " ", context.temp_allocator), entry.title}, " ", context.temp_allocator)
	entry.search_heading = strings.to_lower(heading)
	entry.search_body = strings.to_lower(strings.join(lines, " ", context.temp_allocator))
	clear(body)
}
