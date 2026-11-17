package reference

import "core:strings"
import ui "../ui"

// The reference docs shown in the Docs window (../docs_view.odin), read from
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
embedded_instruction_docs := #load("../../../docs/reference/instructions.md", string)
@(rodata)
embedded_pseudo_docs := #load("../../../docs/reference/pseudo-instructions.md", string)
@(rodata)
embedded_directive_docs := #load("../../../docs/reference/directives.md", string)
@(rodata)
embedded_csr_docs := #load("../../../docs/reference/csrs.md", string)
@(rodata)
embedded_trap_docs := #load("../../../docs/reference/traps.md", string)
@(rodata)
embedded_concurrency_docs := #load("../../../docs/reference/concurrency.md", string)
@(rodata)
embedded_elf_docs := #load("../../../docs/reference/elf.md", string)
@(rodata)
embedded_term_docs := #load("../../../docs/reference/terms.md", string)

// Which file an entry comes from; the Docs window's list is grouped by it.
Group :: enum {
	Instructions,
	Pseudo_Instructions,
	Directives,
	Csrs,
	Traps,
	Concurrency,
	Elf,
	Terms,
}

group_names := [Group]string {
	.Instructions        = "Instructions",
	.Pseudo_Instructions = "Pseudo-instructions",
	.Directives          = "Assembler directives",
	.Csrs                = "CSRs",
	.Traps               = "Traps and privilege",
	.Concurrency         = "Atomics, locks, ordering",
	.Elf                 = "ELF and memory",
	.Terms               = "Terms",
}

Entry :: struct {
	group: Group,
	names: []string, // e.g. {"lb", "lh", ...}; point into the embedded text
	title: string, // "Load from memory"
	lines: []string, // the body, without trailing blank lines
	// Heading and body in lower case, for the search (ui/search.odin).
	search_heading: string,
	search_body: string,
}

// Every entry, in file order (load fills it).
entries: [dynamic]Entry

// Splits the embedded files into entries. Called once at startup.
load :: proc() {
	add_file(embedded_instruction_docs, .Instructions)
	add_file(embedded_pseudo_docs, .Pseudo_Instructions)
	add_file(embedded_directive_docs, .Directives)
	add_file(embedded_csr_docs, .Csrs)
	add_file(embedded_trap_docs, .Traps)
	add_file(embedded_concurrency_docs, .Concurrency)
	add_file(embedded_elf_docs, .Elf)
	add_file(embedded_term_docs, .Terms)
}

destroy :: proc() {
	for entry in entries {
		delete(entry.names)
		delete(entry.lines)
		delete(entry.search_heading)
		delete(entry.search_body)
	}
	delete(entries)
}

// The entry covering `name` (e.g. "lw"), or -1.
find :: proc(name: string) -> int {
	for entry, index in entries {
		for entry_name in entry.names {
			if entry_name == name {
				return index
			}
		}
	}
	return -1
}

// Entry indices that match `query` (a search box's text): entries whose heading matches
// first, then those where only the body does. All of them, in order, when
// the search is empty.
filter :: proc(query: string) -> []int {
	matches := make([dynamic]int, context.temp_allocator)
	for entry, index in entries {
		if ui.search_matches(query, entry.search_heading) {
			append(&matches, index)
		}
	}
	if query == "" {
		return matches[:]
	}
	for entry, index in entries {
		if !ui.search_matches(query, entry.search_heading) && ui.search_matches(query, entry.search_body) {
			append(&matches, index)
		}
	}
	return matches[:]
}

// "lb lh lw ... - Load from memory": the entry's heading, for lists.
entry_heading :: proc(entry: Entry) -> string {
	return strings.concatenate({strings.join(entry.names, " ", context.temp_allocator), " - ", entry.title}, context.temp_allocator)
}

@(private = "file")
add_file :: proc(text: string, group: Group) {
	lines := strings.split_lines(text)
	defer delete(lines)

	current := -1
	body: [dynamic]string
	for line in lines {
		if strings.has_prefix(line, "## ") {
			finish_entry(current, &body)
			current = start_entry(line[3:], group)
			continue
		}
		if current >= 0 {
			append(&body, line)
		}
	}
	finish_entry(current, &body)
	delete(body)
}

@(private = "file")
start_entry :: proc(heading: string, group: Group) -> int {
	names_part, title := heading, ""
	if dash := strings.index(heading, " - "); dash >= 0 {
		names_part, title = heading[:dash], heading[dash + 3:]
	}
	append(&entries, Entry{group = group, names = strings.fields(names_part), title = title})
	return len(entries) - 1
}

// Gives the entry its body (trailing blank lines dropped) and empties
// `body` for the next one.
@(private = "file")
finish_entry :: proc(index: int, body: ^[dynamic]string) {
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
	entry := &entries[index]
	entry.lines = lines
	heading := strings.join({strings.join(entry.names, " ", context.temp_allocator), entry.title}, " ", context.temp_allocator)
	entry.search_heading = strings.to_lower(heading)
	entry.search_body = strings.to_lower(strings.join(lines, " ", context.temp_allocator))
	clear(body)
}
