// ABOUTME: Menu bar status item for the Noter accessory app.
// ABOUTME: Provides New Note and Quit actions since there's no Dock icon.

import AppKit

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    var onNewNote: (() -> Void)?
    var onToggleArchived: (() -> Bool)?
    var onSettings: (() -> Void)?
    private var archivedItem: NSMenuItem?

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = AppIcon.statusItem()
            button.image?.accessibilityDescription = "Noter"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n"))
        let archived = NSMenuItem(title: "Show Archived", action: #selector(toggleArchived), keyEquivalent: "")
        menu.addItem(archived)
        archivedItem = archived
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Noter", action: #selector(quit), keyEquivalent: "q"))

        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc private func newNote() {
        onNewNote?()
    }

    @objc private func toggleArchived() {
        archivedItem?.state = onToggleArchived?() == true ? .on : .off
    }

    @objc private func settings() {
        onSettings?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
