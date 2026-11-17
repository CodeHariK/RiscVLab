package view

import "core:fmt"
import clay "../../vendor/clay-odin"
import rl "vendor:raylib"
import ui "../ui"
import state "../state"

// The debugger window, described with Clay:
//
//   +------------------------------------------------------------+
//   | [Reset] [Prev] [Next]   program   step   pc   status       |  toolbar
//   +-----------------------------------+------------------------+
//   | [Source][Disassembly][Steps]      | [CSRs][Memory][ELF]    |
//   | (current instruction highlighted) | tab content, scrolls   |
//   +-----------------------------------+ with the mouse wheel   |
//   +-------------------------------------+----------------------+
//   | Encoding: the next instruction as   | Console: what the    |
//   | colour-coded bit fields, then what  | program printed      |
//   | it reads, computes and writes       | (the UART)           |
//   +-------------------------------------+----------------------+
//
// This file draws the frame: toolbar, the panel slots and the dividers
// between them, and panel grips. Every panel is drawn the same way
// (panel.odin), its content is a tab (tab_*.odin); each window has its
// own file (window_*.odin).
//
// Built from scratch every frame from the session state; strings use the
// temp allocator, freed once the frame is drawn.

// The code tabs show as many lines as fit (see code_scroll.odin for how
// they scroll). Heights in pixels, matching the styles used below.
CODE_LINE_HEIGHT :: 24 // Code font (18) + line padding (4) + gap (2)
SOURCE_LINE_HEIGHT :: 22 // Code_Small font (16) + line padding (4) + gap (2)
CODE_LINES_DEFAULT :: 20 // first frame, before the panel has a size

build_layout :: proc(session: ^state.Session, frame_time: f32) -> clay.ClayArray(clay.RenderCommand) {
	colors := ui.palette()
	clay.BeginLayout()
	if clay.UI(clay.ID("Root"))({
		layout = {
			sizing = {clay.SizingGrow(), clay.SizingGrow()},
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(ui.PANEL_GAP),
			childGap = ui.PANEL_GAP,
		},
		backgroundColor = colors.background,
	}) {
		toolbar(session)
		panel_area(session)
	}
	if panel, dragging := panel_layout.dragging_panel.?; dragging {
		drag_label(panel)
	}
	programs_modal(session)
	docs_modal(session)
	return clay.EndLayout(frame_time)
}

