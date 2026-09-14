// ABOUTME: Entry point for the Noter macOS edge-panel note-taking app.
// ABOUTME: Bootstraps NSApplication with AppDelegate for window lifecycle management.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
