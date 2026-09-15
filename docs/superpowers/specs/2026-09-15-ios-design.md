# Noter on iOS: design

Date: 2026-09-15. Status: approved in conversation, awaiting written review.

## Goal

The same notes on the Mac and on every iPhone, with full editing on both, capture from the iOS
share sheet, and enrichment on the phone through the user's own API key. iOS ships through the
App Store; the Mac keeps Developer ID, Sparkle and Homebrew.

## Decisions taken

- Sync carrier: iCloud Drive files in the app's ubiquity container. Not CloudKit.
- Enrichment without a Mac: the user's Anthropic, OpenAI or Gemini key, stored in the device
  keychain. No hosted service. Without a key, notes stay as captured.
- Capture on the phone: an iOS share extension. The Shortcut stays documented for automation.
- Repo shape: one repository, one `project.yml`, targets Noter (macOS), NoterKit (package),
  NoterMobile (iOS), NoterShare (iOS extension). One version number for all.

## 1. Library location

Container id `iCloud.com.hexul.noter`, entitlement `com.apple.developer.icloud-container-identifiers`
and `com.apple.developer.ubiquity-container-identifiers` on both apps and the extension.
`Storage.resolveRootDirectory()` returns `<container>/Documents` when the container URL resolves,
else `~/Library/Application Support/Noter` as today.

Migration: on the first launch that sees an empty container and a non-empty Application Support
library, copy `notes/`, `metadata/` and `attachments/` into the container. The old folder is
left in place and never read again. A marker file `migrated-from-app-support` in the container
prevents a second copy.

The Mac app needs a provisioning profile carrying the iCloud entitlement; Developer ID
distribution supports this. The profile is embedded by xcodegen's signing settings and is a
one-time setup in the developer portal.

## 2. NoterKit

A local Swift package under `Noter/NoterKit`, Foundation only, depended on by all three app
targets and by `Package.swift` for tests. Contents, moved not rewritten:

- `Note`, `NoteMetadata`, `Storage` (with coordinated reads and writes, see 3)
- `LinkPreview`, `LimitedDownload`
- `Enrichment`: the request and reply shapes and the three API backends (Anthropic, OpenAI,
  Gemini). The agent-CLI backends (`agy`, `claude`, `codex`) and `ProcessRunner` stay in the
  Mac target.
- `JobQueue`, `Debounce`, `Inbox` drop parsing, `PastelColor` names (colour values stay in
  each UI layer).
- `CLI` and `MCPServer` stay in the Mac target; they depend on NoterKit.

Everything the apps call becomes `public`. Tests move with the code into `NoterKit/Tests`.

## 3. Change detection and coordination

- Mac: `LibraryWatcher` as built, on the container's `metadata/` folder.
- iOS: `NSMetadataQuery` scoped to the ubiquity container, `NSMetadataQueryUpdateDidChange`
  feeding the same `NoteStore.merge(fromDisk:)`. Files not yet downloaded are requested with
  `startDownloadingUbiquitousItem` when the list appears; a note whose body is still
  downloading shows its sidecar fields and a placeholder body.
- `Storage.save` and `load` wrap file access in `NSFileCoordinator` so a half-written pair is
  never uploaded. The atomic-write behaviour is kept inside the coordinated block.
- Conflicts: `NSFileVersion` conflicts are resolved by taking the version with the newest
  `modifiedAt` sidecar and discarding the other. Documented as last writer wins.

## 4. iOS app (NoterMobile)

SwiftUI, iOS 17 and later.

- List: pinned then recent, newest first; archived behind a toolbar toggle. Rows are the pastel
  card with title, tag row, byline with favicon and thumbnail, two-line excerpt.
- Note: editor bound to `content` with the same guard as `NotePanel` (external updates replace
  the buffer only while it still equals what was loaded). Title, tags, colour, pin, archive,
  delete in a toolbar menu. Attachments listed and previewable.
- Settings: provider picker, key field stored in the device keychain under service "Noter",
  a test button that calls the backend once, and About with version.
- Enrichment: a note tagged `inbox` is enriched on next foreground through the shared
  backends when a key is present. The Mac does the same today; whichever device sees it first
  wins, and the other sees the result through sync.

## 5. Share extension (NoterShare)

Accepts URL, plain text, image, PDF and generic files. Writes the note and any attachment
into the container through `Storage`, tagged `inbox`, with the same drop semantics as the
Shortcut (`url`, `title`, `text`, `input`, `file`). UI: title field, colour picker, Post.
The extension carries the same iCloud container entitlement as the app; no app group is needed because nothing is shared outside the container.

## 6. Distribution

- iOS: App Store Connect, TestFlight first. Requires a privacy policy URL (a page on
  `github.com/hex/Noter` is enough), App Store listing text, screenshots for 6.7" and 6.1".
- Mac: unchanged. The next Mac release carries the container move and NoterKit and ships
  before the iOS app.
- Version: `MARKETING_VERSION` shared. iOS build number uses the same `CURRENT_PROJECT_VERSION`.

## 7. Testing

- NoterKit: `swift test` from `Noter/NoterKit`. New tests: coordinated save/load round trip
  with two `Storage` instances, migration copies once, conflict pick by `modifiedAt`.
- Mac: existing suite, minus what moved.
- iOS: no UI tests; checked on the developer's phone before each TestFlight build.

## Order of work

1. NoterKit extraction and container move, shipped as a Mac release.
2. NoterMobile read-only list and note view, on the developer's phone.
3. Editing, settings, enrichment.
4. Share extension.
5. TestFlight, then App Store.

## Out of scope

Shared notes between users, widgets, Apple Watch, a Mac App Store build, the web.
