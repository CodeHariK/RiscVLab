package rvdbg

// User-adjustable look, changed from the Theme button on the right of
// the toolbar. Lives for the session only (not saved to disk yet).

Theme_Choice :: enum {
	Light, // the Clay website palette
	Dark,
}

Settings :: struct {
	theme: Theme_Choice,
}

settings := Settings {
	theme = .Light,
}

settings_next_theme :: proc() {
	settings.theme = .Dark if settings.theme == .Light else .Light
}

settings_theme_label :: proc() -> string {
	return "Theme: Light" if settings.theme == .Light else "Theme: Dark"
}
