# MD-design-macOS

A minimal native macOS Markdown viewer and editor for offline local files. No Electron, no server, no network requirement.

Formerly known as MD_View-Edit_macOS. Current version is stored in [`VERSION`](VERSION).


![Screenshot](MD-design-macOS-3.png)
![Screenshot-dark](MD-design-macOS-2.png)
![Screenshot-info](MD-design-macOS-1.png)

## Features

- Open `.md`, `.markdown`, `.mdown`, `.mkd`, and `.txt` files
- Edit and save Markdown
- Drag and drop local files into the window
- Native Markdown preview
- System, light, and dark appearance modes
- Font size controls
- Current file name and path display
- Async file loading and capped preview rendering for large files
- Clear user-facing error messages
- Built-in Markdown formatting guide from the keyboard/info button

## Download And Install

For end users, download the latest `MD-design-macOS-vX.Y.Z.dmg` or `MD-design-macOS-vX.Y.Z.zip` from GitHub Releases.

For normal installation, open the `.dmg` and drag the app into `Applications`.

⚠️: I do not currently have an Apple Developer license. macOS may warn that the app is from an unidentified developer, and you may need to allow it manually in **System Settings > Privacy & Security** or right-click the app and choose **Open**. This is expected for unsigned open source builds.

## Requirements For Building

- macOS 13 or newer
- Swift toolchain from Xcode or Apple Command Line Tools

End users do not need Xcode to run the packaged `.app`. They only need the final app bundle.

## Versioning

The project version is stored in [`VERSION`](VERSION).

Release files include the version in their names:

```text
MD-design-macOS-vX.Y.Z.zip
MD-design-macOS-vX.Y.Z.dmg
```

The macOS app bundle version is written to `CFBundleShortVersionString` during packaging.

## Build Commands

```bash
swift build -c release
```

Run the executable directly:

```bash
.build/release/MDDesignMacOS
```

Open a file from Terminal:

```bash
.build/release/MDDesignMacOS /path/to/notes.md
```

## Package As `.app`

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
```

The app bundle will be created here:

```text
dist/MD-design-macOS-vX.Y.Z.app
```

The script also creates a Finder-friendly archive:

```text
dist/MD-design-macOS-vX.Y.Z.zip
```

It also creates a drag-to-install disk image:

```text
dist/MD-design-macOS-vX.Y.Z.dmg
```

For normal installation, open the `.dmg` and drag the app into `Applications`.
For versioned releases, the app bundle name includes the version, for example `MD-design-macOS-v2.0.5.app`.

## Unsigned Local Build

Use this for personal/offline use on your own Mac:

```bash
./scripts/package_app.sh
open "dist/MD-design-macOS-vX.Y.Z.app"
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

1. Builds and packages `dist/MD-design-macOS-vX.Y.Z.app`
2. Signs the app with hardened runtime
3. Zips it for notarization
4. Submits it to Apple notarization
5. Staples the notarization ticket to the app
6. Verifies the final app with Gatekeeper

## Notes

This app intentionally uses Apple native frameworks only. The preview uses Apple Markdown parsing, while editing uses `NSTextView` for better behavior with large local text files.

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT License. See [`LICENSE`](LICENSE).
