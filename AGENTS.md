# Agent Notes

## Project Context

- This is a macOS Markdown viewer/editor.
- Add notes in the code for better navigation and understanding WHY it was made like this.
- Every time change this document if needed, depands on what was changed.
- Keep up to date the "Change Log" file

## Table Rendering Lessons

> [!NOTE] 💡
>  Add lessons only for the matter to avoide those issues next time when you create some code.

- Do not measure table width from the table itself when the table's own frame depends on that measurement. This can create a feedback loop where SwiftUI collapses the table to a near-zero width.
- For preview-width tables, measure the width from an outer container that has `.frame(maxWidth: .infinity, alignment: .leading)`, then pass that measured width into the table grid.
- In a vertical SwiftUI `ScrollView`, content may keep its intrinsic width instead of filling the visible viewport. For full-width preview tables, read the preview pane width from a parent `GeometryReader` and pass the content width into `MarkdownPreview` / `MarkdownTableView`.
- Keep a reasonable fallback width before the first geometry measurement arrives. A `1 px` fallback makes the table appear as a thin vertical line.
- Avoid fixed maximum cell widths for Markdown preview tables when the requirement is full content visibility.
- Do not draw table dividers as per-cell overlays when cells can wrap to different heights. Short cells will draw short borders and break the grid. Draw horizontal dividers at the row level and vertical dividers across the full row height.
- Prefer wrapping table cell text vertically with:
  - `.lineLimit(nil)`
  - `.fixedSize(horizontal: false, vertical: true)`
  - an explicit column width derived from the available preview width
- Trade-off: many columns will become narrow and rows will become tall. This is expected when prioritizing full cell content over horizontal scrolling.

## Demo File Expectations

- `markdown_demo.md` should include table examples that stress the layout:
  - normal short tables
  - aligned tables
  - formatted inline Markdown inside cells
  - long wrapping content
  - dense multi-column tables
- When table rendering changes, update the demo file so the behavior can be tested visually in the bundled demo.

## Build And Test Notes

- Versioning: current line is `2.1.x`. For each new build/release, bump only the last digit (2.1.19 → 2.1.20 → ...). The version lives in the `VERSION` file; `scripts/package_app.sh` injects it into both `CFBundleShortVersionString` and `CFBundleVersion`. Development release notes are consolidated under `2.1.19` in CHANGELOG.md.

- `swift build` may fail inside the sandbox because Swift wants to write compiler caches under the user's home directory. If the error mentions `~/.cache/clang`, rerun the same build command with escalation instead of treating it as a code failure.

- Always run at least:

  - `swift build`
  - `swift build -c release` before creating a test `.app`

- Verify test app bundles with:

  - `codesign --verify --deep --strict path/to/App.app`

- When creating a test app, prefer a separate bundle name such as `MD_View-Edit_macOS-table-improvements-fixed.app` instead of overwriting the release `MD_View-Edit_macOS-v1.0.0.app`.

- If copying into an already-created `.app` fails with `Operation not permitted`, the app may be running or macOS may be holding the bundle. Create a new test bundle instead of fighting the existing one.

## Visual Verification

- Compile success is not enough for SwiftUI layout changes.
- For layout work, inspect a real app window or user-provided screenshot before considering the change complete.
- If a screenshot shows a table as a single vertical line, suspect width measurement collapse before changing table content or parser logic.

## Toggle Serialization

- Never serialize a toggle with `node.textContent`: it drops formatting, block boundaries, and non-text nodes.
- Serialize each child using the Markdown serializer and close each block, including block images.
- Separate adjacent list nodes with an HTML comment so Markdown parsing does not merge ordinary lists with task lists.
- Escape summary text as HTML. Check nested toggles and code containing literal HTML tags.
- Run `swift scripts/toggle_roundtrip.swift` for Preview/Code and reparse regression coverage.
- Toggle nodes must be defining containers: ProseMirror otherwise replaces an empty toggle when a pasted block slice fills its body. Test actual `serializeForClipboard` / `pasteHTML` with nested formatting; `insertContent` alone does not test this behavior.
- Toggle title editing must respect `editor.isEditable`, including read-only disk previews.

