// ABOUTME: Shared observable state for the panel's expand/collapse and selection.
// ABOUTME: Bridges SwiftUI views and AppKit panel frame management.

import Foundation
import NoterKit
import Observation

@Observable
final class PanelState {
    var isExpanded = false
    var selectedNoteID: UUID?
    /// Archived notes appear at the bottom of the rail while this is on.
    var showArchived = false

    /// Called by AppDelegate when the panel needs to resize.
    var onExpandedChanged: ((Bool) -> Void)?

    func selectNote(_ note: Note, in store: NoteStore) {
        if selectedNoteID == note.id && isExpanded {
            collapse()
        } else {
            selectedNoteID = note.id
            expand()
        }
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        onExpandedChanged?(true)
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        onExpandedChanged?(false)
    }
}
