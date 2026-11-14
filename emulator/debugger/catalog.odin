package rvdbg

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// The program selector's list: every program the debugger can open,
// found by looking in the tests/ folder (given with --tests):
//
//   Lessons      tests/programs/lessons/*.s   (built into programs/build/lessons/)
//   Tests        tests/programs/*.s           (built into programs/build/)
//   riscv-tests  tests/riscv-tests/build/rv64ui-p-*  (if built)
//
// Titles and descriptions come from the first two comment lines of each
// source file. Only programs that have been built are listed.

Catalog_Group :: enum {
	Lessons,
	Tests,
	Riscv_Tests,
}

catalog_group_names := [Catalog_Group]string {
	.Lessons     = "Lessons",
	.Tests       = "Test programs",
	.Riscv_Tests = "Official riscv-tests (rv64ui)",
}

Catalog_Entry :: struct {
	group:       Catalog_Group,
	title:       string,
	description: string,
	path:        string, // the ELF to load
}

Catalog :: struct {
	entries: [dynamic]Catalog_Entry,
}

// The list the debugger shows; empty when started without --tests.
catalog: Catalog

catalog_load :: proc(tests_root: string) {
	add_programs(.Lessons, fmt.aprintf("%s/programs/lessons", tests_root), fmt.aprintf("%s/programs/build/lessons", tests_root))
	add_programs(.Tests, fmt.aprintf("%s/programs", tests_root), fmt.aprintf("%s/programs/build", tests_root))
	add_riscv_tests(fmt.aprintf("%s/riscv-tests/build", tests_root))
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
		elf := fmt.aprintf("%s/%s.elf", build_dir, stem)
		if !os.exists(elf) {
			continue
		}
		title, description := read_header(fmt.tprintf("%s/%s", source_dir, name), stem)
		append(&catalog.entries, Catalog_Entry{group, title, description, elf})
	}
}

// riscv-tests have no description lines of their own; the file name says
// which instruction each one tests.
@(private = "file")
add_riscv_tests :: proc(build_dir: string) {
	for name in sorted_file_names(build_dir, "") {
		if !strings.has_prefix(name, "rv64ui-p-") || strings.contains(name, ".") {
			continue // skip the .s / .o / .dis files next to each test
		}
		instruction := strings.trim_prefix(name, "rv64ui-p-")
		append(
			&catalog.entries,
			Catalog_Entry {
				.Riscv_Tests,
				strings.clone(name),
				fmt.aprintf("official test for: %s", instruction),
				fmt.aprintf("%s/%s", build_dir, name),
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
			append(&names, strings.clone(info.name))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// Title and description from the first two "# " comment lines of a source
// file; the file name stands in when there is no header.
@(private = "file")
read_header :: proc(path: string, fallback: string) -> (title: string, description: string) {
	title = strings.clone(fallback)
	data, error := os.read_entire_file(path, context.temp_allocator)
	if error != nil {
		return title, ""
	}
	lines := strings.split_lines(string(data), context.temp_allocator)
	if len(lines) > 0 && strings.has_prefix(lines[0], "# ") {
		title = strings.clone(strings.trim_prefix(lines[0], "# "))
	}
	if len(lines) > 1 && strings.has_prefix(lines[1], "# ") {
		description = strings.clone(strings.trim_prefix(lines[1], "# "))
	}
	return title, description
}
