// ABOUTME: The open note: a glass card with a whisper of the note color, SF Pro text, hover-only controls.
// ABOUTME: Header, tags, source byline, thumbnails, then the summary as body; hover reveals close, pin, color, archive.

import SwiftUI

struct NoteCard: View {
    let note: Note
    let attachmentURLs: [URL]
    /// Resolves an attachment name to its file; used for the preview image.
    let attachmentURL: (String) -> URL
    @Binding var content: String
    var editorFocused: FocusState<Bool>.Binding
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleArchive: () -> Void
    let onPickColor: (String) -> Void
    var onRerun: () -> Void = {}
    /// Move to the neighbouring note: -1 up, +1 down.
    var onStep: (Int) -> Void = { _ in }
    var onNew: () -> Void = {}
    @State private var isHovered = false
    @State private var showingColors = false

    private var previewImageURL: URL? { note.preview?.imageName.map(attachmentURL) }
    private var previewFaviconURL: URL? { note.preview?.faviconName.map(attachmentURL) }
    /// The palette's dark ink for that color, so tags read on a full-strength tint.
    private var tagInk: Color { (PastelColor(rawValue: note.colorName) ?? .lavender).foreground.asSwiftUIColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !note.tags.isEmpty {
                tagRow.padding(.top, 10)
            }
            if let preview = note.preview {
                Byline(preview: preview, imageURL: previewImageURL, faviconURL: previewFaviconURL)
                    .padding(.top, 12)
            }
            if !attachmentURLs.isEmpty {
                AttachmentStrip(urls: attachmentURLs).padding(.top, 12)
            }
            editor.padding(.top, 14)
            footer.padding(.top, 12)
        }
        .padding(16)
        .frame(width: RailMetrics.cardWidth)
        .frame(minHeight: RailMetrics.cardMinHeight, maxHeight: RailMetrics.cardMaxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            LinearGradient(colors: [note.tint.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: RailMetrics.cardRadius, style: .continuous))
        }
        .glass(radius: RailMetrics.cardRadius)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch (press.key, press.modifiers.contains(.shift)) {
            case (.upArrow, _): onStep(-1)
            case (.downArrow, _): onStep(1)
            case (KeyEquivalent("n"), false): onNew()
            case (KeyEquivalent("o"), false):
                if let url = note.preview?.url { NSWorkspace.shared.open(url) }
            case (KeyEquivalent("p"), true): onTogglePin()
            case (.delete, _): onToggleArchive()
            default: return .ignored
            }
            return .handled
        }
    }

    /// Title on up to two lines with the short age on its first baseline. The rail carries the color;
    /// Esc, clicking away, or clicking the dot closes, so there is no close mark.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(note.isPending && note.title.isEmpty ? "Reading…" : (note.title.isEmpty ? "New note" : note.title))
                .font(.system(size: 15, weight: note.title.isEmpty ? .medium : .semibold))
                .foregroundStyle(note.title.isEmpty ? Label.tertiary : Label.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            Text(Age.short(note.modifiedAt))
                .font(.system(size: 11))
                .foregroundStyle(Label.tertiary)
                .lineLimit(1)
        }
    }

    private var tagRow: some View {
        TagRow(tags: note.tags, tint: note.tint, ink: tagInk, size: 11)
    }

    /// The editor grows with its text: an invisible copy of the content sets the height,
    /// the editor sits on top. Beyond the card's maximum the editor scrolls.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            // Past the card's tallest, the editor scrolls, so measuring more lines than fit is waste.
            Text(content.isEmpty ? " " : content)
                .font(.system(size: 13))
                .lineSpacing(5)
                .lineLimit(Int(RailMetrics.cardMaxHeight / 18))
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
                .accessibilityHidden(true)
            if note.isPending && content.isEmpty {
                PendingLines()
            } else if content.isEmpty {
                Text("Start writing")
                    .font(.system(size: 13))
                    .foregroundStyle(Label.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $content)
                .font(.system(size: 13))
                .foregroundStyle(Label.primary)
                .tint(Label.primary)
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .focused(editorFocused)
        }
        .frame(minHeight: 60)
        .padding(.horizontal, -5)
        .cursor(.iBeam)
    }

    /// Icon and label, borderless until the mouse is over them. Archive lives on the dot's
    /// context menu and cmd-delete, not here, so the two visible actions are both reversible.
    private var footer: some View {
        HStack(spacing: 4) {
            control(note.isPinned ? "pin.fill" : "pin", note.isPinned ? "Pinned" : "Pin", active: note.isPinned, action: onTogglePin)
            Button { showingColors.toggle() } label: {
                HStack(spacing: 5) {
                    Circle().fill(note.tint).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5).blendMode(.plusLighter))
                    Text("Colour").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Label.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Capsule())
            }
            .buttonStyle(QuietPillStyle())
            .focusable(false)
            .popover(isPresented: $showingColors, arrowEdge: .bottom) {
                ColorSwatches(current: note.colorName) { name in
                    onPickColor(name)
                    showingColors = false
                }
            }
            Spacer(minLength: 0)
            control(note.isPending ? "sparkles" : "sparkles", note.isPending ? "Writing…" : "Rewrite", action: onRerun)
                .disabled(note.isPending)
                .help("Ask the model for a new title, summary and tags from the current text")
        }
        .padding(.top, 6)
    }

    private func control(_ symbol: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(active ? note.tint : Label.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(QuietPillStyle())
        .focusable(false)
    }
}

