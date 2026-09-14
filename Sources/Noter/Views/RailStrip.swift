// ABOUTME: The frosted strip at the screen edge holding one dot per note and a plus button.
// ABOUTME: Dots are the note color; empty notes are rings; the open note wears a halo.

import SwiftUI

struct RailStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let notes: [Note]
    let visibleDots: Int
    let faviconURL: (Note) -> URL?
    let archived: [Note]
    let openNoteID: UUID?
    let onSelect: (Note) -> Void
    let onCreate: () -> Void
    let onArchive: (Note) -> Void
    let onPin: (Note) -> Void
    let onSettings: () -> Void
    /// Hover with the dot's frame in window coordinates; nil note on leave.
    let onHover: (Note?, CGRect) -> Void

    var body: some View {
        VStack(spacing: RailMetrics.dotGap) {
            dots
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Label.tertiary)
                    .frame(width: RailMetrics.stripWidth, height: RailMetrics.plusButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, RailMetrics.plusGap - RailMetrics.dotGap)
        }
        .padding(.vertical, RailMetrics.stripPadding)
        .frame(width: RailMetrics.stripWidth)
        .glass(radius: RailMetrics.stripWidth / 2, lift: 0.6, opacity: 0)
        .contextMenu { Button("Settings…", action: onSettings) }
        .animation(reduceMotion ? nil : Motion.settle, value: notes.map(\.id) + archived.map(\.id))
    }
}

extension RailStrip {
    private var overflowing: Bool { notes.count + (archived.isEmpty ? 0 : archived.count + 1) > visibleDots }

    /// The first seven dots are always in view; beyond that the column scrolls under a fade.
    @ViewBuilder
    private var dots: some View {
        let column = VStack(spacing: RailMetrics.dotGap) {
            ForEach(notes) { note in
                RailDot(note: note, isOpen: note.id == openNoteID, faviconURL: faviconURL(note), onTap: { onSelect(note) }, onHover: onHover)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .contextMenu {
                        Button(note.isPinned ? "Unpin" : "Pin") { onPin(note) }
                        Button("Archive") { onArchive(note) }
                        Divider()
                        Button("Settings…", action: onSettings)
                    }
            }
            if !archived.isEmpty {
                Rectangle().fill(Label.primary.opacity(0.15)).frame(width: 12, height: 1)
                ForEach(archived) { note in
                    RailDot(note: note, isOpen: note.id == openNoteID, faviconURL: faviconURL(note), onTap: { onSelect(note) }, onHover: onHover)
                        .opacity(0.5)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .contextMenu {
                            Button("Unarchive") { onArchive(note) }
                            Divider()
                            Button("Settings…", action: onSettings)
                        }
                }
            }
        }
        if overflowing {
            ScrollView(.vertical, showsIndicators: false) {
                column.padding(.vertical, 2)
            }
            .frame(height: RailMetrics.dotsHeight(noteCount: visibleDots, visibleDots: visibleDots))
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
                }
            )
        } else {
            column
        }
    }
}

struct RailDot: View {
    let note: Note
    let isOpen: Bool
    let faviconURL: URL?
    let onTap: () -> Void
    let onHover: (Note?, CGRect) -> Void
    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool { NoteKind.classify(note.content) == .empty }

    var body: some View {
        ZStack {
            // Open: a steady halo.
            Circle()
                .strokeBorder(note.tint.opacity(0.5), lineWidth: 1.5)
                .frame(width: RailMetrics.dot + 6, height: RailMetrics.dot + 6)
                .opacity(isOpen ? 1 : 0)
            // Pending: a ring breathes outward while the model writes, open or not.
            if note.isPending && !reduceMotion {
                PhaseAnimator([false, true]) { expanded in
                    Circle()
                        .strokeBorder(note.tint.opacity(expanded ? 0 : 0.9), lineWidth: 1.5)
                        .frame(width: RailMetrics.dot + 4, height: RailMetrics.dot + 4)
                        .scaleEffect(expanded ? 1.6 : 1)
                } animation: { _ in .easeOut(duration: 1.1) }
            }
            if let faviconURL, let icon = NSImage(contentsOf: faviconURL) {
                // A linked note wears its site's icon inside the note's color ring.
                Image(nsImage: icon).resizable().scaledToFill()
                    .frame(width: RailMetrics.dot - 2, height: RailMetrics.dot - 2)
                    .clipShape(Circle())
                    .padding(1)
                    .overlay(Circle().strokeBorder(note.tint, lineWidth: isOpen ? 0 : 1))
                    .scaleEffect(isPressed ? 0.88 : (isHovered ? 1.15 : 1))
            } else {
                // Empty notes are the same dot, dimmed: a ring reads as a form control.
                Circle()
                    .fill(note.tint.opacity(isEmpty ? 0.35 : 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5).blendMode(.plusLighter))
                    .frame(width: RailMetrics.dot, height: RailMetrics.dot)
                    .scaleEffect(isPressed ? 0.88 : (isHovered ? 1.15 : 1))
            }
        }

        .frame(width: RailMetrics.stripWidth, height: RailMetrics.dot)
        .contentShape(Rectangle().inset(by: -RailMetrics.dotGap / 2))
        .onTapGesture {
            onHover(nil, .zero)
            onTap()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(Motion.feedback) { isPressed = true } }
                .onEnded { _ in withAnimation(Motion.feedback) { isPressed = false } }
        )
        .background {
            GeometryReader { geo in
                Color.clear.onChange(of: isHovered) { _, hovering in
                    onHover(hovering && !isOpen ? note : nil, geo.frame(in: .global))
                }
            }
        }
        .onHover { hovering in
            withAnimation(Motion.feedback) { isHovered = hovering }
        }
        .onChange(of: isOpen) { _, open in
            if open { onHover(nil, .zero) }
        }
    }
}
