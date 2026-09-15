# NoterKit and iCloud Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 1 of the iOS spec: the platform-neutral model, storage and enrichment code lives in a `NoterKit` package, and the library lives in the app's iCloud container, shipped as Mac release 2026.9.3.

**Architecture:** `Noter/NoterKit` is a local Swift package (Foundation, Observation, Security only) that the Mac app target and the root `Package.swift` test target depend on. Files move, they are not rewritten; types the app uses become `public`. `Storage.resolveRootDirectory` prefers the ubiquity container `iCloud.com.hexul.noter` and copies the Application Support library into it once. The Mac target keeps AppKit, SwiftUI, the agent-CLI enrichment backends, the CLI and the MCP server.

**Tech Stack:** Swift 5.9, xcodegen, Swift Testing, SwiftPM local package, iCloud Documents entitlement, Developer ID provisioning profile.

**Spec:** `Noter/docs/superpowers/specs/2026-09-15-ios-design.md`

## Global Constraints

- Deployment target macOS 14.0; NoterKit `platforms: [.macOS(.v14), .iOS(.v17)]`.
- NoterKit imports only Foundation, Observation and Security. No AppKit, no SwiftUI.
- iCloud container id: `iCloud.com.hexul.noter`. Bundle id stays `com.hexul.noter`, team `7G4UQW35EL`.
- Files move with `git mv`; no rewrites. Every source file keeps its two `ABOUTME:` lines.
- `xcodegen generate` after every `project.yml` change and after adding any new source file; `Info.plist` is generated and committed.
- `swift test` runs from `Noter/` and must stay green after every task. The current count is 134.
- No push to `hex/Noter` without Alex's ok. Release 2026.9.3 follows Snip's playbook at `~/.claude-sessions/Snip/.claude/commands/release.md`; the ASC key-id and issuer are read from `~/.appstoreconnect/config.json`, never written into a tracked file.
- Commits end with `Claude-Session: https://claude.ai/code/session_01H6eKyoFUzhZ8dz2DuuS6yY`.

---

## File map after phase 1

```
Noter/NoterKit/Package.swift
Noter/NoterKit/Sources/NoterKit/
  Note.swift                 (from Sources/Noter/Model)
  NoteStore.swift            (from Sources/Noter/Model)
  Storage.swift              (from Sources/Noter/Persistence) + resolveRootDirectory container logic + migrate
  LinkPreview.swift, LimitedDownload.swift, Inbox.swift, JobQueue.swift, Debounce.swift, APIKey.swift
  PastelColor.swift          (new: the enum cases and next(after:) only)
  Enrichment.swift           (new: Enrichment struct, EnrichmentError, prompt, parse, apply, schemaJSON, API request)
Noter/NoterKit/Tests/NoterKitTests/
  NoteTests, NoteContentTests, TagsTests, StorageTests, StorageWriteTests, NoteStoreTests, ArchiveTests,
  AttachmentsTests, LinkPreviewTests, UnfurlTests, LimitedDownloadTests, InboxTests, InboxWriteTests,
  JobQueueTests, DebounceTests, EnrichmentTests (API half of EnricherTests), PaletteTests (cycling half of
  PastelColorsTests), MigrationTests (new)
Noter/Sources/Noter/Theme/PastelColors.swift   (extension PastelColor: colours only)
Noter/Sources/Noter/Model/Enricher.swift        (Tool, Backend, run, locate, enrich; CLI half)
Noter/Noter.entitlements                        (+ iCloud keys)
Noter/project.yml                               (NoterKit package, signing, entitlements)
Noter/Package.swift                             (NoterKit dependency)
```

The exact test file split is decided at execution time by reading each file: a test moves when everything it imports is in NoterKit.

---

### Task 1: NoterKit package skeleton wired into both build systems

**Files:**
- Create: `Noter/NoterKit/Package.swift`, `Noter/NoterKit/Sources/NoterKit/NoterKit.swift`, `Noter/NoterKit/Tests/NoterKitTests/SmokeTests.swift`
- Modify: `Noter/project.yml` (packages + dependencies), `Noter/Package.swift`

**Interfaces:**
- Produces: module `NoterKit` importable from the app target and from `NoterTests`.

- [ ] **Step 1: Write the package**