// The columns, the bottom panel and the dividers between them (see
// panel_layout.odin).
@(private)
panel_area :: proc(session: ^state.Session) {
	layout := &panel_layout
	if clay.UI(clay.ID("Content"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
		if clay.UI(clay.ID("Main"))({layout = {sizing = {clay.SizingGrow(), clay.SizingPercent(layout.main_height)}}}) {
			for index in 0 ..< layout.column_count {
				column := layout.columns[index]
				is_last := index == layout.column_count - 1
				width := clay.SizingGrow() if is_last else clay.SizingPercent(column.width)
				if clay.UI(column_id(index))({layout = {sizing = {width, clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
					if column.has_bottom {
						slot(session, {column = index}, {clay.SizingGrow(), clay.SizingPercent(column.split)})
						divider({.Column_Rows, index})
						slot(session, {column = index, lower = true}, {clay.SizingGrow(), clay.SizingGrow()})
					} else {
						slot(session, {column = index}, {clay.SizingGrow(), clay.SizingGrow()})
					}
				}
				if !is_last {
					divider({.Column_Edge, index})
				}
			}
		}
		divider({.Main_Bottom, 0})
		if clay.UI(clay.ID("BottomRow"))({layout = {sizing = {clay.SizingGrow(), clay.SizingGrow()}}}) {
			if layout.bottom_count == 2 {
				slot(session, {column = -1}, {clay.SizingPercent(layout.bottom_split), clay.SizingGrow()})
				divider({.Bottom_Edge, 0})
				slot(session, {column = -1, lower = true}, {clay.SizingGrow(), clay.SizingGrow()})
			} else {
				slot(session, {column = -1}, {clay.SizingGrow(), clay.SizingGrow()})
			}
		}
	}
}

// One slot, showing whichever panel is assigned to it. While a panel is
// dragged, the slot under the mouse is outlined as the drop target.
@(private)
slot :: proc(session: ^state.Session, slot: Slot, sizing: clay.Sizing) {
	colors := ui.palette()
	outline: clay.BorderElementConfig
	if dragged, dragging := panel_layout.dragging_panel.?; dragging && clay.PointerOver(slot_id(slot)) {
		if source, shown := slot_of(dragged).?; shown && source != slot {
			outline = {colors.accent, clay.BorderOutside(4)}
		}
	}
	if clay.UI(slot_id(slot))({layout = {sizing = sizing}, border = outline, cornerRadius = clay.CornerRadiusAll(ui.CORNER_RADIUS)}) {
		draw_panel(session, panel_in(slot))
	}
}

// The gap between two slots: a bar appears in it on hover or while
// dragging.
@(private)
divider :: proc(divider: Divider) {
	colors := ui.palette()
	vertical := divider.kind == .Column_Edge || divider.kind == .Bottom_Edge
	sizing := clay.Sizing{clay.SizingGrow(), clay.SizingFixed(DIVIDER_THICKNESS)}
	bar := clay.Sizing{clay.SizingGrow(), clay.SizingFixed(4)}
	if vertical {
		sizing = clay.Sizing{clay.SizingFixed(DIVIDER_THICKNESS), clay.SizingGrow()}
		bar = clay.Sizing{clay.SizingFixed(4), clay.SizingGrow()}
	}
	active := panel_layout.dragging_divider == divider || clay.PointerOver(divider_id(divider))
	if clay.UI(divider_id(divider))({layout = {sizing = sizing, childAlignment = {x = .Center, y = .Center}}}) {
		if active {
			if clay.UI()({layout = {sizing = bar}, backgroundColor = colors.accent, cornerRadius = clay.CornerRadiusAll(2)}) {}
		}
	}
}

// The handle a panel is dragged by: "::" at the start of its header.
@(private)
panel_grip :: proc(panel: Panel) {
	colors := ui.palette()
	color := colors.title if clay.PointerOver(grip_id(panel)) else colors.text_dim
	if clay.UI(grip_id(panel))({layout = {padding = {2, 8, 2, 2}, childAlignment = {y = .Center}}}) {
		clay.TextDynamic("::", ui.text_config(.Title, color))
	}
}

// Follows the mouse while a panel is dragged.
@(private)
drag_label :: proc(panel: Panel) {
	colors := ui.palette()
	mouse := rl.GetMousePosition()
	if clay.UI(clay.ID("DragLabel"))({
		layout = {padding = {10, 10, 6, 6}},
		floating = {attachTo = .Root, offset = {mouse.x + 16, mouse.y + 16}, zIndex = 100},
		backgroundColor = colors.panel,
		border = {colors.accent, clay.BorderOutside(ui.BORDER_WIDTH)},
		cornerRadius = clay.CornerRadiusAll(ui.CORNER_RADIUS),
	}) {
		clay.TextDynamic(fmt.tprintf("Move %s: drop it on another panel to swap", panel_names[panel]), ui.text_config(.Text, colors.text))
	}
}

@(private)
toolbar :: proc(session: ^state.Session) {
	colors := ui.palette()
	if clay.UI(clay.ID("Toolbar"))({
		layout = {
			sizing = {width = clay.SizingGrow()},
			childGap = 8,
			childAlignment = {y = .Center},
		},
	}) {
		ui.button(BUTTON_ID_RESET, "Reset")
		ui.button(BUTTON_ID_PREV, "< Prev")
		ui.button(BUTTON_ID_NEXT, "Next >")

		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(16)}}}) {}
		cpu := &session.machine.cpu
		info := fmt.tprintf("%s    step %d    pc 0x%x", session.program_name, cpu.instret, cpu.pc)
		clay.TextDynamic(info, ui.text_config(.Code, colors.text_dim))
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(24)}}}) {}
		ended := session.stopped != nil || session.exited != nil
		clay.TextDynamic(explain_status(session), ui.text_config(.Text, colors.stopped if ended else colors.text))

		// Settings, pushed to the right edge.
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {}
		ui.button(BUTTON_ID_PROGRAMS, "Programs (~ / P)")
		ui.button(BUTTON_ID_DOCS, "Docs (D)")
		ui.button(BUTTON_ID_RESET_LAYOUT, "Reset layout")
		ui.button(BUTTON_ID_THEME, ui.settings_theme_label())
	}
}

// Look shared by the panels. `clip` hides content that overflows the
// panel. A panel that contains its own scrolling area must not clip:
// in Clay a clipping element lets its children grow past it (so they can
// scroll), which would stop the inner area from being sized to the panel.
@(private)
panel_style :: proc(sizing: clay.Sizing, clip := true) -> clay.ElementDeclaration {
	colors := ui.palette()
	return clay.ElementDeclaration {
		layout = {
			sizing = sizing,
			layoutDirection = .TopToBottom,
			padding = clay.PaddingAll(ui.PANEL_PADDING),
			childGap = 2,
		},
		backgroundColor = colors.panel,
		cornerRadius = clay.CornerRadiusAll(ui.CORNER_RADIUS),
		border = {colors.border, clay.BorderOutside(ui.BORDER_WIDTH)},
		clip = {horizontal = clip, vertical = clip},
	}
}
