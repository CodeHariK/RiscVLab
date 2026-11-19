package reference

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:testing"

// Checks on the docs themselves, run by `make test` (`make docs-check`),
// so a renamed or mistyped entry name shows up at once rather than as a
// link that does nothing in the Docs window:
//   - every entry has a "Does:" and a "Related:" line;
//   - no two entries share a name (find would pick the first);
//   - every Related item leads to an entry (and its #Section to a section);
//   - every lesson has a "# Docs:" line, and every name on it is an entry;
//   - the docs are plain ASCII.

// Parses the docs once, for every test (they only read them). The tests
// run on several threads, so the first one to get here does it. Kept on
// the heap rather than in that test's allocator: they outlive the test.
@(private = "file")
loaded: sync.Once

@(private = "file")
load_once :: proc() {
	sync.once_do(&loaded, proc() {
		context.allocator = runtime.heap_allocator()
		load()
	})
}

@(test)
entries_have_does_and_related :: proc(t: ^testing.T) {
	load_once()
	for entry in entries {
		has_does, has_related := false, false
		for line in entry.lines {
			has_does ||= strings.has_prefix(line, "Does:")
			has_related ||= strings.has_prefix(line, RELATED_LABEL)
		}
		testing.expectf(t, has_does, "%s: no Does: line", entry_heading(entry))
		testing.expectf(t, has_related, "%s: no Related: line", entry_heading(entry))
	}
}

@(test)
names_are_unique :: proc(t: ^testing.T) {
	load_once()
	for entry, index in entries {
		for name in entry.names {
			testing.expectf(t, find(name) == index, "%s: the name %s is also used by %s", entry_heading(entry), name, entry_heading(entries[find(name)]))
		}
	}
}

@(test)
related_items_lead_to_entries :: proc(t: ^testing.T) {
	load_once()
	for entry in entries {
		for item in entry.related {
			testing.expectf(t, item.target >= 0, "%s: Related item %q leads nowhere (its first word must be an entry's name, and a #Section one of that entry's ### headings)", entry_heading(entry), item.text)
		}
	}
}

// The lessons, read at compile time (the Docs window reads the open
// program's source instead).
lesson_files := #load_directory("../../../tests/programs/lessons")

@(test)
lessons_name_entries :: proc(t: ^testing.T) {
	load_once()
	for file in lesson_files {
		if !strings.has_suffix(file.name, ".s") {
			continue
		}
		docs_line := ""
		for line in strings.split_lines(string(file.data), context.temp_allocator) {
			if strings.has_prefix(line, "# Docs:") {
				docs_line = line[len("# Docs:"):]
				break
			}
		}
		testing.expectf(t, docs_line != "", "%s: no # Docs: line", file.name)
		for item in strings.split(docs_line, ",", context.temp_allocator) {
			name := strings.trim_space(item)
			testing.expectf(t, find(name) >= 0, "%s: # Docs: %q is not an entry name", file.name, name)
		}
	}
}

@(test)
docs_are_plain_ascii :: proc(t: ^testing.T) {
	reference_files := [?]struct {
		name, text: string,
	} {
		{"start.md", embedded_start_docs},
		{"instructions.md", embedded_instruction_docs},
		{"encodings.md", embedded_encoding_docs},
		{"pseudo-instructions.md", embedded_pseudo_docs},
		{"directives.md", embedded_directive_docs},
		{"csrs.md", embedded_csr_docs},
		{"traps.md", embedded_trap_docs},
		{"concurrency.md", embedded_concurrency_docs},
		{"elf.md", embedded_elf_docs},
		{"devices.md", embedded_device_docs},
		{"emulator.md", embedded_emulator_docs},
		{"terms.md", embedded_term_docs},
	}
	for file in reference_files {
		expect_ascii(t, file.text, file.name)
	}
}

// Reports the first line of `text` (from file `name`) with a byte outside
// ASCII.
@(private = "file")
expect_ascii :: proc(t: ^testing.T, text: string, name: string) {
	for line, index in strings.split_lines(text, context.temp_allocator) {
		for i in 0 ..< len(line) {
			if line[i] >= 0x80 {
				testing.expectf(t, false, "%s line %d is not plain ASCII: %s", name, index + 1, line)
				return
			}
		}
	}
}