## External File Changes

- File events are hints. Check content on focus/wake and immediately inside the coordinated write; never rely only on timestamps.
- Watch the parent directory because atomic saves replace the file inode. Discard reads whose document or saved baseline changed while reading.
- Preserve local edits when the file is missing or unreadable. Save As must use a different path; never silently recreate a removed file.
- Comparison is two independent buffers, not a merge. Apply adopts the displayed external version without writing to disk, and must support one Undo.
- Highlight with ProseMirror decorations, not document marks or DOM text edits. View-mode transitions and comparison metadata must not mark the file dirty.
- Use bounded-memory comparison in a worker; never allocate a full line-by-line LCS matrix for this feature.
- Check `scripts/external_changes_smoke.swift` and `scripts/comparison_diff_tests.js` when changing this flow.


## Native Save Commands

- File → Save As… (Command-Shift-S) and the comparison banner must call the same `DocumentStore.saveAs()` flow. Keep editor flushing and disk safeguards in that shared path.


## Markdown Source Fidelity

- Markdown source is authoritative. Never regenerate the whole file merely because one rich block changed.
- Retain original source ranges and gaps for unchanged blocks, including reference definitions, unsupported HTML and line endings. Use immutable node identities to distinguish duplicate blocks.
- Validate changed fragments by parsing them back before saving. A failed conversion must preserve the editor buffer and report an error, not silently drop syntax.
- Code/Preview changes must pass through the same source-preserving serializer as Save. Preserve BOM and frontmatter as source metadata.
- The left comparison pane shows current local text only; deleted baseline widgets belong in the right comparison. Keep mine dismisses comparison but never disables the write guard.
- Run `swift scripts/source_roundtrip.swift` and native bridge checks when changing parsing or serialization.


## Independent Disk Preview

- A readable disk version must not depend on converting the dirty local editor. Handle disk reads and editor snapshots in separate error paths.
- If local conversion or highlighting fails, keep showing disk content and preserve the local model. Never replace valid disk data with a generic editor error.
- Full Apply replaces the model and cancels old debounce callbacks. It must not serialize the discarded model, and Undo must retain that model.
- Test the user flow on full documents: unsaved Preview edits, an external save to the same path, and two independent panes. Also test editor failures before the native dirty flag arrives.
- Render disk changes in a separate read-only rich editor, independent of the left Code/Preview mode. Reject document-changing transactions, keep frontmatter visible and expand toggles for review. Apply must use the original disk text, never the rendered model or deletion decorations.

## Confirmed Overwrite

- Keep mine dismisses comparison without granting overwrite consent. The right Preview is always the first review step. Save must ask Yes/No only after Keep mine for the exact current disk version; a new/unreviewed version must show comparison instead. No must preserve the local buffer and dismissed pane.
- Yes authorizes only the exact disk version checked before the dialog. Retry the coordinated write against that version; never use an unconditional write. Keep missing/unreadable file protection.

## Rich Input and Save Failures

- Command-S must send the native Save command before conversion. Native Save owns snapshot/error handling; pre-serializing in a key handler silently swallows the shortcut on failure.
- Use the same `preserveWhitespace: true` parsing for rich initialization, refresh, validation and comparison. HTML fallback must be compact, without injected formatting whitespace. Empty paragraphs need explicit HTML because Markdown blank lines cannot encode them.
- Test typed spaces with `tr.insertText`, not `insertContent`: the latter parses HTML and may trim away the very input under test. Run `scripts/editor_input_regression.swift` across demo text blocks.
- Background conversion failure must keep the dirty model editable. A failed locked snapshot must restore its previous inert state. Error messages must not recommend Code if the failed conversion also prevents opening Code.

- Generated whitespace-sensitive HTML uses `data-md-whitespace` parse rules and newline entities. Do not run Markdown HTML pretty-print cleanup over those text nodes.
- Callout parsing must exclude the decorative emoji and use only `.callout-content` when present. Compare CSS colors semantically (hex versus rgb/rgba); missing highlight color must parse as null, not an empty string.
- Board marker/table/marker regions map to one source range, just as a details region maps to one toggle. Board source attributes exclude whitespace outside their closing marker.
