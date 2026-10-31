# Changelog

## [2.1.19] - 2026-10-31

Consolidated release notes for Edit MD for Mac.

### Added

- Local Markdown opening, editing, drag and drop, a bundled demo, duplicate, copy content/path, reveal in Finder, and HTML/PDF export.
- Native File → Save As… with Command-Shift-S, shared with “Save my version as…” in the comparison banner.
- Automatic detection of external file changes through directory events, polling, and focus/wake checks. Unedited documents refresh automatically.
- Independent read-only Preview for external changes when local edits are pending. Yellow shows additions; red struck-out text shows removals. Tables, formatting, frontmatter and expanded toggles remain visible even when the local editor is in Code mode.
- “Apply changes?” replaces the local document with the displayed disk version and supports one Undo. “No, keep mine” dismisses that version; subsequent Save asks for Yes/No overwrite confirmation. A newer external version opens comparison again.
- Rich editing with headings, inline formatting, text colors, highlighting, lists, tasks, quotes, callouts, toggles, tables, images, code, Mermaid diagrams, Kanban/table boards and whiteboards.
- Editable toggle titles, a full block conversion picker, table row/column append controls, and resizable columns with widths stored in Markdown delimiter dash counts.
- Persistent preview settings, appearance options, fonts, text sizes, page widths, wrapping, smart typography and outline. System appearance controls and the Markdown guide are available through the macOS menus.
- Local `.app`, `.zip` and `.dmg` packaging, plus signing and notarization scripts.

### Changed

- Renamed the app to Edit MD for Mac, including its bundle, executable, package, window titles, documentation and release artifacts. Updated the app icon.
- Use one web editor for Code and Preview in a native macOS shell. Separate document state, disk operations, system actions, settings and the versioned editor transport; remove the hidden native editor, obsolete renderer and legacy navigation.
- Keep document/channel identities, increasing revisions, acknowledged snapshots and ordered writes shared across Save, close, switch and quit. Window titles follow the active file and the status bar shows its path and document details.
- Simplify the in-window interface and remove unused logo and AI controls. Retain the MD Editor Plus attribution and license notices.
- Match table text to the surrounding editor size, align cells at the top left, wrap long content, fill the preview width and keep grid lines continuous. Expand the demo with dense and wrapping tables.
- Consolidate development release notes under version 2.1.19 and keep bundle version metadata aligned with VERSION during packaging.
- Remove internal architecture notes and regression commands from README; keep engineering safeguards in AGENTS.md.

### Fixed

- Preserve original Markdown bytes for untouched blocks and unedited documents. Rich changes do not rewrite unrelated quotes, tables, references, HTML, spacing, line endings, byte-order marks or frontmatter.
- Preserve toggle formatting, nested blocks, images, dividers and adjacent list boundaries through insertion, Save, Code/Preview and reopening. Pasting formatted blocks into an empty toggle keeps its container.
- Preserve typed spaces, empty paragraphs, callout formatting, highlight attributes and literal newlines. Compare equivalent CSS colors consistently and map complete board regions to their source. Use validated compact HTML within changed fragments when Markdown cannot express the edited structure.
- Route Command-S through native Save before conversion so errors are reported. Background conversion errors keep the editor usable; failed snapshots restore the prior input-lock state.
- Keep local and disk buffers independent. A local conversion or highlighting failure cannot hide readable disk data; Preview rendering failure falls back to readable source. Apply uses the exact disk text and preserves the prior local model for Undo.
- Check disk bytes inside coordinated writes to prevent overwriting unreviewed changes. Overwrite confirmation applies only after Keep mine for the exact reviewed version; another write during confirmation remains protected. Missing and unreadable files preserve local edits.
- Keep mode changes, toggle expansion and comparison decorations out of dirty tracking. Save after Apply works normally; declined overwrite preserves local edits and the dismissed pane.
- Preserve newer edits when an older save completes, reject stale cross-document messages, and keep canceled close/switch operations editable.

### Verification

- Add native session, bridge and disk checks for pending edits, concurrent saves, stale messages, close/cancel, external changes, overwrite decisions, Apply/Undo and recovery from conversion failures.
- Check both full demo files for exact H1-only edits, unchanged surrounding source, repeated Code/Preview cycles and reopening.
- Run 4,862 input and formatting checks across demo blocks, plus targeted toggle copy/paste, nested formatting, table widths, images, Mermaid, board edits and bounded-memory comparison checks.
