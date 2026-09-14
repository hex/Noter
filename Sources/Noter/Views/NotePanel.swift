// ABOUTME: Root SwiftUI view inside the NoterPanel: the note card beside the frosted rail strip.
// ABOUTME: The strip always stays at the screen edge; the card fades and slides in to its left.

import SwiftUI

struct NotePanel: View {
    @Bindable var store: NoteStore
    var panelState: PanelState
    var settings: Settings
    /// Asks the model to write title, summary and tags again for this note.
    var onRerun: (Note) -> Void
    var onSettings: () -> Void
    /// Hovered dot's note and frame in window coordinates; nil note on leave.
    var onDotHover: (Note?, CGRect) -> Void
    @State private var editingContent = ""
    @State private var editingNoteID: UUID?
    /// What the editor last loaded; when it still matches, external updates may replace the buffer.
    @State private var loadedContent = ""
    @FocusState private var editorFocused: Bool
    /// The note that was open before the current one; nil when the card is opening from closed.
    @State private var lastOpenID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openNote: Note? {
        guard panelState.isExpanded, let id = panelState.selectedNoteID else { return nil }
        return store.notes.first { $0.id == id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: RailMetrics.cardGap) {
            if settings.railSide == .left { rail }
            if let note = openNote {
                NoteCard(
                    note: note,
                    attachmentURLs: note.attachments.map(store.attachmentURL),
                    attachmentURL: store.attachmentURL,
                    content: $editingContent,
                    editorFocused: $editorFocused,
                    onClose: { panelState.collapse() },
                    onTogglePin: { update(note) { $0.isPinned.toggle() } },
                    onToggleArchive: { toggleArchive(note) },
                    onPickColor: { name in update(note) { $0.colorName = name } },
                    onRerun: {
                        saveContent()
                        if let fresh = store.notes.first(where: { $0.id == note.id }) { onRerun(fresh) }
                    },
                    onStep: { step(by: $0, from: note) },
                    onNew: createNote
                )
                .id(note.id)
                // Opening grows from the rail; switching notes only crossfades, so it reads as a change, not a reopen.
                .transition(panelState.isExpanded && lastOpenID != nil
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.96, anchor: settings.railSide == .right ? .trailing : .leading)))
            }
            if settings.railSide == .right { rail }
        }
        .padding(RailMetrics.shadowMargin)
        .padding(edge, RailMetrics.edgeInset - RailMetrics.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.railSide == .right ? .topTrailing : .topLeading)
        .animation(reduceMotion ? nil : (panelState.isExpanded ? Motion.enter : Motion.exit), value: panelState.isExpanded)
        .animation(reduceMotion ? nil : Motion.small, value: panelState.selectedNoteID)
        .onChange(of: panelState.selectedNoteID) { old, newID in
            lastOpenID = panelState.isExpanded ? old : nil
            saveContent()
            loadContent(for: newID)
            if panelState.isExpanded { editorFocused = true }
        }
        .onChange(of: openNote?.content) { _, external in
            // The store changed the open note (enrichment, phone sync). Take it unless the user has typed.
            guard let external, editingContent == loadedContent, external != editingContent else { return }
            editingContent = external
            loadedContent = external
        }
        .onChange(of: panelState.isExpanded) { _, expanded in
            if expanded {
                loadContent(for: panelState.selectedNoteID)
                editorFocused = true
            } else {
                saveContent()
                editorFocused = false
                lastOpenID = nil
            }
        }
    }

    /// The screen edge the rail sits against.
    private var edge: Edge.Set { settings.railSide == .right ? .trailing : .leading }

    private var rail: some View {
            RailStrip(
                notes: store.pinnedNotes + store.recentNotes,
                visibleDots: settings.visibleDots,
                faviconURL: { $0.preview?.faviconName.map(store.attachmentURL) },
                archived: panelState.showArchived ? store.archivedNotes : [],
                openNoteID: openNote?.id,
                onSelect: { note in panelState.selectNote(note, in: store) },
                onCreate: createNote,
                onArchive: toggleArchive,
                onPin: { note in update(note) { $0.isPinned.toggle() } },
                onSettings: onSettings,
                onHover: onDotHover
            )
    }

    private func createNote() {
        if let note = try? store.create(title: "") {
            panelState.selectedNoteID = note.id
            panelState.expand()
        }
    }

    /// ⌘↑ / ⌘↓: open the neighbouring note on the rail; the card content crossfades.
    private func step(by delta: Int, from note: Note) {
        let rail = store.pinnedNotes + store.recentNotes
        guard let i = rail.firstIndex(where: { $0.id == note.id }) else { return }
        let j = i + delta
        guard rail.indices.contains(j) else { return }
        panelState.selectNote(rail[j], in: store)
    }

    private func toggleArchive(_ note: Note) {
        update(note) { $0.isArchived.toggle() }
        if note.id == panelState.selectedNoteID, !note.isArchived { panelState.collapse() }
    }

    private func update(_ note: Note, _ change: (inout Note) -> Void) {
        var copy = note
        change(&copy)
        try? store.update(copy)
    }

    private func loadContent(for noteID: UUID?) {
        guard let id = noteID,
              let note = store.notes.first(where: { $0.id == id }) else {
            editingContent = ""
            loadedContent = ""
            editingNoteID = nil
            return
        }
        var body = note.content
        if let preview = note.preview {
            // Notes enriched before the byline existed still start with the link; the byline holds it now.
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            if let first = lines.first, first.hasPrefix("http"),
               first.contains(preview.url.host() ?? "\u{0}") {
                body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                var cleaned = note
                cleaned.content = body
                try? store.update(cleaned)
            }
        }
        editingContent = body
        loadedContent = body
        editingNoteID = note.id
    }

    private func saveContent() {
        guard let id = editingNoteID,
              var note = store.notes.first(where: { $0.id == id }),
              note.content != editingContent else { return }
        note.content = editingContent
        note.modifiedAt = Date()
        try? store.update(note)
    }
}