/// A pill that is invisible at rest and fills on hover or press, the macOS toolbar way.
struct QuietPillStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(Label.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.07 : 0))))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.feedback, value: configuration.isPressed)
            .animation(Motion.feedback, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// The eight note colours as a 4x2 grid; the current one wears a ring.
struct ColorSwatches: View {
    let current: String
    let pick: (String) -> Void

    var body: some View {
        let colors = PastelColor.allCases
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(colors[row * 4..<min(row * 4 + 4, colors.count)], id: \.self) { color in
                        Button { pick(color.rawValue) } label: {
                            Circle().fill(color.background.asSwiftUIColor)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Label.primary.opacity(color.rawValue == current ? 0.6 : 0), lineWidth: 2))
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle())
                        .focusable(false)
                        .help(color.rawValue.capitalized)
                    }
                }
            }
        }
        .padding(12)
    }
}

/// Three soft bars where the summary will land, breathing while the model writes it.
struct PendingLines: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([0.9, 0.75, 0.6], id: \.self) { width in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Label.primary.opacity(on ? 0.06 : 0.11))
                    .frame(width: 250 * width, height: 9)
            }
        }
        .padding(.top, 5)
        .padding(.leading, 5)
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

/// Small previews of a note's files. Images show themselves; other files show their Finder icon.
/// Clicking opens the file in its default app.
struct AttachmentStrip: View {
    let urls: [URL]
    private let side: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(urls, id: \.self) { url in
                    Button { NSWorkspace.shared.open(url) } label: {
                        thumbnail(url)
                            .frame(width: side, height: side)
                            .background(Label.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5).blendMode(.plusLighter))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(url.lastPathComponent)
                }
            }
        }
        .frame(height: side)
    }

    @ViewBuilder
    private func thumbnail(_ url: URL) -> some View {
        if let image = ImageCache.shared.image(at: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(12)
        }
    }
}

/// The source as one attribution row: 16pt site icon, "site · author or page title", open arrow;
/// beneath it up to two lines of what the link carried, on a lighter panel.
struct Byline: View {
    let preview: LinkPreview
    let imageURL: URL?
    var faviconURL: URL? = nil
    var body: some View {
        Button { NSWorkspace.shared.open(preview.url) } label: {
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let faviconURL, let icon = ImageCache.shared.image(at: faviconURL) {
                        Image(nsImage: icon).resizable().scaledToFill()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Text([preview.siteName ?? preview.url.host(), preview.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Label.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Label.tertiary)
                }
                .frame(height: 20)
                if let text = preview.description, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(Label.secondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = preview.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Label.tertiary)
                        .lineLimit(1)
                }
            }
            if let imageURL, let image = ImageCache.shared.image(at: imageURL) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
          }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            // A lighter panel: this part is someone else's words.
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.85))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .focusable(false)
        .help(preview.url.absoluteString)
        .cursor(.pointingHand)
    }
}

/// Up to three quiet tag capsules and a "+N" for the rest; never scrolls, never clips a word.
struct TagRow: View {
    let tags: [String]
    let tint: Color
    let ink: Color
    var size: CGFloat = 11
    private let shown = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(shown), id: \.self) { tag in
                capsule(tag, fill: tint.opacity(0.16), ink: Label.secondary)
            }
            if tags.count > shown {
                capsule("+\(tags.count - shown)", fill: Label.primary.opacity(0.06), ink: Label.tertiary)
                    .help(tags.dropFirst(shown).joined(separator: ", "))
            }
        }
    }

    private func capsule(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size * 0.7)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}
