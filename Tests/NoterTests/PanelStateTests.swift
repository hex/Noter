// ABOUTME: Tests for PanelState expand/collapse/selection transitions.
// ABOUTME: Covers note switching while open and selection survival across collapse.

import Testing
import Foundation
@testable import Noter

@Suite("Panel State")
struct PanelStateTests {
    private func makeStore() -> NoteStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelStateTests-\(UUID().uuidString)")
        return NoteStore(storage: Storage(rootDirectory: dir))
    }

    @Test("Selecting a note from collapsed expands")
    func selectFromCollapsedExpands() throws {
        let store = makeStore()
        let a = try store.create(title: "A")
        let state = PanelState()
        var changes: [Bool] = []
        state.onExpandedChanged = { changes.append($0) }

        state.selectNote(a, in: store)

        #expect(state.isExpanded)
        #expect(state.selectedNoteID == a.id)
        #expect(changes == [true])
    }

    @Test("Switching notes while expanded does not resize")
    func switchWhileExpandedDoesNotResize() throws {
        let store = makeStore()
        let a = try store.create(title: "A")
        let b = try store.create(title: "B")
        let state = PanelState()
        state.selectNote(a, in: store)
        var changes: [Bool] = []
        state.onExpandedChanged = { changes.append($0) }

        state.selectNote(b, in: store)

        #expect(state.isExpanded)
        #expect(state.selectedNoteID == b.id)
        #expect(changes.isEmpty)
    }

    @Test("Selecting the selected note collapses")
    func selectSelectedCollapses() throws {
        let store = makeStore()
        let a = try store.create(title: "A")
        let state = PanelState()
        state.selectNote(a, in: store)

        state.selectNote(a, in: store)

        #expect(!state.isExpanded)
    }

    @Test("Collapse keeps the selection for the rail highlight")
    func collapseKeepsSelection() throws {
        let store = makeStore()
        let a = try store.create(title: "A")
        let state = PanelState()
        state.selectNote(a, in: store)

        state.collapse()

        #expect(!state.isExpanded)
        #expect(state.selectedNoteID == a.id)
    }
}
