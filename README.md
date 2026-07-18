# Clippy 📎

A tiny, native macOS clipboard history manager that lives in your menu bar.

macOS remembers exactly one thing at a time. Copy a URL, then copy a sentence, and the URL is gone. Clippy fixes that: it quietly keeps your last 50 text snippets, and clicking any of them pastes it straight back into whatever app you were using — without that app ever losing focus, so you can paste several in a row.

Built with Swift, SwiftUI, and AppKit. No dependencies, no accounts, no network access, no analytics. MIT licensed.

## Who it's for

- **Anyone filling out forms** — copy name, email, address once, then click-click-click them into the fields.
- **Developers and writers** — juggle error messages, snippets, links, and IDs without round-tripping through a scratch file.
- **People who just lost a clipboard** — you copied something important, then copied something else. Never again.
- **The minimalist** — if full-featured managers feel like too much, Clippy is one panel, one hotkey, and nothing else. It's also a compact, readable example of a menu bar app if you want to learn how they're built.

## Features

- **Clipboard history** — your last 50 text snippets, persisted across restarts and reboots.
- **Click to paste** — clicking an entry pastes it directly into the app you were just using.
- **Multi-paste** — the panel deliberately stays open after a paste, so you can insert several entries in sequence.
- **Global hotkey** — <kbd>⌥⌘V</kbd> opens or closes the panel from anywhere; <kbd>Esc</kbd> closes it.
- **Smart rows** — entries are recognized as URLs, emails, code, numbers, or plain text, each with a matching glyph; code renders in monospace.
- **De-duplication** — re-copying something already in your history moves it to the top instead of storing it twice.
- **Password-aware** — copies that password managers mark as concealed or transient (the [nspasteboard.org](http://nspasteboard.org) convention, used by 1Password and friends) are never recorded.
- **Launch at login** — one checkbox, powered by Apple's `SMAppService`.

## Install

Clippy is currently built from source — it takes about a minute.

**Requirements:** macOS 14 (Sonoma) or later, and Xcode 16 or later.

```sh
git clone https://github.com/ajanwachuku/Clippy.git
cd Clippy
open Clippy.xcodeproj
```

Then press <kbd>⌘R</kbd> in Xcode. Clippy appears as a 📎 in your menu bar — there's no Dock icon and no window, that's all of it.

Prefer the command line?

```sh
xcodebuild -project Clippy.xcodeproj -scheme Clippy -configuration Release build
```

**First run:** the first time you click an entry to paste, macOS asks you to grant Clippy **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Clippy needs it to synthesize the <kbd>⌘V</kbd> keystroke on your behalf. Until you grant it, clicking an entry still copies it to your clipboard — you just press <kbd>⌘V</kbd> yourself.

To have Clippy start with your Mac, tick **Launch at Login** at the bottom of the panel.

## Using it

| Action | How |
|---|---|
| Open / close the panel | <kbd>⌥⌘V</kbd> from anywhere, or click the 📎 menu bar icon |
| Paste an entry | Click it |
| Paste several entries | Click them one after another — the panel stays open |
| Close the panel | <kbd>Esc</kbd>, <kbd>⌥⌘V</kbd>, or the menu bar icon |
| Delete an entry | Hover over it, click the ✕ |
| Clear everything | The trash icon in the header |

## How it works

Most of this app is ordinary. The one interesting trick: the panel is an `NSPanel` that **can never become the key or main window**. Because opening it never steals keyboard focus, the app you were working in stays frontmost the entire time — so pasting is just "put the text on the pasteboard, synthesize <kbd>⌘V</kbd>", and the keystroke lands in your app rather than in Clippy's own UI.

Two consequences of that design:

- There's deliberately no search field — a never-key window can't host one.
- Clicking elsewhere doesn't close the panel; that's what makes multi-paste work.

The hotkeys use Carbon's `RegisterEventHotKey`, which needs no special permission and consumes the keystroke so the frontmost app never also receives it. One caveat: while Clippy is running, <kbd>⌥⌘V</kbd> shadows Finder's little-known "Move Item Here" shortcut. If that bothers you, change the combination in `AppDelegate.setupHotKey()`.

## Privacy

- History is stored locally as JSON at `~/Library/Application Support/Clippy/history.json` and never leaves your machine. Clippy makes no network connections of any kind.
- Copies flagged as concealed or transient by their source (passwords, one-time codes) are skipped entirely.
- Anything a source *doesn't* flag is stored in plain text — if you copy something sensitive from an app that doesn't use the convention, delete the entry or use "Clear all".

## Limitations

- Text only — images, files, and rich text aren't captured (yet).
- Entries over 100,000 characters are skipped rather than stored truncated.
- The hotkey isn't configurable from the UI yet.

Issues and pull requests are welcome.

## License

[MIT](LICENSE) © 2026 Peter AjaNwachuku
