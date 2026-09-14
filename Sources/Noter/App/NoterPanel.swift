// ABOUTME: Floating NSPanel subclass for the edge-anchored note panel.
// ABOUTME: Borderless, non-activating by default, becomes key for text editing.

import AppKit
import SwiftUI

final class NoterPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        apply(level: .desktop)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }

    /// Desktop: like a widget, above the wallpaper and below every app window, so Show Desktop
    /// or a click on the wallpaper reveals it. Floating: above app windows.
    func apply(level choice: WindowLevelChoice) {
        switch choice {
        case .desktop: level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating: level = .floating
        }
    }
}

/// Delivers the first click on a non-key panel to the view instead of spending it on focus.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
