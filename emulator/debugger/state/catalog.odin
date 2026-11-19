package state

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// The program selector's list: every program the debugger can open,
// found by looking in the tests/ folder (given with --tests):
//
//   Lessons      tests/programs/lessons/*.s   (built into programs/build/lessons/)
//   Tests        tests/programs/*.s           (built into programs/build/)
//   riscv-tests  tests/riscv-tests/build/rv64ui-p-*, rv64um-p-*, rv64ua-p-*  (if built)
//
// Titles and descriptions come from the first two comment lines of each
// source file, and a lesson's Docs entries from its "# Docs:" line. Only
// programs that have been built are listed.

Catalog_Group :: enum {
	Lessons,
	Tests,
	Riscv_Tests,
}

catalog_group_names := [Catalog_Group]string {
	.Lessons     = "Lessons",
	.Tests       = "Test programs",
	.Riscv_Tests = "Official riscv-tests (rv64ui, rv64um, rv64ua)",
}

Catalog_Entry :: struct {
	group:       Catalog_Group,
	title:       string,
	description: string,
	path:        string, // the ELF to load
	// The names on the source's "# Docs:" line (lessons have one): the
	// Docs entries it is about. The Docs window links each entry back.
	docs:        []string,
}

Catalog :: struct {
	entries: [dynamic]Catalog_Entry,
}

// The list the debugger shows; empty when started without --tests.
catalog: Catalog

catalog_load :: proc(tests_root: string) {
	// Folder names are only needed while loading; entries keep copies of
	// what they use.
	add_programs(.Lessons, fmt.tprintf("%s/programs/lessons", tests_root), fmt.tprintf("%s/programs/build/lessons", tests_root))
	add_programs(.Tests, fmt.tprintf("%s/programs", tests_root), fmt.tprintf("%s/programs/build", tests_root))
	add_riscv_tests(fmt.tprintf("%s/riscv-tests/build", tests_root))
}

// Index of the entry with this path, or -1.
catalog_find :: proc(path: string) -> int {
	for entry, index in catalog.entries {
		if entry.path == path {
			return index
		}
	}
	return -1
}

// Every `<name>.s` in `source_dir` whose `<name>.elf` exists in `build_dir`.
@(private = "file")
add_programs :: proc(group: Catalog_Group, source_dir: string, build_dir: string) {
	for name in sorted_file_names(source_dir, ".s") {
		stem := strings.trim_suffix(name, ".s")
		elf := fmt.tprintf("%s/%s.elf", build_dir, stem)
		if !os.exists(elf) {
			continue
		}
		elf = strings.clone(elf)
		header := read_header(fmt.tprintf("%s/%s", source_dir, name), stem)
		append(&catalog.entries, Catalog_Entry{group = group, title = header.title, description = header.description, path = elf, docs = header.docs})
	}
}

// riscv-tests have no description lines of their own; the file name says
// which instruction each one tests.
@(private = "file")
add_riscv_tests :: proc(build_dir: string) {
	for name in sorted_file_names(build_dir, "") {
		is_test := strings.has_prefix(name, "rv64ui-p-") || strings.has_prefix(name, "rv64um-p-") || strings.has_prefix(name, "rv64ua-p-")
		if !is_test || strings.contains(name, ".") {
			continue // skip the .s / .o / .dis files next to each test
		}
		instruction := name[len("rv64ui-p-"):] // all prefixes have this length
		append(
			&catalog.entries,
			Catalog_Entry {
				group = .Riscv_Tests,
				title = strings.clone(name),
				description = fmt.aprintf("official test for: %s", instruction),
				path = fmt.aprintf("%s/%s", build_dir, name),
			},
		)
	}
}

// File names in `dir` ending in `suffix`, sorted. Empty if `dir` is missing.
@(private = "file")
sorted_file_names :: proc(dir: string, suffix: string) -> []string {
	infos, error := os.read_all_directory_by_path(dir, context.temp_allocator)
	if error != nil {
		return nil
	}
	names := make([dynamic]string, context.temp_allocator)
	for info in infos {
		if info.type == .Regular && strings.has_suffix(info.name, suffix) {
			append(&names, strings.clone(info.name, context.temp_allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// What a source file's header says (a lesson's, for example):
//
//   # Lesson 19: Printing with the UART      title
//   # A program prints by storing bytes ...   description
//   # Expect: exit 13                         (for run_lessons.sh)
//   # Docs: uart, mmio, lbu, sb               docs
@(private = "file")
Header :: struct {
	title:       string,
	description: string,
	docs:        []string,
}

// How far into a source file its header can reach.
HEADER_LINES :: 10

// Reads a source file's header; the file name stands in for a missing
// title.
@(private = "file")
read_header :: proc(path: string, fallback: string) -> (header: Header) {
	header.title = strings.clone(fallback)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return header
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	if len(lines) > 0 && strings.has_prefix(lines[0], "# ") {
		delete(header.title)
		header.title = strings.clone(strings.trim_prefix(lines[0], "# "))
	}
	if len(lines) > 1 && strings.has_prefix(lines[1], "# ") {
		header.description = strings.clone(strings.trim_prefix(lines[1], "# "))
	}
	for line in lines[:min(len(lines), HEADER_LINES)] {
		if strings.has_prefix(line, "# Docs:") {
			names := strings.split(line[len("# Docs:"):], ",")
			for &name in names {
				name = strings.clone(strings.trim_space(name))
			}
			header.docs = names
			break
		}
	}
	return header
}
