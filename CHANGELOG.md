# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning: `MAJOR.MINOR.PATCH`.

## [Unreleased]

### Changed

- Renamed the app to Edit MD for Mac. The app bundle, executable, Swift package, release artifacts, window titles, documentation, screenshots, and GitHub repository now use the new name.

## [2.0.9] - 2026-08-09

### Added

- More block actions: Heading 4–6, callouts, toggles, tables, Mermaid diagrams, images, Kanban/table boards, and whiteboards.
- Inline text highlighting and text-color controls in the editor.

### Changed

- Simplified the preview appearance picker to Light, Claude, Dark, and macOS system appearance.
- Replaced the app icon with the selected minimal text-lines and overflow-menu mark.

## [2.0.7] - 2026-08-09

### Fixed

- Preview settings now persist when a document is closed and reopened.

## [2.0.6] - 2026-08-05

### Fixed

- The window title now shows the current file name ("<file> — MD Design"). SwiftUI's WindowGroup owns NSWindow.title and kept resetting the imperatively set title to the default; the title is now driven declaratively via .navigationTitle and updates on open/save-as. The edited-state dot and the proxy icon are unchanged.

## [2.0.5] - 2026-08-05

### Changed

- Renamed the app to MD-design-macOS (window titles now show "<file> — MD Design"; bundle, executable, and dist artifacts use the new name).

## [2.0.4] - 2026-08-05

### Added

- Resizable table columns in preview: drag any column border to resize (thin blue handle, 60px minimum). Widths persist in the Markdown file itself as proportional dash counts in the table's separator row (`| --- | ------------ |`, ~1 dash ≈ 20px) — still 100% valid Markdown for any other renderer — and are restored on reopen. Files with uniform `---` separators never gain width attributes, and hand-edited dash counts round-trip byte-identical when unedited.

## [2.0.3] - 2026-08-05

### Added

- "Turn into" in the block-handle menu now opens the full block picker (same sections, filter box, and drill-down as the "+" menu); clicking a block converts the current block instead of inserting a new one. Added conversion targets: Toggle, Divider, Board: Kanban, and Whiteboard (text blocks seed the first kanban card / mermaid node label so content isn't dropped).
- Toggle titles are now inline-editable in preview: click the title text to edit, Enter/blur commits, Escape cancels; the disclosure arrow still expands/collapses independently.
- Tables now show Notion-style "+" append bands: hovering just past the bottom edge reveals a full-width band that appends a row, and hovering just past the right edge reveals a full-height band that appends a column.

## [2.0.2] - 2026-08-05

### Changed

- Removed the in-window header panel. Open (⌘O) and Save (⌘S) remain in the File menu; font-size commands (⌘+/⌘−) stay in the menu; preview display settings live in the preview's own toolbar/settings panel.
- Appearance (theme) switching moved to the menu bar: View → Appearance → System / Light / Dark (checkmark on the active mode; applies to all windows).
- Markdown Guide moved to the Help menu (⌘/) and opens as a sheet in the focused window.
- Window title now shows "<file name> — MD View-Edit", with the standard edited-state dot and a proxy icon for saved files.
- The status bar now shows the full file path (middle-truncated) plus size, character count, encoding, and an Edited marker.
- Removed the webview toolbar logo and the "✨ Using AI" menu (bubble-menu ⋯ entry, AI transform panel, and the block-picker flyout AI section). AI features were inert in this host.

## [2.0.1] - 2026-08-05

### Changed

- Replaced the side-by-side editor/preview split with a single full-width surface: Code mode (native source editor) or Preview mode, toggled from the header.
- Preview mode is now a fully editable WYSIWYG surface powered by the bundled md-editor-plus web editor (TipTap/ProseMirror): type directly in the rendered document, edit tables inline, click task checkboxes, use slash commands, bubble-menu formatting, callouts, code blocks with syntax highlighting, and mermaid diagrams.
- Preview display settings (theme incl. sepia/claude, font, text size, page width, full width, dark code/source options, word wrap, smart typography, outline) now come from the md-editor-plus settings panel inside the preview and persist across launches.
- Save lifecycle (saving/saved indicator), ⌘S, reload-from-disk, copy content/path, reveal in Finder, duplicate, HTML export, and PDF export are wired through the native host bridge.

## [1.0.1] - 2026-06-13

### Changed

- Improved Markdown preview table layout so cells wrap full content instead of clipping.
- Tables now fill the preview width while row heights grow with wrapped content.
- Table grid lines now span full row heights for wrapped cells.
- Expanded the bundled demo file with wrapping and dense table test cases.

## [1.0.0] - 2026-04-25

### Added

- Initial open source release of MD_View-Edit_macOS.
- Native macOS Markdown editor and previewer.
- Local file opening, editing, saving, drag and drop, and bundled demo file.
- Light, dark, and system appearance modes.
- Release packaging scripts for `.app`, `.zip`, and `.dmg` artifacts.
