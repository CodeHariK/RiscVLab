package reference

import "core:strings"
import ui "../ui"

// The reference docs shown in the Docs window (view/window_docs.odin), read from
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
//
// An entry can have sections, each starting with a "### Title" line
// (the encodings and emulator pages do).
//
// An entry's "Related: a, b c, d" line lists other entries, separated by
// commas. Each item names its entry by its first word ("lb lh lw ld" is
// the entry for lb), so an item can show a whole group, or add a note in
// brackets ("amoswap.w ... (the AMOs)"). "entry#Section" leads to a section
// of that entry: Section is its "### " title up to any " (", so
// "encodings#Loads and stores" finds "### Loads and stores (rv64i_load_store.odin)".
// The Docs window draws them as links; reference_test.odin checks every
// one leads somewhere.
//
// Everything is worked out once, by load: each entry's names go into an
// index (find), its sections into a list, and its Related items are
// looked up, so drawing the Docs window never searches the text.

@(rodata)
embedded_start_docs := #load("../../../docs/reference/start.md", string)
@(rodata)
embedded_instruction_docs := #load("../../../docs/reference/instructions.md", string)
@(rodata)
embedded_encoding_docs := #load("../../../docs/reference/encodings.md", string)
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
embedded_memory_docs := #load("../../../docs/reference/memory.md", string)
@(rodata)
embedded_device_docs := #load("../../../docs/reference/devices.md", string)
@(rodata)
embedded_emulator_docs := #load("../../../docs/reference/emulator.md", string)
@(rodata)
embedded_term_docs := #load("../../../docs/reference/terms.md", string)

// Which file an entry comes from; the Docs window's list is grouped by it.
Group :: enum {
	Start,
	Encodings,
	Emulator,
	Instructions,
	Pseudo_Instructions,
	Directives,
	Csrs,
	Traps,
	Concurrency,
	Elf,
	Memory,
	Devices,
	Terms,
}

group_names := [Group]string {
	.Start               = "Start here",
	.Encodings           = "Instruction encodings",
	.Emulator            = "The emulator",
	.Instructions        = "Instructions",
	.Pseudo_Instructions = "Pseudo-instructions",
	.Directives          = "Assembler directives",
	.Csrs                = "CSRs",
	.Traps               = "Traps and privilege",
	.Concurrency         = "Atomics, locks, ordering",
	.Elf                 = "ELF files",
	.Memory              = "Memory",
	.Devices             = "Devices",
	.Terms               = "Terms",
}

Entry :: struct {
	group: Group,
	names: []string, // e.g. {"lb", "lh", ...}; point into the embedded text
	title: string, // "Load from memory"
	lines: []string, // the body, without trailing blank lines
	// The "### " section titles, in order, up to any " (": what
	// "entry#Section" links name.
	sections: []string,
	// The items on its "Related:" line, looked up.
	related: []Related,
	// Heading and body in lower case, for the search (ui/search.odin, filter below).
	search_heading: string,
	search_body: string,
}

// One item of a Related line: the text as written, and where it leads.
Related :: struct {
	text:    string,
	target:  int, // an index into entries, or -1 if it names none
	section: int, // an index into the target's sections, or -1 for its top
}

// Every entry, in file order (load fills it).
entries: [dynamic]Entry

// Every entry name -> its entry (load fills it). The first entry with a
// name keeps it (reference_test.odin makes sure no two share one).
@(private = "file")
names_index: map[string]int

// Splits the embedded files into entries. Called once at startup.
load :: proc() {
	add_file(embedded_start_docs, .Start)
	add_file(embedded_encoding_docs, .Encodings)
	add_file(embedded_emulator_docs, .Emulator)
	add_file(embedded_instruction_docs, .Instructions)
	add_file(embedded_pseudo_docs, .Pseudo_Instructions)
	add_file(embedded_directive_docs, .Directives)
	add_file(embedded_csr_docs, .Csrs)
	add_file(embedded_trap_docs, .Traps)
	add_file(embedded_concurrency_docs, .Concurrency)
	add_file(embedded_elf_docs, .Elf)
	add_file(embedded_memory_docs, .Memory)
	add_file(embedded_device_docs, .Devices)
	add_file(embedded_term_docs, .Terms)

	for entry, index in entries {
		for name in entry.names {
			if name not_in names_index {
				names_index[name] = index
			}
		}
	}
	// Only now can Related items be looked up: they name entries from any
	// file.
	for &entry in entries {
		entry.related = resolve_related(entry)
	}
}

destroy :: proc() {
	for entry in entries {
		delete(entry.names)
		delete(entry.lines)
		delete(entry.sections)
		delete(entry.related)
		delete(entry.search_heading)
		delete(entry.search_body)
	}
	delete(entries)
	delete(names_index)
}

// The entry covering `name` (e.g. "lw"), or -1.
find :: proc(name: string) -> int {
	return names_index[name] or_else -1
}

// The section of entry `index` titled `title` (as in "entry#Section"), or -1.
find_section :: proc(index: int, title: string) -> int {
	for section, at in entries[index].sections {
		if section == title {
			return at
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

// Looks up the items on the entry's "Related:" line (none if it has no
// such line). An item leads to the entry its first word names, and with
// "#Section", to that section of it.
@(private = "file")
resolve_related :: proc(entry: Entry) -> []Related {
	for line in entry.lines {
		if !strings.has_prefix(line, RELATED_LABEL) {
			continue
		}
		items := strings.split(line[len(RELATED_LABEL):], ",", context.temp_allocator)
		related := make([]Related, len(items))
		for item, at in items {
			text := strings.trim_space(item)
			name, section := text, ""
			if hash := strings.index_byte(text, '#'); hash >= 0 {
				name, section = text[:hash], text[hash + 1:]
			}
			related[at] = {text = text, target = -1, section = -1}
			words := strings.fields(name, context.temp_allocator)
			if len(words) == 0 {
				continue
			}
			related[at].target = find(words[0])
			if related[at].target >= 0 && section != "" {
				related[at].section = find_section(related[at].target, section)
				if related[at].section < 0 {
					related[at].target = -1 // a section that isn't there leads nowhere
				}
			}
		}
		return related
	}
	return nil
}

// The "Related:" line's start.
RELATED_LABEL :: "Related:"

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

// The "### " titles in `lines`, each cut at " (" if it has one.
@(private = "file")
section_titles :: proc(lines: []string) -> []string {
	titles := make([dynamic]string)
	for line in lines {
		if strings.has_prefix(line, SECTION_PREFIX) {
			append(&titles, section_name(line[len(SECTION_PREFIX):]))
		}
	}
	return titles[:]
}

// A "### " heading's text, as "entry#Section" names it: up to any " (".
section_name :: proc(heading: string) -> string {
	if bracket := strings.index(heading, " ("); bracket >= 0 {
		return heading[:bracket]
	}
	return heading
}

// The start of a section heading inside an entry.
SECTION_PREFIX :: "### "

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
	entry.sections = section_titles(lines)
	heading := strings.join({strings.join(entry.names, " ", context.temp_allocator), entry.title}, " ", context.temp_allocator)
	entry.search_heading = strings.to_lower(heading)
	entry.search_body = strings.to_lower(strings.join(lines, " ", context.temp_allocator))
	clear(body)
}
