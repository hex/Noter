<img src="https://raw.githubusercontent.com/hex/Noter/main/docs/banner-v2.svg" alt="Noter" width="100%" />

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

The platform-neutral model, storage and enrichment code is the `NoterKit` package in `NoterKit/`,
shared with the iOS app. `swift test` in the repo root runs the Mac tests; `swift test` in `NoterKit/`
runs the shared model, storage and enrichment tests.

## Send things from your iPhone

Notes live in iCloud Drive under Noter; a library from an earlier version is copied there on first
launch and left in place.

Noter watches `iCloud Drive/Shortcuts/Noter/Inbox`, the folder Shortcuts' Save File action writes to. Anything the phone drops there as JSON becomes a note, and
a model writes a title, a four-line summary, and tags for it.

A link in a note gets a preview card from the page's OpenGraph tags. GitHub repos and issues,
Reddit posts, YouTube videos, Hacker News items and X posts come from each site's own API
instead, with a detail line (stars, points, comments, channel) and the avatar or thumbnail.

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

## Notes from the shell and from agents

The app binary doubles as a command line when invoked as `noter`. The Homebrew cask links it into
your path; from a local build, symlink it yourself:

```sh
ln -s /Applications/Noter.app/Contents/MacOS/Noter /usr/local/bin/noter
```

Output is JSON, ids may be shortened to a unique prefix, and `-` reads a body from stdin. The
running app notices every write and updates the rail; the app does not need to be running.

```sh
noter list                      # active notes, newest first, with excerpts
noter list --archived           # or --all
noter show 6950                 # one note with its markdown body
noter add --title "Groceries" --tags home,food --color mint "milk\neggs"
pbpaste | noter add --title "Clipboard" -
noter edit 6950 --content - < body.md
noter edit 6950 --tags a,b --pin
noter archive 6950 | noter unarchive 6950 | noter delete 6950
```

`noter mcp` serves the same verbs as MCP tools over stdio (`list_notes`, `get_note`, `add_note`,
`edit_note`, `archive_note`, `unarchive_note`, `delete_note`):

```sh
claude mcp add noter -- noter mcp
```

Writes from the shell skip enrichment: the caller already chose the title and tags. Drop a JSON
file in the inbox instead when you want the model to write them.

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

`Noter.icon` is the app icon in Icon Composer format: `icon.json` plus one layer in `Assets/`, the
full-bleed artwork (`noter-icon-fullbleed.png`, which keeps its own painted shadows). macOS 26
masks it and adds its glass rim; for macOS 14 and 15 actool flattens it into `Noter.icns` at build
time, so no `.appiconset` is needed. `noter-icon.png` and `Icon/` are the pre-squircled legacy exports
kept for the README and docs. The menu bar uses a code-drawn template mark (`App/AppIcon.swift`).

## Layout

- `Sources/Noter/App` window, menu bar, tooltip panel, inbox watcher
- `Sources/Noter/Views` rail strip, note card, glass surface, shared metrics
- `Sources/Noter/Model` note, store, panel state, content kind, inbox, enricher, settings, login item
- `Sources/Noter/Persistence` markdown plus JSON sidecar storage

## License

MIT
