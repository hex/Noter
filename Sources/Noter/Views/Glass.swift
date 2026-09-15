// ABOUTME: The frosted surface every Noter panel is made of: material, hairline, two-layer shadow.
// ABOUTME: Applied to the rail strip, the note card, and the hover preview.

import SwiftUI
import NoterKit

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var lift: CGFloat = 1
    /// How much the wallpaper is hidden: 1 is the near-opaque card, 0 is bare glass for the rail.
    var opacity: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if opacity > 0.5 {
                        shape.fill(.thickMaterial)
                    } else {
                        shape.fill(.ultraThinMaterial)
                    }
                    // A wash on top: the wallpaper only ghosts through the card, so text keeps its contrast.
                    shape.fill(colorScheme == .light ? Color.white.opacity(0.32 * opacity) : Color.black.opacity(0.28 * opacity))
                }
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.5), lineWidth: 0.5).blendMode(.plusLighter)
            }
            .overlay {
                shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.14 * lift), radius: 14 * lift, y: 8 * lift)
    }
}

extension View {
    func glass(radius: CGFloat, lift: CGFloat = 1, opacity: CGFloat = 1) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), lift: lift, opacity: opacity))
    }

    func glass<S: InsettableShape>(shape: S, lift: CGFloat = 1, opacity: CGFloat = 1) -> some View {
        modifier(GlassSurface(shape: shape, lift: lift, opacity: opacity))
    }
}


/// Label colors as plain colors so they are not vibrancy-blended into the material.
enum Label {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .labelColor).opacity(0.68)
    static let tertiary = Color(nsColor: .labelColor).opacity(0.48)
    static let muted = Color(nsColor: .labelColor).opacity(0.3)
}

extension Note {
    var tint: Color { (PastelColor(rawValue: colorName) ?? .lavender).background.asSwiftUIColor }
}

/// One timing scale for the whole app. Enter decelerates, exit accelerates, feedback is quick.
enum Motion {
    static let feedback = Animation.easeOut(duration: 0.12)
    static let small = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    static let enter = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)
    static let exit = Animation.timingCurve(0.55, 0, 1, 0.45, duration: 0.16)
    static let settle = Animation.spring(duration: 0.35, bounce: 0.15)
}

/// A press that gives a little: 4% smaller while the mouse is down.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.feedback, value: configuration.isPressed)
    }
}

extension Note {
    /// Imported from the phone and still waiting for its title, summary and tags.
    var isPending: Bool { tags == [Inbox.pendingTag] }
}

/// Non-activating panels do not refresh cursor rects, so views set the pointer themselves.
struct CursorOnHover: ViewModifier {
    let cursor: NSCursor
    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View { modifier(CursorOnHover(cursor: cursor)) }
}
