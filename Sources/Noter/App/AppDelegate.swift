// ABOUTME: Application delegate managing the panel lifecycle and screen positioning.
// ABOUTME: Creates the NoterPanel anchored to the right edge of the active screen.

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NoterPanel!
    private let statusBar = StatusBarController()
    private var store: NoteStore!
    private let panelState = PanelState()
    private let settings = Settings()
    private let loginItem = LoginItem()
    private let settingsWindow = SettingsWindowController()
    private let updater = UpdaterController()
    private let tooltip = BadgeTooltip()
    private var inboxWatcher: InboxWatcher?
    private var currentScreenID: CGDirectDisplayID?
    private var mouseMonitor: Any?
    private var hostingView: NSView?


    func applicationDidFinishLaunching(_ notification: Notification) {
        let storage = Storage(rootDirectory: Storage.resolveRootDirectory())
        store = NoteStore(storage: storage)
        try? store.loadFromDisk()

        if store.notes.isEmpty {
            _ = try? store.create(title: "Welcome", colorName: "lavender")
        }

        panelState.onExpandedChanged = { [weak self] expanded in
            self?.resizePanel(expanded: expanded)
        }

        installEditMenu()
        setupPanel()
        tooltip.attachmentURL = { [weak self] name in self?.store.attachmentURL(name) ?? URL(fileURLWithPath: "/") }
        tooltip.onOpen = { [weak self] note in
            guard let self else { return }
            self.tooltip.dismiss()
            self.panelState.selectNote(note, in: self.store)
        }
        statusBar.setup()
        statusBar.onSettings = { [weak self] in self?.openSettings() }
        inboxWatcher = InboxWatcher(inbox: Inbox(directory: Storage.inboxDirectory(), store: store))
        inboxWatcher?.start()
        statusBar.onToggleArchived = { [weak self] in
            guard let self else { return false }
            self.panelState.showArchived.toggle()
            self.panel.setFrame(self.panelState.isExpanded ? self.expandedFrame() : self.collapsedFrame(), display: true)
            return self.panelState.showArchived
        }
        statusBar.onNewNote = { [weak self] in
            guard let self else { return }
            if let note = try? self.store.create(title: "Untitled") {
                self.panelState.selectedNoteID = note.id
                self.panelState.expand()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )

        currentScreenID = screenUnderMouse().displayID
        startMouseMonitor()
        followRailSize()
        applySettings()
    }

    private func openSettings() {
        settingsWindow.show(settings: settings, loginItem: loginItem, updater: updater)
    }

    /// Pushes every preference into the objects that act on it, and re-arms itself after each change.
    private func applySettings() {
        withObservationTracking {
            Enricher.backend = settings.backend
            panel.apply(level: settings.windowLevel)
            _ = settings.visibleDots
            _ = settings.railSide
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tooltip.dismiss()
                self.panel.setFrame(self.panelState.isExpanded ? self.expandedFrame() : self.collapsedFrame(), display: true)
                self.pinHostingView()
                self.applySettings()
            }
        }
    }

    /// The rail grows when a note arrives and shrinks when one is archived; the window must follow,
    /// or the new dot lands outside it. Re-arms itself after every change.
    private func followRailSize() {
        withObservationTracking {
            _ = store.notes.count
            _ = store.archivedNotes.count
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                let frame = self.panelState.isExpanded ? self.expandedFrame() : self.collapsedFrame()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                    self.panel.animator().setFrame(frame, display: true)
                }
                self.followRailSize()
            }
        }
    }

    // MARK: - Monitor Tracking

    private func startMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.checkScreenChange()
        }
    }

    private func checkScreenChange() {
        guard !panelState.isExpanded else { return }
        let screen = screenUnderMouse()
        let newID = screen.displayID
        guard newID != currentScreenID else { return }
        currentScreenID = newID
        let frame = panelFrame(on: screen, expanded: false)
        panel.setFrame(frame, display: true)
    }

    /// An accessory app has no menu bar of its own, but AppKit still routes Undo, Cut, Copy,
    /// Paste and Select All through the main menu's key equivalents. Without this, none work.
    private func installEditMenu() {
        let main = NSMenu()
        let edit = NSMenuItem()
        main.addItem(edit)
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = menu
        NSApp.mainMenu = main
    }

    // MARK: - Panel

    private func setupPanel() {
        let screen = screenUnderMouse()
        let frame = panelFrame(on: screen, expanded: false)
        panel = NoterPanel(contentRect: frame)

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]

        // Constant width, pinned to the right edge: the window can widen leftward
        // without shifting SwiftUI's coordinate space, so slots animate in place.
        let notePanelView = NotePanel(store: store, panelState: panelState, settings: settings, onRerun: { [weak self] note in
            self?.inboxWatcher?.rerun(note)
        }, onSettings: { [weak self] in self?.openSettings() }) { [weak self] note, frame in
            guard let self else { return }
            // No peek while a card is open: the card already shows everything the peek would.
            if self.panelState.isExpanded { self.tooltip.dismiss(); return }
            // SwiftUI's global frame is in the window's flipped content space.
            let contentHeight = self.panel.contentView?.bounds.height ?? 0
            let appKitRect = NSRect(
                x: frame.minX, y: contentHeight - frame.maxY,
                width: frame.width, height: frame.height
            )
            // Sit beyond the whole panel, so an open card never hides the tooltip.
            var anchor = self.panel.convertToScreen(appKitRect)
            switch self.settings.railSide {
            case .right: anchor.origin.x = self.panel.frame.minX + RailMetrics.shadowMargin
            case .left: anchor.origin.x = self.panel.frame.maxX - RailMetrics.shadowMargin - anchor.width
            }
            self.tooltip.update(note: note, anchor: anchor, side: self.settings.railSide)
        }
        let hostingView = FirstMouseHostingView(rootView: notePanelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: RailMetrics.expandedWidth, height: frame.height)
        self.hostingView = hostingView
        pinHostingView()
        container.addSubview(hostingView)

        panel.contentView = container
        panel.orderFrontRegardless()
    }

    /// Constant width, pinned to the screen-edge side: the window can widen toward the screen
    /// centre without shifting SwiftUI's coordinate space, so slots animate in place.
    private func pinHostingView() {
        guard let hostingView, let container = panel.contentView else { return }
        switch settings.railSide {
        case .right:
            hostingView.frame.origin.x = container.bounds.width - RailMetrics.expandedWidth
            hostingView.autoresizingMask = [.height, .minXMargin]
        case .left:
            hostingView.frame.origin.x = 0
            hostingView.autoresizingMask = [.height, .maxXMargin]
        }
    }

    /// The window's x for a given width: flush with the chosen screen edge.
    private func edgeX(width: CGFloat, on screen: NSScreen) -> CGFloat {
        switch settings.railSide {
        case .right: screen.visibleFrame.maxX - width
        case .left: screen.visibleFrame.minX
        }
    }

    /// Expand: grow the (invisible) window instantly so SwiftUI can spring the card in.
    /// Collapse: let the card spring out, then shrink the window once it has settled.
    private func resizePanel(expanded: Bool) {
        if expanded {
            tooltip.dismiss()
            panel.setFrame(expandedFrame(), display: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseSettleDelay) { [weak self] in
            guard let self, !self.panelState.isExpanded else { return }
            self.panel.setFrame(self.collapsedFrame(), display: true)
        }
    }

    /// Long enough for NotePanel.closeAnimation to finish before the window shrinks.
    private static let collapseSettleDelay: TimeInterval = 0.3

    /// Dots on the rail: active notes, plus archived ones (and their divider slot) when shown.
    private var railCount: Int {
        let active = store.pinnedNotes.count + store.recentNotes.count
        return panelState.showArchived && !store.archivedNotes.isEmpty ? active + store.archivedNotes.count + 1 : active
    }

    /// Keeps the rail's top edge fixed while the window grows leftward and downward.
    private func expandedFrame() -> NSRect {
        let screen = panel.screen ?? screenUnderMouse()
        let visible = screen.visibleFrame
        let width = RailMetrics.expandedWidth
        let height = RailMetrics.expandedHeight(noteCount: railCount, visibleDots: settings.visibleDots)
        let top = max(panel.frame.maxY, visible.minY + height)
        return NSRect(x: edgeX(width: width, on: screen), y: top - height, width: width, height: height)
    }

    private func collapsedFrame() -> NSRect {
        let screen = panel.screen ?? screenUnderMouse()
        let height = RailMetrics.collapsedHeight(noteCount: railCount, visibleDots: settings.visibleDots)
        return NSRect(
            x: edgeX(width: RailMetrics.collapsedWidth, on: screen),
            y: panel.frame.maxY - height,
            width: RailMetrics.collapsedWidth,
            height: height
        )
    }

    /// Defer one runloop so the new key window is known; stay open if it is one of ours.
    @objc private func panelDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelState.isExpanded,
                  !self.panel.isKeyWindow, NSApp.keyWindow == nil else { return }
            self.panelState.collapse()
        }
    }

    /// Returns the screen containing the mouse cursor, falling back to the first screen.
    private func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.screens[0]
    }

    private func panelFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let visible = screen.visibleFrame
        let count = railCount
        let width = expanded ? RailMetrics.expandedWidth : RailMetrics.collapsedWidth
        let height = expanded ? RailMetrics.expandedHeight(noteCount: count, visibleDots: settings.visibleDots) : RailMetrics.collapsedHeight(noteCount: count, visibleDots: settings.visibleDots)
        let x = edgeX(width: width, on: screen)
        let y = visible.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

extension NSColor {
    var asSwiftUIColor: Color {
        Color(nsColor: self)
    }
}

extension NSScreen {
    /// The Core Graphics display ID for this screen.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
