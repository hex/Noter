<img src="https://raw.githubusercontent.com/hex/Noter/main/docs/banner.svg" alt="Noter" width="100%" />

<h1 align="center">Noter</h1>

<p align="center">
  A frosted rail of colored dots at the edge of your screen, one per note;<br>
  click a dot and the note opens as a glass card beside it.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## Build and run

Noter is a signed macOS app bundle. The Xcode project is generated from `project.yml` by
[xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`):

```sh
xcodegen generate
xcodebuild -project Noter.xcodeproj -scheme Noter -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Noter.app
```

Signing uses the "Developer ID Application" identity of team `7G4UQW35EL` with the hardened
runtime; change `DEVELOPMENT_TEAM` in `project.yml` to build with another account. Versions follow
`YYYY.M.PATCH` (`MARKETING_VERSION`) with a date-encoded build number (`CURRENT_PROJECT_VERSION`)
that Sparkle compares to offer updates; both live in `project.yml`.

`Package.swift` stays for the tests only: `swift test`.

## Send things from your iPhone

Noter watches `iCloud Drive/Shortcuts/Noter/Inbox`, the folder Shortcuts' Save File action writes to. Anything the phone drops there as JSON becomes a note, and
a model writes a title, a four-line summary, and tags for it.

### 1. Have an agent CLI installed

Enrichment runs through a local agent CLI in print mode, so Noter holds no API key. Default is
`agy` with Gemini Flash; `claude` with Haiku is the alternate, switched in `Enricher.backend`. Either
must be logged in and installed under `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`.

### 2. Install the Shortcut

The shortcut is generated and signed on the Mac; Shortcuts syncs it to the iPhone through iCloud.

```sh
cd Shortcut && python3 build.py && open "Send to Noter.shortcut"
```

Click **Add Shortcut** in the window that opens. On the phone, share any page or text and tap
**Send to Noter**. A note appears on the Mac once iCloud syncs, usually within seconds, and is
rewritten a few seconds later. Select text on the page before sharing to give the summary more to
work with; pages behind a login cannot be fetched from the Mac.

Favourite the shortcut in the share sheet's actions row so it is one tap from the top.

The shortcut reads the page name, the page selection, any URLs, and the raw input, writes them as
JSON, and saves it as `iCloud Drive/Shortcuts/Noter/Inbox/<timestamp>.txt`; files it shares are saved
beside it as `<timestamp>-<name>`.

### What the drop looks like

```json
{"url": "https://example.com/post", "title": "Page title", "text": "selected text", "input": "raw shared input"}
```

Any key may be missing or empty; `input` is used when `text` is empty. A drop that is not valid JSON is left in the folder.

## Settings

Menu bar icon > Settings… (⌘,), or right-click anywhere on the rail. Stored in UserDefaults.

- **Launch at login** registers the app with `SMAppService`; it also shows under System Settings >
  General > Login Items, and macOS may ask for approval there the first time.
- **Window level**: on the desktop under app windows (default), or floating above them.
- **Rail**: left or right screen edge; how many dots show before the rail scrolls (3 to 12).
- **Summaries**: what writes titles and summaries. `agy`, Claude Code (`claude`) and Codex (`codex`)
  are detected when installed under `~/.local/bin`, Homebrew, `/usr/local/bin` or nvm; each runs in
  print mode with its own login. Pick any model name, or leave it empty for the tool's default.
  The three "API key" options (Anthropic, OpenAI, Gemini) call the provider directly. Paste a
  key and press Return to store it in your login keychain (service `Noter`, account `anthropic`,
  `openai` or `gemini`); nothing is written to a file. Without a stored key, Noter falls back to
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `GEMINI_API_KEY`, which only exist when Noter is
  started from a terminal, not from Finder or at login.
- **About**: version, links, and updates. **Check for Updates…** runs Sparkle against the feed in
  `project.yml` (`SUFeedURL`, `appcast.xml` on GitHub); automatic checks can be turned off.

## Icon

`Noter/noter-icon.png` is the 1024 source squircled 824-in-1024 for macOS 15 and earlier, which
do not mask icons. `Noter/noter-icon-fullbleed.png` is the unmasked square for Icon Composer on
macOS 26, where the system draws the shape and glass; open it there and export a `.icon` next to
the `.icns`. `Noter/Icon/AppIcon.iconset` and `AppIcon.icns` are sliced from it, and
`Assets.xcassets/AppIcon.appiconset` is sliced from the full-bleed square instead, because macOS 26
masks it itself and a pre-squircled image would render doubly inset; on macOS 14 and 15 it shows as
an unmasked square until the `.icon` is added. The menu bar uses a code-drawn template mark (`App/AppIcon.swift`).

## Layout

- `Sources/Noter/App` window, menu bar, tooltip panel, inbox watcher
- `Sources/Noter/Views` rail strip, note card, glass surface, shared metrics
- `Sources/Noter/Model` note, store, panel state, content kind, inbox, enricher, settings, login item
- `Sources/Noter/Persistence` markdown plus JSON sidecar storage

## License

MIT
