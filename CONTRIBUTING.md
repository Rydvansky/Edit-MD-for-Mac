# Contributing

Thanks for considering a contribution to Edit MD for Mac.

## Development

Requirements:

- macOS 13 or newer
- Swift 5.9 or newer from Xcode or Apple Command Line Tools

Build:

```bash
swift build
```

Run:

```bash
swift run EditMDForMac
```

Package a release build:

```bash
./scripts/package_app.sh
```

## Pull Requests

- Keep changes focused and easy to review.
- Include a short explanation of the user-facing behavior.
- Update `CHANGELOG.md` for user-visible changes.
- Do not commit `.build/`, `dist/`, notarization credentials, or generated local machine files.

## Versioning

The project version lives in `VERSION`.

For a release:

1. Update `VERSION`.
2. Update `CHANGELOG.md`.
3. Run `./scripts/package_app.sh`.
4. Create a GitHub Release named `vX.Y.Z`.
