# Edit MD for Mac

A minimal native macOS Markdown viewer and editor for offline local files. No Electron, no server, no network requirement.

Current version is stored in [`VERSION`](VERSION).


![Screenshot](Edit-MD-for-Mac-3.png)
![Screenshot-dark](Edit-MD-for-Mac-2.png)
![Screenshot-info](Edit-MD-for-Mac-1.png)

## Features

- Open `.md`, `.markdown`, `.mdown`, `.mkd`, and `.txt` files
- Edit and save Markdown
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

The editor bundle remains a licensed vendor artifact. Our maintained adapter is `Resources/Webview/native-host.js`. The bundle has two integration hooks: immediate dirty notification and document context/save-indicator access. Preserve these hooks when replacing the vendor bundle.

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT License. See [`LICENSE`](LICENSE).
