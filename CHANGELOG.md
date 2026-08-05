# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning: `MAJOR.MINOR.PATCH`.

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
