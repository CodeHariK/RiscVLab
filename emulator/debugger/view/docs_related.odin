package view

import "core:slice"
import "core:strings"
import clay "../../vendor/clay-odin"
import ui "../ui"
import reference "../reference"
import state "../state"

// Links under a Docs entry, drawn with ui.link_rows (rows that wrap when
// they don't fit across the page):
//   - Related: the entries on its "Related:" line, drawn where that line
//     stands; clicking one pins that entry;
//   - Lessons: the lessons whose "# Docs:" line names the entry (from the
//     Programs window's list); clicking one opens that lesson and closes
//     the window, which reopens (D) on the entry.
// This file decides what the links are, gives them ids, and works out
// which one was clicked: modal_input.odin asks docs_link_under_pointer.

DOCS_RELATED_LINK_ID :: "DocsRelatedLink" // + docs_link_number(slot, item's position on the line)
DOCS_LESSON_LINK_ID :: "DocsLessonLink" // + docs_link_number(slot, catalog index)
// A link's id number holds the slot of the entry it is under (up to four
// are on the page at once) and which link it is, so the same link under
// two entries gets two ids. More than there will ever be links or programs:
DOCS_LINK_SLOT_STRIDE :: u32(1 << 16)

docs_link_number :: proc(slot: u32, target: int) -> u32 {
	return slot * DOCS_LINK_SLOT_STRIDE + u32(target)
}

// What a click on a link does.
Docs_Link_Target :: union {
	Docs_Entry_Link, // pin this entry
	Docs_Lesson_Link, // open this lesson
}
Docs_Entry_Link :: struct {
	entry:   int, // an index into reference.entries
	section: int, // an index into its sections, or -1 for its top
}
Docs_Lesson_Link :: struct {
	lesson: int, // an index into state.catalog.entries
	entry:  int, // the entry the link is under (to stay on)
}

// The Related line of `entry`, in page slot `slot`, as links (looked up
// once, by reference.load). An item that leads nowhere is plain text
// (reference_test.odin makes sure there are none). "entry#Section" shows
// as "entry: Section".
docs_related_links :: proc(entry: reference.Entry, slot: u32) {
	links := make([dynamic]ui.Link, 0, len(entry.related), context.temp_allocator)
	for item, at in entry.related {
		text, _ := strings.replace(item.text, "#", ": ", 1, context.temp_allocator)
		append(&links, ui.Link{text, clay.ID(DOCS_RELATED_LINK_ID, docs_link_number(slot, at)), item.target >= 0})
	}
	ui.link_rows("Related", links[:], DOCS_LABEL_WIDTH, docs_page_width())
}

// The lessons about entry `index`, as links ("19: Printing with the
// UART"); nothing if none is (or the debugger has no list of programs).
docs_lesson_links :: proc(index: int, slot: u32) {
	lessons := lessons_about(index)
	if len(lessons) == 0 {
		return
	}
	links := make([dynamic]ui.Link, 0, len(lessons), context.temp_allocator)
	for lesson in lessons {
		text := strings.trim_prefix(state.catalog.entries[lesson].title, "Lesson ")
		append(&links, ui.Link{text, clay.ID(DOCS_LESSON_LINK_ID, docs_link_number(slot, lesson)), true})
	}
	ui.link_rows("Lessons", links[:], DOCS_LABEL_WIDTH, docs_page_width())
}

// For each entry, the lessons whose "# Docs:" line names it: catalog
// indices, in catalog order. Worked out the first time it is needed (the
// list of programs and the docs are both loaded by then, and never
// change), not on every frame.
@(private = "file")
lessons_index: [][dynamic]int

// The catalog indices of the lessons about entry `index`.
@(private = "file")
lessons_about :: proc(index: int) -> []int {
	if lessons_index == nil {
		lessons_index = make([][dynamic]int, len(reference.entries))
		for program, at in state.catalog.entries {
			for name in program.docs {
				entry := reference.find(name)
				if entry >= 0 && !slice.contains(lessons_index[entry][:], at) {
					append(&lessons_index[entry], at)
				}
			}
		}
	}
	return lessons_index[index][:]
}

// The link under the mouse, for a click; nil if none. Uses last frame's
// layout, like every click.
docs_link_under_pointer :: proc(session: ^state.Session) -> Docs_Link_Target {
	for index, slot in docs_page_entries(session) {
		if index < 0 {
			continue
		}
		for item, at in reference.entries[index].related {
			if item.target >= 0 && clay.PointerOver(clay.ID(DOCS_RELATED_LINK_ID, docs_link_number(u32(slot), at))) {
				return Docs_Entry_Link{item.target, item.section}
			}
		}
		for lesson in lessons_about(index) {
			if clay.PointerOver(clay.ID(DOCS_LESSON_LINK_ID, docs_link_number(u32(slot), lesson))) {
				return Docs_Lesson_Link{lesson, index}
			}
		}
	}
	return nil
}