```swift
// Noter/NoterKit/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoterKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "NoterKit", targets: ["NoterKit"])],
    targets: [
        .target(name: "NoterKit"),
        .testTarget(name: "NoterKitTests", dependencies: ["NoterKit"]),
    ]
)
```

```swift
// Noter/NoterKit/Sources/NoterKit/NoterKit.swift
// ABOUTME: Platform-neutral model, storage and enrichment shared by the Mac app, the iOS app and the noter CLI.
// ABOUTME: Foundation only; UI, process spawning and the panel live in each app target.

public enum NoterKitInfo {
    public static let name = "NoterKit"
}
```

```swift
// Noter/NoterKit/Tests/NoterKitTests/SmokeTests.swift
// ABOUTME: Proves the NoterKit test target builds and links against the package.
// ABOUTME: Replaced by real tests as files move in.
import Testing
@testable import NoterKit

@Test("NoterKit links") func links() { #expect(NoterKitInfo.name == "NoterKit") }
```

- [ ] **Step 2: Run the package's own tests**

Run: `cd Noter/NoterKit && swift test`
Expected: 1 test passes.

- [ ] **Step 3: Wire into project.yml and the root Package.swift**

In `Noter/project.yml` add under `packages:`:

```yaml
  NoterKit:
    path: NoterKit
```

and under `targets.Noter.dependencies:`:

```yaml
      - package: NoterKit
```

In `Noter/Package.swift` add `.package(path: "NoterKit")` to `dependencies` and `.product(name: "NoterKit", package: "NoterKit")` to the `Noter` target's dependencies.

- [ ] **Step 4: Regenerate and build both**

Run: `cd Noter && xcodegen generate && swift test 2>&1 | rg "Test run with" && xcodebuild -project Noter.xcodeproj -scheme Noter -configuration Debug -derivedDataPath DerivedData build 2>&1 | rg "BUILD"`
Expected: 134 tests pass; BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Noter/NoterKit Noter/project.yml Noter/Package.swift Noter/Info.plist
git commit -m "NoterKit package skeleton, linked into the app and the tests"
```

---

### Task 2: Move Note, Storage, LinkPreview, LimitedDownload and the palette names

**Files:**
- Move: `Sources/Noter/Model/Note.swift`, `Sources/Noter/Persistence/Storage.swift`, `Sources/Noter/Model/LinkPreview.swift`, `Sources/Noter/Model/LimitedDownload.swift` → `NoterKit/Sources/NoterKit/`
- Create: `NoterKit/Sources/NoterKit/PastelColor.swift`
- Modify: `Sources/Noter/Theme/PastelColors.swift` (becomes an extension), every file that uses these types gets `import NoterKit`
- Move tests: `NoteTests`, `NoteContentTests`, `TagsTests`, `StorageTests`, `StorageWriteTests`, `LinkPreviewTests`, `UnfurlTests`, `LimitedDownloadTests` → `NoterKit/Tests/NoterKitTests/`; the "Next color cycles" test of `PastelColorsTests` → `NoterKit/Tests/NoterKitTests/PaletteTests.swift`
- Delete: `NoterKit/Sources/NoterKit/NoterKit.swift`, `SmokeTests.swift`

**Interfaces:**
- Produces: `public struct Note`, `public struct Storage`, `public struct LinkPreview`, `public enum LimitedDownload`, `public enum PastelColor: String, CaseIterable, Codable, Sendable` with `public static func next(after:)`. Every stored property and initializer the app or tests use is `public`; `Note.init` keeps its defaulted parameters and becomes `public init(...)`.

- [ ] **Step 1: Move the files**

```bash
cd Noter
git mv Sources/Noter/Model/Note.swift NoterKit/Sources/NoterKit/Note.swift
git mv Sources/Noter/Persistence/Storage.swift NoterKit/Sources/NoterKit/Storage.swift
git mv Sources/Noter/Model/LinkPreview.swift NoterKit/Sources/NoterKit/LinkPreview.swift
git mv Sources/Noter/Model/LimitedDownload.swift NoterKit/Sources/NoterKit/LimitedDownload.swift
git rm -q NoterKit/Sources/NoterKit/NoterKit.swift NoterKit/Tests/NoterKitTests/SmokeTests.swift
```

- [ ] **Step 2: Split PastelColor**

`NoterKit/Sources/NoterKit/PastelColor.swift`:

```swift
// ABOUTME: The eight sticky-note colour names a note can carry, and the order they cycle in.
// ABOUTME: The colour values live in each app's theme; the model only knows the names.

