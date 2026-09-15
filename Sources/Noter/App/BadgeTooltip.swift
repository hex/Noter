// ABOUTME: A tiny floating panel that shows a badge's title to the left of the rail.
// ABOUTME: Replaces system tooltips, which AppKit suppresses while the app is inactive.

import AppKit
import NoterKit
import SwiftUI

@MainActor
final class BadgeTooltip {
    private var panel: NSPanel?
    private var showTask: DispatchWorkItem?
    private var hideTask: DispatchWorkItem?
    private var mouseInside = false
    private static let delay: TimeInterval = 0.35
    private static let gap: CGFloat = 8
    /// Called when the preview itself is clicked.
    var onOpen: ((Note) -> Void)?
    /// Resolves attachment names for the preview's favicon and image.
    var attachmentURL: ((String) -> URL)?

    /// Schedules the tooltip beside `anchor` (screen coordinates); a nil note asks it to go away,
    /// which it does unless the mouse has moved onto it.
    func update(note: Note?, anchor: NSRect, side: RailSide = .right) {
        showTask?.cancel()
        hideTask?.cancel()
        guard let note else {
            let task = DispatchWorkItem { [weak self] in
                guard let self, !self.mouseInside else { return }
                self.hide()
            }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
            return
        }
        let task = DispatchWorkItem { [weak self] in self?.show(note, beside: anchor, side: side) }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: task)
    }

    /// Hides at once; used when a note opens.
    func dismiss() {
        showTask?.cancel()
        hideTask?.cancel()
        mouseInside = false
        hide()
    }

    private func show(_ note: Note, beside anchor: NSRect, side: RailSide) {
        let view = BadgeTooltipView(
            note: note,
            faviconURL: note.preview?.faviconName.flatMap { attachmentURL?($0) },
            onHover: { [weak self] inside in
                self?.mouseInside = inside
                if !inside { self?.update(note: nil, anchor: .zero) }
            },
            onOpen: { [weak self] in self?.onOpen?(note) },
            side: side
        )
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let panel = self.panel ?? makePanel()
        panel.contentView = host
        // The window must end before the dot, or its hover steals the dot's and the two fight.
        let x = side == .right ? anchor.minX - size.width - Self.gap : anchor.maxX + Self.gap
        let target = NSRect(
            x: x,
            y: anchor.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        // Start tucked toward the badge and transparent, then slide out and fade in.
        panel.alphaValue = 0
        panel.setFrame(target.offsetBy(dx: side == .right ? Self.slide : -Self.slide, dy: 0), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
        self.panel = panel
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private static let slide: CGFloat = 10

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        return panel
    }
}

/// A peek, not a second card: title, age, and two lines of the body. No tail.
struct BadgeTooltipView: View {
    let note: Note
    var faviconURL: URL? = nil
    var onHover: (Bool) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var side: RailSide = .right
    static let margin: CGFloat = 24

    private var bodyPreview: String {
        let excerpt = note.excerpt(lines: 2)
        if excerpt.isEmpty, let description = note.preview?.description { return description }
        return excerpt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let faviconURL, let icon = ImageCache.shared.image(at: faviconURL) {
                    Image(nsImage: icon).resizable().scaledToFill().frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous)).offset(y: 1)
                } else {
                    Circle().fill(note.tint).frame(width: 7, height: 7).offset(y: -1)
                }
                Text(note.isPending && note.title.isEmpty ? "Reading…" : (note.title.isEmpty ? "New note" : note.title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Label.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Age.short(note.modifiedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(Label.tertiary)
            }
            let bodyPreview = bodyPreview
            if !bodyPreview.isEmpty {
                Text(bodyPreview).font(.system(size: 11.5)).lineSpacing(2).foregroundStyle(Label.secondary).lineLimit(2)
            } else if !note.isPending {
                Text("Empty").font(.system(size: 11)).foregroundStyle(Label.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 240, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glass(radius: 9, lift: 0.7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover(perform: onHover)
        .cursor(.pointingHand)
        .padding(side == .right ? .leading : .trailing, Self.margin)
        .padding(.vertical, Self.margin)
        .padding(side == .right ? .trailing : .leading, 2)
    }
}
