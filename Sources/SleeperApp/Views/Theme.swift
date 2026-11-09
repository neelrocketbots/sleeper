import SleeperCore
import SwiftUI

enum Theme {
    static let ink = Color.white
    static let soft = Color.white.opacity(0.66)
    static let faint = Color.white.opacity(0.4)
    static let accent = Color(red: 1, green: 0.56, blue: 0.69)      // axolotl pink
    static let alert = Color(red: 1, green: 0.36, blue: 0.36)
    static let good = Color(red: 0.36, green: 0.9, blue: 0.75)
    static let gold = Color(red: 1, green: 0.79, blue: 0.24)
    static let deep = Color(red: 0.02, green: 0.06, blue: 0.1)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .rounded) }

    /// The player colour, lifted when it's too dark to read as text on the dark UI.
    static func text(_ c: PlayerColor) -> Color {
        let r = Double((c.hex >> 16) & 0xFF) / 255, g = Double((c.hex >> 8) & 0xFF) / 255, b = Double(c.hex & 0xFF) / 255
        let l = 0.299 * r + 0.587 * g + 0.114 * b
        let k = l < 0.45 ? 0.45 : 0
        return Color(red: r + (1 - r) * k, green: g + (1 - g) * k, blue: b + (1 - b) * k)
    }

    static func color(_ c: PlayerColor) -> Color {
        Color(red: Double((c.hex >> 16) & 0xFF) / 255, green: Double((c.hex >> 8) & 0xFF) / 255, blue: Double(c.hex & 0xFF) / 255)
    }
}

/// A dark translucent panel with a hairline rim. Flat on purpose: it reads over bright pixel art and renders the
/// same everywhere (including the offscreen snapshot tool).
struct Panel: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(red: 0.02, green: 0.05, blue: 0.09).opacity(0.78)))
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill((tint ?? .clear).opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

extension View {
    func panel(tint: Color? = nil, radius: CGFloat = 14) -> some View { modifier(Panel(tint: tint, radius: radius)) }
}

/// A key cap: "E", "Space", "←".
struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.28), lineWidth: 1))
    }
}

struct Hint: View {
    let key: String, text: String
    var body: some View {
        HStack(spacing: 5) { KeyCap(key); Text(text).font(Theme.body(11.5)).foregroundStyle(Theme.soft) }
    }
}

/// The axolotl as a hard-pixel image.
struct Portrait: View {
    let color: PlayerColor
    let hat: Hat
    var scale: CGFloat = 3
    var dead = false
    var body: some View {
        Image(nsImage: CharacterArt.portrait(color, hat, scale: 1, dead: dead))
            .interpolation(.none)
            .resizable()
            .frame(width: 16 * scale, height: 18 * scale)
    }
}
