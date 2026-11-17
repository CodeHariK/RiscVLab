package view

import clay "../../vendor/clay-odin"
import ui "../ui"
import state "../state"

// Panels and tabs. Everything the debugger shows is a tab (tab_*.odin); a
// panel is just a box that holds a list of tabs, with the selected one's
// content below them. A panel with a single tab shows its title instead
// of tab buttons. Which tabs each panel holds is the table below; where
// the panels sit is panel_layout.odin.

Tab :: enum {
	Source,      // the .s file with its comments (when the build made a line map)
	Disassembly, // the instructions decoded from memory
	Steps,       // every step taken so far
	Registers,   // pc and x0..x31
	Encoding,    // the next instruction's bit fields and effect
	Csrs,        // control and status registers, privilege level
	Memory,      // hex dump around the address being used
	Stack,       // the words from sp up to the top of the stack
	Elf,         // what the loader found in the program file
}

tab_titles := [Tab]string {
	.Source      = "Source",
	.Disassembly = "Disassembly",
	.Steps       = "Steps",
	.Registers   = "Registers",
	.Encoding    = "Encoding",
	.Csrs        = "CSRs",
	.Memory      = "Memory",
	.Stack       = "Stack",
	.Elf         = "ELF",
}

// Ids of the tab buttons, checked for clicks in input.odin.
tab_ids := [Tab]string {
	.Source      = "SourceTab",
	.Disassembly = "DisassemblyTab",
	.Steps       = "StepsTab",
	.Registers   = "RegistersTab",
	.Encoding    = "EncodingTab",
	.Csrs        = "CsrsTab",
	.Memory      = "MemoryTab",
	.Stack       = "StackTab",
	.Elf         = "ElfTab",
}

// Which tabs each panel holds, in order.
panel_tabs := [Panel][]Tab {
	.Code      = {.Source, .Disassembly, .Steps},
	.Registers = {.Registers},
	.Side      = {.Csrs, .Memory, .Stack, .Elf},
	.Encoding  = {.Encoding},
}

// The code tabs draw only the lines that fit and scroll themselves (see
// code_scroll.odin); the others are drawn whole and Clay scrolls them.
is_code_tab :: proc(tab: Tab) -> bool {
	return tab == .Source || tab == .Disassembly || tab == .Steps
}

// The tab `panel` shows: the selected one, except that without a source
// map the Source tab falls back to Disassembly.
shown_tab :: proc(session: ^state.Session, panel: Panel) -> Tab {
	tab := display.selected_tab[panel]
	if tab == .Source && !session.has_source {
		tab = .Disassembly
	}
	return tab
}

// Whether `tab` has a button in its panel right now.
tab_available :: proc(session: ^state.Session, tab: Tab) -> bool {
	return tab != .Source || session.has_source
}

// The area below a panel's header, where its tab's content goes.
tab_area_id :: proc(panel: Panel) -> clay.ElementId {
	return clay.ID("TabArea", u32(panel))
}

// The tab area being drawn, so a tab can size itself to it (from last
// frame's layout): see visible_lines and tab_source.
@(private)
current_tab_area: clay.ElementId

// Any panel: a header with its grip and tabs (or title), then the shown
// tab's content in an area that clips, and scrolls with the mouse wheel
// when the content is taller.
@(private)
draw_panel :: proc(session: ^state.Session, panel: Panel) {
	colors := ui.palette()
	shown := shown_tab(session, panel)
	tabs := panel_tabs[panel]
	// No clip on the panel itself: the tab area is the clipping element.
	if clay.UI(clay.ID("Panel", u32(panel)))(panel_style({clay.SizingGrow(), clay.SizingGrow()}, clip = false)) {
		if clay.UI(clay.ID("PanelHeader", u32(panel)))({layout = {childGap = 8, padding = {bottom = 8}, childAlignment = {y = .Center}}}) {
			panel_grip(panel)
			if len(tabs) == 1 {
				clay.TextDynamic(tab_titles[tabs[0]], ui.text_config(.Title, colors.title))
			} else {
				for tab in tabs {
					if tab_available(session, tab) {
						ui.tab(tab_ids[tab], tab_titles[tab], tab == shown)
					}
				}
			}
		}
		scroll := clay.Vector2{}
		if !is_code_tab(shown) {
			scroll = clay.GetScrollOffset()
		}
		current_tab_area = tab_area_id(panel)
		if clay.UI(current_tab_area)({
			layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom, childGap = 2},
			clip = {horizontal = true, vertical = true, childOffset = scroll},
		}) {
			draw_tab(session, shown)
		}
	}
}

@(private)
draw_tab :: proc(session: ^state.Session, tab: Tab) {
	switch tab {
	case .Source:
		tab_source(session)
	case .Disassembly:
		tab_disassembly(session)
	case .Steps:
		tab_steps(session)
	case .Registers:
		tab_registers(session)
	case .Encoding:
		tab_encoding(session)
	case .Csrs:
		tab_csrs(session)
	case .Memory:
		tab_memory(session)
	case .Stack:
		tab_stack(session)
	case .Elf:
		tab_elf(session)
	}
}
