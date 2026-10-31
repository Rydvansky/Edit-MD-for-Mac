# Edit MD for Mac

A minimal native macOS Markdown viewer and editor for offline local files. No Electron, no server, no network requirement.

Current version is stored in [`VERSION`](VERSION).


![Screenshot](Edit-MD-for-Mac-3.png)
![Screenshot-dark](Edit-MD-for-Mac-2.png)
![Screenshot-info](Edit-MD-for-Mac-1.png)

## Features

- Open `.md`, `.markdown`, `.mdown`, `.mkd`, and `.txt` files
- Edit and save Markdown
- Save to a new file with File → Save As… (⌘⇧S)
- Drag and drop local files into the window
- Editable Markdown preview and source modes in one embedded web editor
- System, light, and dark appearance modes
- Font size controls
- Current file name and path display
- Async file loading
- Clear user-facing error messages
- Built-in Markdown formatting guide from the keyboard/info button

## Download And Install

For end users, download the latest `Edit MD for Mac-vX.Y.Z.dmg` or `Edit MD for Mac-vX.Y.Z.zip` from GitHub Releases.

For normal installation, open the `.dmg` and drag the app into `Applications`.

⚠️ `I'm not apple-sertified developer, so your macOS will block the installation until you give the permission in System Settings - Privacy & Security section` or `you can download the source of the app (from github) and ask your AI to pack the app for you`.

## Requirements For Building

- macOS 13 or newer
- Swift toolchain from Xcode or Apple Command Line Tools

End users do not need Xcode to run the packaged `.app`. They only need the final app bundle.

## Versioning

The project version is stored in [`VERSION`](VERSION).

Release files include the version in their names:

```text
Edit MD for Mac-vX.Y.Z.zip
Edit MD for Mac-vX.Y.Z.dmg
```

The macOS app bundle version is written to `CFBundleShortVersionString` during packaging.

## Build Commands

```bash
swift build -c release
```

Run the executable directly:

```bash
.build/release/EditMDForMac
```

Open a file from Terminal:

```bash
.build/release/EditMDForMac /path/to/notes.md
```

## Package As `.app`

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
```

The app bundle will be created here:

```text
dist/Edit MD for Mac-vX.Y.Z.app
```

The script also creates a Finder-friendly archive:

```text
dist/Edit MD for Mac-vX.Y.Z.zip
```

It also creates a drag-to-install disk image:

```text
dist/Edit MD for Mac-vX.Y.Z.dmg
```

For normal installation, open the `.dmg` and drag the app into `Applications`.
For versioned releases, the app bundle name includes the version, for example `Edit MD for Mac-v2.0.7.app`.

## Unsigned Local Build

Use this for personal/offline use on your own Mac:

```bash
./scripts/package_app.sh
open "dist/Edit MD for Mac-vX.Y.Z.app"
```

This creates a local ad-hoc signed app bundle, which keeps macOS resource validation happy but is still not Developer ID notarized.

If macOS warns because the app is not from an identified developer, allow it manually in **System Settings > Privacy & Security** or right-click the app, choose `Open`, then confirm. This is expected for local builds and is not an app bug.

## Signed And Notarized Build

Use this when distributing the app to non-technical users. It requires an Apple Developer account and a Developer ID Application certificate.

```bash
chmod +x scripts/sign_and_notarize.sh

export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export TEAM_ID="TEAMID"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./scripts/sign_and_notarize.sh
```

The script:

1. Builds and packages `dist/Edit MD for Mac-vX.Y.Z.app`
2. Signs the app with hardened runtime
3. Zips it for notarization
4. Submits it to Apple notarization
5. Staples the notarization ticket to the app
6. Verifies the final app with Gatekeeper

## Notes

The macOS shell uses SwiftUI and AppKit. Both source and rich editing run in the bundled WebKit editor, which includes modified MD Editor Plus code. Attribution and license notices are included in `THIRD_PARTY_NOTICES.md`.

The native `DocumentSession` owns document identity, the current text, and the saved baseline. `DocumentStore` owns file operations. `NativeDocumentActions` handles system actions. `WebEditorBridge` transports versioned messages through `native-host.js`; the vendor compatibility layer is confined to that adapter.

Each editor page has a channel identity and each open document has a document identity. Editor transactions advance a revision immediately, before debounced text arrives. Save/close/switch/quit request an acknowledged snapshot. Native writes run in order, and a completed write only updates its captured saved baseline. An unedited document retains its original Markdown bytes. A new document loads a fresh editor page so delayed messages and undo history cannot cross documents.

The custom native document parser, renderer, source editor, and old heading pane have been removed. The formatting guide uses SwiftUI's built-in Markdown support.

Run the native session checks and the real WebKit checks:

```bash
swiftc Sources/EditMDForMac/DocumentSession.swift scripts/document_session_tests.swift -o /tmp/edit-md-session-checks
/tmp/edit-md-session-checks
swift scripts/webview_smoke.swift
# Build within the project so the executable finds Resources/Webview:
mkdir -p .build-architecture
swiftc -DARCHITECTURE_SMOKE Sources/EditMDForMac/*.swift scripts/native_bridge_smoke.swift -o .build-architecture/native-bridge-smoke
.build-architecture/native-bridge-smoke
```

Markdown source ranges are preserved across rich edits: changing an H1 does not rewrite unrelated quotes, tables, HTML or references. Only changed fragments are converted and validated against the editor model. Code/Preview uses the same source-preserving path. Run `swift scripts/source_roundtrip.swift` to check both demo fixtures and all editable block types.

The editor bundle remains a licensed vendor artifact. Our maintained adapter is `Resources/Webview/native-host.js`. The bundle has narrow integration hooks for editor transactions, mode changes, source preservation and document context/save-indicator access. Preserve these hooks when replacing the vendor bundle.

## External File Changes

The app watches the open file's parent directory and checks again on focus/wake and before writing. Clean documents refresh automatically. With local edits, the editor stays on the left and a read-only Markdown comparison appears on the right. Yellow indicates additions; red struck-out text in the right pane indicates deletions. The left editor always contains only the current local text. The two panes compare independently against the last synchronized disk version.

“Save my version as…” writes the local buffer to a different file and makes that file active. “Apply changes?” replaces the entire local document with the displayed disk version, without writing to disk; one Undo restores the prior local version. “No, keep mine” dismisses the comparison without changing either file; the pre-save guard still applies. You can also copy selected fragments manually. Ordinary Save cannot silently overwrite a changed, deleted, or unreadable file.

Comparison uses a Web Worker and bounded-memory patience anchors. Local highlights refresh after a typing pause. Decorative highlights never enter the Markdown or its undo history. Code/Preview changes are service operations, not user edits.

The right pane shows an independent read-only Preview with formatting, tables and expanded toggles, even while the local editor is in Code mode. Frontmatter is visible as a code block. Its disk read is independent of local Save conversion. If the local editor cannot provide a snapshot or comparison highlighting fails, the disk version remains available. A Preview rendering failure falls back to readable disk source. Apply always adopts the exact disk text, without serializing the Preview. Arbitrary programs that ignore macOS file coordination can still race a write; file notifications alone are not a guarantee of exclusive access.

Additional checks:

```bash
node scripts/comparison_diff_tests.js
swiftc -DARCHITECTURE_SMOKE Sources/EditMDForMac/*.swift scripts/external_changes_smoke.swift -o .build-architecture/external-changes-smoke
.build-architecture/external-changes-smoke
```

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT License. See [`LICENSE`](LICENSE).
