# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning: `MAJOR.MINOR.PATCH`.

## [1.1.0] - 2026-08-05

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
