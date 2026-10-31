# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning: `MAJOR.MINOR.PATCH`.

## [Unreleased]

### Changed

- Renamed the app to Edit MD for Mac. The app bundle, executable, Swift package, release artifacts, window titles, documentation, screenshots, and GitHub repository now use the new name.
- Match regular Markdown table text to the surrounding editor text size, including the selected text-size setting.
- Align all Markdown table cell text at the top left, including cells with explicit alignment markers.

## [2.0.13] - 2026-10-31

### Added

- Native File → Save As… with Command-Shift-S. It uses the same latest-editor snapshot and safe write flow as the comparison banner, then makes the new file active.

## [2.0.12] - 2026-10-31

### Added

- Watch external changes using parent-directory events, metadata polling, and focus/wake recovery checks.
- Automatically refresh clean documents. Dirty documents show two independent panes with local and external changes, yellow additions, red deleted-text overlays, and persistent action banners.
- Add “Save my version as…” and “Apply changes?”; Apply replaces the complete local document with the displayed disk version, without writing to disk, and supports one Undo.
- Compare file bytes inside coordinated writes so a missed file event cannot silently overwrite a newer disk version. Deleted or unreadable files preserve the local buffer.
- Compute comparison using bounded-memory patience anchors in a Web Worker; local highlights refresh after a typing pause.

### Fixed

- Keep Code/Preview switches and decorations out of user edit tracking; retain unchanged raw Markdown until a real edit.
- Preserve edits in meaningful container attributes, including toggle summaries.

## [2.0.11] - 2026-10-31

### Fixed

- Toggle serialization now preserves child blocks and inline formatting instead of flattening `textContent` and losing images/dividers.
- Preserve block boundaries and separate adjacent lists inside toggles so Preview/Code transitions and reopening retain their structure.
- Escape summary text when writing HTML to preserve literal angle brackets and ampersands.
- Add a WebKit regression check covering headings, marks, links, nested lists, tasks, quotes, code, tables, images, dividers, and nested toggles across repeated mode switches and reparses.

## [2.0.10] - 2026-10-31

### Changed

- Use one web editor for both source and preview modes; remove the hidden native editor, unused native preview, and legacy navigation pane.
- Separate native document state, system actions, web settings, and the editor transport.
- Add a versioned document protocol with document/channel identities, increasing revisions, snapshots, and acknowledgments.
- Save, close, switch, and quit now await the same editor snapshot. Writes run in order and older save completions preserve newer unsaved edits.
- Preserve the original Markdown bytes when opening and closing an unedited document.
- Render guide examples with SwiftUI's built-in Markdown support, without the document parser.

### Verification

- Add document-session checks and expand the WebKit smoke checks for stale identities, pending edits, save races, and both editor modes.

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
