# Clippy 📎

A tiny, native macOS clipboard history manager that lives in your menu bar. Copy things as you work; click any of them later to paste them back — including several in a row — without your target app ever losing focus.

Built with Swift, SwiftUI, and AppKit. No dependencies, no accounts, no network access.

## Features

- **Clipboard history** — the last 50 text snippets you copied, persisted across relaunches.
- **Click to paste** — clicking an entry pastes it straight into the app you were just using.
- **Multi-paste** — the panel stays open after a paste, so you can click several entries in sequence (great for filling forms).
- **Global hotkey** — press <kbd>⌥⌘V</kbd> anywhere to open or close the panel; press <kbd>Esc</kbd> to close it.
- **Smart rows** — entries are classified (URL, email, code, number, text) with a matching glyph; code renders in monospace.
- **De-duplication** — re-copying something already in your history moves it to the top instead of storing it twice.
- **Privacy-aware** — copies that password managers mark as concealed or transient (the [nspasteboard.org](http://nspasteboard.org) convention, used by 1Password and friends) are never recorded.
- **Launch at login** toggle, powered by `SMAppService`.

## How pasting works (and why the panel never takes focus)

Most of this app is ordinary. The interesting part is that the panel is an `NSPanel` that **can never become the key or main window**. Because opening it never steals keyboard focus, the app you were working in stays frontmost the whole time — so when you click an entry, Clippy only has to put the text on the pasteboard and synthesize a <kbd>⌘V</kbd>, which lands in your app, not Clippy's own UI.

Two consequences of that design:

- There is deliberately no search field — a never-key window can't host a text field.
- The panel doesn't close when you click elsewhere; that's what lets you paste several items in a row. Close it with <kbd>Esc</kbd>, <kbd>⌥⌘V</kbd>, or the menu bar icon.

The hotkeys use Carbon's `RegisterEventHotKey`, which needs no special permission and consumes the keystroke. Note that while Clippy is running, <kbd>⌥⌘V</kbd> shadows Finder's "Move Item Here" — change the combination in `AppDelegate.setupHotKey()` if that bothers you.

## Permissions

Clippy needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility) to synthesize the <kbd>⌘V</kbd> keystroke. It prompts the first time you click an entry. Without the permission, clicking an entry still copies it to the clipboard — you just have to press <kbd>⌘V</kbd> yourself.

## Privacy

- History is stored locally as JSON in `~/Library/Application Support/Clippy/history.json` and never leaves your machine.
- Copies flagged as concealed/transient by their source (passwords, OTPs) are skipped.
- Anything a source *doesn't* flag is stored in plain text — use "Clear all" (the trash icon) if you've copied something sensitive from an app that doesn't use the convention.

## Building

Requires Xcode 16+ and macOS 14 or later.

```sh
git clone <this repo>
open Clippy.xcodeproj   # then ⌘R
```

or from the command line:

```sh
xcodebuild -project Clippy.xcodeproj -scheme Clippy -configuration Release build
```

## Limitations

- Text only — images, files, and rich text aren't captured (yet).
- Entries over 100,000 characters are skipped rather than stored truncated.
- The hotkey isn't configurable from the UI yet.