public enum PastelColor: String, CaseIterable, Codable, Sendable {
    case lavender, mint, peach, sky, rose, lemon, coral, sage

    /// The palette entry after `name`, wrapping around; unknown names start from the first.
    public static func next(after name: String) -> PastelColor {
        let all = allCases
        guard let i = all.firstIndex(where: { $0.rawValue == name }) else { return all[0] }
        return all[(i + 1) % all.count]
    }
}
```

`Sources/Noter/Theme/PastelColors.swift` keeps only the AppKit half: change `enum PastelColor: ... {` to `extension PastelColor {`, delete the `case` lines and `next(after:)`, add `import NoterKit`.

- [ ] **Step 3: Make the moved types public**

In each moved file: `struct` → `public struct`, `enum` → `public enum`, every `var`/`let`/`func`/`init`/`static` the app or tests call → `public`. Nested `Site` in `LinkPreview` becomes `public enum Site: Equatable`. `Storage.resolveRootDirectory`, `inboxDirectory`, `metadataDirectory`, `attachmentsDirectory`, `save`, `load`, `loadAll`, `delete`, `attachmentURL` are all public. Keep `private` what is private today.

- [ ] **Step 4: Import NoterKit where the types are used**

Run: `rg -l "Note\b|Storage|LinkPreview|LimitedDownload|PastelColor" Sources/Noter Tests/NoterTests | xargs -I{} sed -i '' '0,/^import Foundation$/s//import Foundation\nimport NoterKit/' {}` then hand-check files that import AppKit or SwiftUI first and add `import NoterKit` after their first import. Test files use `@testable import NoterKit` next to `@testable import Noter`.

- [ ] **Step 5: Move the tests and fix their imports**

```bash
for t in NoteTests NoteContentTests TagsTests StorageTests StorageWriteTests LinkPreviewTests UnfurlTests LimitedDownloadTests; do
  git mv Tests/NoterTests/$t.swift NoterKit/Tests/NoterKitTests/$t.swift
  sed -i '' 's/@testable import Noter$/@testable import NoterKit/' NoterKit/Tests/NoterKitTests/$t.swift
done
```

Create `NoterKit/Tests/NoterKitTests/PaletteTests.swift` holding the "Next color cycles through all colors and wraps around" test verbatim from `PastelColorsTests.swift`, with `@testable import NoterKit`; delete that test from `PastelColorsTests.swift`.

- [ ] **Step 6: Build until both suites are green**

Run: `cd Noter/NoterKit && swift test 2>&1 | rg "error:|Test run with"; cd .. && xcodegen generate && swift test 2>&1 | rg "error:|Test run with"`
Expected: NoterKit suite runs the moved tests; the root suite runs the rest; the two counts sum to 134. Fix `public` omissions the compiler names; add nothing else.

- [ ] **Step 7: App build**

Run: `xcodebuild -project Noter.xcodeproj -scheme Noter -configuration Debug -derivedDataPath DerivedData build 2>&1 | rg "error:|BUILD"`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add -A Noter/NoterKit Noter/Sources Noter/Tests Noter/Noter.xcodeproj/project.pbxproj Noter/Info.plist
git commit -m "Note, Storage, LinkPreview and the palette names move to NoterKit"
```

---

### Task 3: Move NoteStore, Inbox, JobQueue, Debounce, APIKey

**Files:**
- Move: `Sources/Noter/Model/{NoteStore,Inbox,JobQueue,Debounce,APIKey}.swift` → `NoterKit/Sources/NoterKit/`
- Move tests: `NoteStoreTests`, `ArchiveTests`, `AttachmentsTests`, `InboxTests`, `InboxWriteTests`, `JobQueueTests`, `DebounceTests` → `NoterKit/Tests/NoterKitTests/`

**Interfaces:**
- Produces: `public final class NoteStore` (`@Observable`), `public struct Inbox`, `public struct InboxDrop`, `public actor JobQueue`, `@MainActor public final class Debounce`, `public enum APIProvider`, `public enum APIKey`.

- [ ] **Step 1: Move and publicise**

Same recipe as Task 2 steps 1, 3, 4, 5 for these five files and seven test files. `NoteStore.merge(fromDisk:)`, `mergeFromDisk()`, `add`, `create`, `update`, `delete`, `attach`, `loadFromDisk`, `loadFromDiskInBackground`, `notes`, `pinnedNotes`, `recentNotes`, `archivedNotes`, `nextColor`, `attachmentURL` are public. `Inbox.pendingTag`, `importPending`, `attachmentLookup` public.

- [ ] **Step 2: Green on both suites and the app build**

Run the three commands from Task 2 steps 6 and 7. Expected: totals still 134; BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add -A Noter/NoterKit Noter/Sources Noter/Tests Noter/Noter.xcodeproj/project.pbxproj
git commit -m "NoteStore, Inbox, JobQueue, Debounce and APIKey move to NoterKit"
```

---

### Task 4: Split Enricher into NoterKit's Enrichment and the Mac's Enricher

**Files:**
- Create: `NoterKit/Sources/NoterKit/Enrichment.swift`
- Modify: `Sources/Noter/Model/Enricher.swift`
- Create test: `NoterKit/Tests/NoterKitTests/EnrichmentTests.swift` (the request and parse tests from `EnricherTests`)
- Modify test: `Tests/NoterTests/EnricherTests.swift` keeps the argument and codex tests

**Interfaces:**
- Produces in NoterKit:

```swift
public struct Enrichment: Codable, Equatable { public var title, summary: String; public var tags: [String]; public var color: String }
public enum EnrichmentError: Error, Equatable { case badReply(String), missingKey(APIProvider) }
public enum EnrichmentAPI {
    public static let schemaJSON: String
    public static func prompt(for note: Note, attachments: [URL] = []) -> String
    public static func parse(_ data: Data) throws -> Enrichment
    public static func apply(_ e: Enrichment, to note: Note) -> Note
    public static func request(prompt: String, model: String, provider: APIProvider, apiKey: String) throws -> URLRequest
    public static func enrich(_ note: Note, provider: APIProvider, model: String) async throws -> Note
    public static func firstJSONObject(in text: String) -> String?
}
```

- Consumes: `Note`, `APIProvider`, `APIKey`, `PastelColor` from earlier tasks.
- The Mac `Enricher` keeps `Tool`, `Backend`, `backend`, `cliTimeout`, `run`, `locate`, `schemaFile`, `enrich(_:attachments:)`; `EnricherError` keeps `binaryNotFound`, `cli`, `timedOut` and gains nothing. `Enricher.enrich` calls `EnrichmentAPI.enrich` when `backend.tool.provider != nil`, else runs the CLI and calls `EnrichmentAPI.parse` and `apply`.

- [ ] **Step 1: Write the failing NoterKit test**

Move the tests "Anthropic request", "OpenAI request", "Gemini request", "Replies from the three APIs are parsed", "API error envelopes surface their message" from `EnricherTests.swift` into `EnrichmentTests.swift`, renaming `Enricher.request(prompt:model:tool:apiKey:)` calls to `EnrichmentAPI.request(prompt:model:provider:apiKey:)` with `.anthropic`, `.openai`, `.gemini`, and `Enricher.parse` to `EnrichmentAPI.parse`.

- [ ] **Step 2: Run to see it fail**

Run: `cd Noter/NoterKit && swift test 2>&1 | rg "error:" | head -3`
Expected: `cannot find 'EnrichmentAPI'`.

- [ ] **Step 3: Create Enrichment.swift by moving code**

Cut from `Enricher.swift` into `Enrichment.swift`: the `Enrichment` struct, `schemaJSON`, `prompt(for:attachments:)`, `parse`, `apiText(in:)`, `firstJSONObject`, `apply`, `request` (switch on `APIProvider` instead of `Tool`; the `.anthropicAPI, .agy, .claude, .codex` case becomes `.anthropic`), `callAPI`. Add:

```swift
public static func enrich(_ note: Note, provider: APIProvider, model: String) async throws -> Note {
    guard let key = APIKey.load(provider) else { throw EnrichmentError.missingKey(provider) }
    let data = try await callAPI(try request(prompt: prompt(for: note), model: model, provider: provider, apiKey: key))
    return apply(try parse(data), to: note)
}
```

`parse` throws `EnrichmentError.badReply` where it threw `EnricherError.badReply`. Two `ABOUTME:` lines at the top.

- [ ] **Step 4: Point the Mac Enricher at it**

In `Enricher.swift`: `import NoterKit`; delete the moved members; `enrich` becomes:

```swift
static func enrich(_ note: Note, attachments: [URL] = []) async throws -> Note {
    if let provider = backend.tool.provider {
        return try await EnrichmentAPI.enrich(note, provider: provider, model: backend.model)
    }
    let prompt = EnrichmentAPI.prompt(for: note, attachments: attachments)
    let output = try await run(backend, prompt: prompt, readsFiles: !attachments.isEmpty)
    return EnrichmentAPI.apply(try EnrichmentAPI.parse(output), to: note)
}
```

`Backend.arguments` references `EnrichmentAPI.schemaJSON`; `schemaFile()` writes `EnrichmentAPI.schemaJSON`. Remove `badReply` from `EnricherError`; any Mac test asserting it moves to `EnrichmentError.badReply`.

- [ ] **Step 5: Green on both suites and the app build**

Run the three commands from Task 2 steps 6 and 7. Expected: totals 134; BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add -A Noter/NoterKit Noter/Sources/Noter/Model/Enricher.swift Noter/Tests/NoterTests/EnricherTests.swift Noter/Noter.xcodeproj/project.pbxproj
git commit -m "Enrichment prompt, parsing and API calls move to NoterKit; the Mac keeps the agent CLIs"
```

---

### Task 5: Library in the iCloud container, with a one-time migration

**Files:**
- Modify: `NoterKit/Sources/NoterKit/Storage.swift` (`resolveRootDirectory`, new `migrate`)
- Modify: `Noter/Noter.entitlements`, `Noter/project.yml`
- Create test: `NoterKit/Tests/NoterKitTests/MigrationTests.swift`
- Modify: `Sources/Noter/App/AppDelegate.swift` (call migrate before loading)

**Interfaces:**
- Produces:

```swift
public static let containerID = "iCloud.com.hexul.noter"
public static func resolveRootDirectory(fileManager: FileManager = .default) -> URL
/// Copies notes, metadata and attachments from `legacy` into `root` once, marked by a file. Returns true when it copied.
public static func migrate(from legacy: URL, to root: URL, fileManager: FileManager = .default) throws -> Bool
```

- [ ] **Step 1: Write the failing migration test**

```swift
// ABOUTME: Tests for the one-time copy of an Application Support library into the iCloud container.
// ABOUTME: Uses two temporary folders; no iCloud.
import Testing
import Foundation
@testable import NoterKit

@Suite("Migration")
struct MigrationTests {
    @Test("A legacy library is copied once, and the copy is not repeated")
    func copiesOnce() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("noter-migrate-\(UUID().uuidString)")
        let legacy = base.appendingPathComponent("legacy"), root = base.appendingPathComponent("container")
        let old = Storage(rootDirectory: legacy)
        let note = Note(title: "Old", colorName: "sky", content: "body")
        try old.save(note)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try Data("img".utf8).write(to: legacy.appendingPathComponent("attachments/a.png"))

        #expect(try Storage.migrate(from: legacy, to: root) == true)
        let new = Storage(rootDirectory: root)
        #expect(try new.load(id: note.id).content == "body")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("attachments/a.png").path))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("metadata/\(note.id.uuidString).json").path))

        try old.save(Note(title: "Later", colorName: "sky"))
        #expect(try Storage.migrate(from: legacy, to: root) == false)
        #expect(try new.loadAll().count == 1)
    }

    @Test("Nothing to migrate when the legacy folder is missing or the container already has notes")
    func skips() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("noter-migrate-\(UUID().uuidString)")
        let legacy = base.appendingPathComponent("legacy"), root = base.appendingPathComponent("container")
        #expect(try Storage.migrate(from: legacy, to: root) == false)
        try Storage(rootDirectory: root).save(Note(title: "Cloud", colorName: "sky"))
        try Storage(rootDirectory: legacy).save(Note(title: "Old", colorName: "sky"))
        #expect(try Storage.migrate(from: legacy, to: root) == false)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd Noter/NoterKit && swift test 2>&1 | rg "error:" | head -2`
Expected: `type 'Storage' has no member 'migrate'`.

- [ ] **Step 3: Implement**

In `Storage.swift`:

```swift
public static let containerID = "iCloud.com.hexul.noter"
static let migrationMarker = "migrated-from-app-support"

/// The iCloud container when the account and entitlement allow it, else Application Support.
public static func resolveRootDirectory(fileManager: FileManager = .default) -> URL {
    if let container = fileManager.url(forUbiquityContainerIdentifier: containerID) {
        return container.appendingPathComponent("Documents")
    }
    return legacyRootDirectory(fileManager: fileManager)
}

public static func legacyRootDirectory(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Noter")
}

@discardableResult
public static func migrate(from legacy: URL, to root: URL, fileManager: FileManager = .default) throws -> Bool {
    let marker = root.appendingPathComponent(migrationMarker)
    guard legacy != root, !fileManager.fileExists(atPath: marker.path),
          fileManager.fileExists(atPath: legacy.appendingPathComponent("metadata").path),
          try Storage(rootDirectory: root).loadAll().isEmpty else { return false }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    for folder in ["notes", "metadata", "attachments"] {
        let src = legacy.appendingPathComponent(folder), dst = root.appendingPathComponent(folder)
        guard fileManager.fileExists(atPath: src.path) else { continue }
        if fileManager.fileExists(atPath: dst.path) { try fileManager.removeItem(at: dst) }
        try fileManager.copyItem(at: src, to: dst)
    }
    try Data(ISO8601DateFormatter().string(from: Date()).utf8).write(to: marker)
    return true
}
```

`url(forUbiquityContainerIdentifier:)` can block on first call; `AppDelegate` calls `resolveRootDirectory` once, off the main thread, inside the existing launch `Task` before `loadFromDiskInBackground`, and then `Storage.migrate(from: Storage.legacyRootDirectory(), to: root)`. Keep the `Storage` value the app holds pointed at the resolved root.

- [ ] **Step 4: Entitlements**

`Noter/Noter.entitlements` gains:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.hexul.noter</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudDocuments</string></array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array><string>iCloud.com.hexul.noter</string></array>
```

and `project.yml` `entitlements.properties` mirrors the same three keys so xcodegen does not strip them.

- [ ] **Step 5: Run the tests, then build**

Run: `cd Noter/NoterKit && swift test 2>&1 | rg "Test run with"; cd .. && xcodegen generate && xcodebuild -project Noter.xcodeproj -scheme Noter -configuration Debug -derivedDataPath DerivedData build 2>&1 | rg "error:|BUILD"`
Expected: 2 new tests pass; the build fails on signing until Task 6 provides a profile, or succeeds with the automatic development profile if Xcode can create one. Either outcome is fine here; record which.

- [ ] **Step 6: Commit**

```bash
git add Noter/NoterKit/Sources/NoterKit/Storage.swift Noter/NoterKit/Tests/NoterKitTests/MigrationTests.swift Noter/Noter.entitlements Noter/project.yml Noter/Sources/Noter/App/AppDelegate.swift Noter/Info.plist Noter/Noter.xcodeproj/project.pbxproj
git commit -m "Library lives in the iCloud container; the Application Support library is copied in once"
```

---

### Task 6: Signing with an iCloud-capable Developer ID profile (Alex's hands)

**Files:**
- Modify: `Noter/project.yml` (signing settings)

**Interfaces:**
- Produces: a Release build whose signature carries the three iCloud entitlements and passes notarization.

- [ ] **Step 1: Ask Alex to create the profile**

In the developer portal for team `7G4UQW35EL`: Identifiers → `com.hexul.noter` → enable iCloud with container `iCloud.com.hexul.noter` (create the container if absent) → Profiles → new **Developer ID Application** profile for that App ID → download → double-click to install. Report the profile's name back.

- [ ] **Step 2: Point the project at it**

In `project.yml` under `targets.Noter.settings.base`:

```yaml
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "Developer ID Application"
        PROVISIONING_PROFILE_SPECIFIER: "<profile name from step 1>"
```

For Debug, keep automatic signing so local builds work: put the three lines under `settings.configs.Release` instead of `base` if the Debug build refuses them.

- [ ] **Step 3: Verify the entitlements are in the signed build**

Run: `cd Noter && xcodegen generate && xcodebuild -project Noter.xcodeproj -scheme Noter -configuration Release -derivedDataPath DerivedData build 2>&1 | rg "error:|BUILD"; ditto DerivedData/Build/Products/Release/Noter.app "$TMPDIR/Noter.app" && codesign -d --entitlements :- "$TMPDIR/Noter.app" 2>/dev/null | rg -c "iCloud.com.hexul.noter"`
Expected: BUILD SUCCEEDED; count 2.

- [ ] **Step 4: Live check on Alex's Mac**

Launch the Release build. Expected: `~/Library/Mobile Documents/iCloud~com~hexul~noter/Documents/` contains `notes`, `metadata`, `attachments` and `migrated-from-app-support`; the rail shows every note it showed before; `noter list` (symlinked to the new binary) lists the same notes. Alex confirms in Finder that the folder appears under iCloud Drive.

- [ ] **Step 5: Commit**

```bash
git add Noter/project.yml Noter/Info.plist Noter/Noter.xcodeproj/project.pbxproj
git commit -m "Release builds sign with the iCloud-capable Developer ID profile"
```

---

### Task 7: README and cask, then release 2026.9.3

**Files:**
- Modify: `Noter/README.md` (library location, NoterKit, `swift test` in two places), `Noter/project.yml` (version), `Noter/appcast.xml`
- Modify in `hex/homebrew-tap`: `Casks/noter.rb` (add `binary` stanza)

- [ ] **Step 1: README**

Under "Build and run" replace the `Package.swift` sentence with: "`swift test` in `Noter/` runs the Mac tests; `swift test` in `Noter/NoterKit/` runs the shared model, storage and enrichment tests." Add to "Send things from your iPhone": "Notes live in iCloud Drive under Noter; a library from an earlier version is copied there on first launch and left in place." In the "Notes from the shell" section drop the "symlink it yourself" step once the cask links it.

- [ ] **Step 2: Cask**

In `Casks/noter.rb` after the `app` stanza add:

```ruby
  binary "#{appdir}/Noter.app/Contents/MacOS/Noter", target: "noter"
```

Committed together with the version bump in step 4.

- [ ] **Step 3: Release notes**

Group as: Features (notes in iCloud Drive; `noter` command line and MCP server; site unfurls if not already released), Fixes, Internal (NoterKit). Run `/write-as-me` voice pass and Vale before showing them. Gate on Alex's approval with AskUserQuestion.

- [ ] **Step 4: Cut the release**

Follow Snip's playbook end to end: bump `MARKETING_VERSION` to `2026.9.3` and `CURRENT_PROJECT_VERSION` to the date plus counter; Release build; `codesign --deep --options runtime --timestamp`; notarize app zip; staple; `ditto --norsrc --noextattr` zip; `sign_update --account Noter`; DMG signed, notarized, stapled; appcast item; mirror two commits to `hex/Noter` as `hex`; tag; `gh release create` with both artifacts; cask bump with the DMG sha and the `binary` line; `brew audit --cask hex/tap/noter`.

- [ ] **Step 5: Verify**

Run: `curl -s https://raw.githubusercontent.com/hex/Noter/main/appcast.xml | rg -m1 "sparkle:version"; brew upgrade --cask hex/tap/noter && which noter && noter list | jq length`
Expected: the new build number; `/opt/homebrew/bin/noter`; the note count. Alex confirms the installed app offered and applied the Sparkle update.

---

## Self-review

- Spec coverage: §1 library location → Tasks 5, 6; §2 NoterKit → Tasks 1–4; §3 change detection → the Mac watcher already exists and now watches the container path through `metadataDirectory`; coordinated writes and the iOS `NSMetadataQuery` are phase 2 and are not in this plan; §6 Mac release → Task 7; §7 NoterKit tests → Tasks 2–5. Not covered here by design: §4, §5, the iOS half of §3 and §6.
- Placeholders: Task 6 step 2 carries the profile name Alex reports; that is an input, not a placeholder. Test-file split in Tasks 2 and 3 is decided by imports at execution time, stated as such.
- Types: `EnrichmentAPI.request(prompt:model:provider:apiKey:)` and `enrich(_:provider:model:)` are used identically in Task 4 steps 1, 3 and 4. `Storage.migrate(from:to:fileManager:)` matches between test and implementation. `Storage.legacyRootDirectory()` is defined in Task 5 and used in Tasks 5 and 6.
