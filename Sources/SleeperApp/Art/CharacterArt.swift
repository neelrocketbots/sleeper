import SleeperCore
import SpriteKit

/// The axolotl and its hats, drawn from palette-indexed grids. One drawing, recoloured per player colour.
enum CharacterArt {
    static let size = 16
    /// Canvas height: two spare rows above the head for tall hats.
    static let canvasHeight = 18

    // o outline, b body, l light, d dark, g gill, G gill shade, e eye, k cheek, m mouth, v vest, V vest shade,
    // p buckle, t tail
    static let head: [String] = [
        "................",
        ".G.g........g.G.",
        "..gGg......gGg..",
        ".gg.goooooog.gg.",
        "..ggolllllbogg..",
        ".gGobllbbbbdoGg.",
        "...obebbbbebo...",
        "...okbbmmbbko...",
        "....obbbbbbo....",
        "...ovvvppvvvo...",
        "..obvvvVVvvvbo..",
        "..odvVvvvvVvdo..",
        "...ovvvvvvvvo...",
        "...obbbbbbbbo.tt",
    ]
    static let gillsAlt: [String] = [
        "................",
        "..G.g......g.G..",
        ".gGg........gGg.",
    ]
    static let legsStand = ["...obdo..obdo.t.", "...ooo....ooo..."]
    static let legsLeft = ["...ooo...obdo.t.", "..........ooo..."]
    static let legsRight = ["...obdo..ooo..t.", "...ooo.........."]

    enum Frame: Int, CaseIterable { case idle, idle2, walk1, walk2, walk3, walk4 }

    static func palette(_ color: PlayerColor, dim: Double = 0) -> [Character: RGB] {
        var base = RGB(hex: color.hex)
        if dim > 0 { base = base.desaturated(dim).darker(dim * 0.3) }
        let gill = base.lighter(0.12).mix(RGB(hex: 0xFF6F91), color == .rose || color == .coral ? 0.15 : 0.32)
        return [
            "o": base.shade(0.68), "b": base, "l": base.lighter(0.28), "d": base.shade(0.28),
            "g": gill, "G": gill.shade(0.32), "e": RGB(hex: 0x1B1026), "k": RGB(hex: 0xFF9AB0, alpha: 0.85),
            "m": base.shade(0.6), "v": RGB(hex: 0x3D4C57), "V": RGB(hex: 0x2A353D), "p": RGB(hex: 0xE8B547),
            "t": base.shade(0.2),
        ]
    }

    static func draw(_ c: PixelCanvas, color: PlayerColor, frame: Frame, at ox: Int, _ oy: Int, flip: Bool = false, dim: Double = 0) {
        let pal = palette(color, dim: dim)
        let bob = (frame == .walk2 || frame == .walk4) ? -1 : 0
        var rows = head
        if frame == .idle2 { rows.replaceSubrange(0..<3, with: gillsAlt) }
        c.sprite(rows, at: ox, oy + bob, palette: pal, flip: flip)
        let legs: [String]
        switch frame {
        case .walk2: legs = legsLeft
        case .walk4: legs = legsRight
        default: legs = legsStand
        }
        c.sprite(legs, at: ox, oy + 14, palette: pal, flip: flip)
    }

    // MARK: Hats

    static func hatRows(_ hat: Hat) -> (rows: [String], top: Int, palette: [Character: RGB])? {
        switch hat {
        case .none: return nil
        case .captain:
            return ([".....oooooo.....", "....owwwwwwo....", "....owwyywwo....", "...okkkkkkkko..."], 2,
                    ["o": RGB(hex: 0x1C2230), "w": RGB(hex: 0xF2F4F8), "y": RGB(hex: 0xE8B547), "k": RGB(hex: 0x1F2A44)])
        case .beanie:
            return ([".......pp.......", "......oRRo......", ".....orrrro.....", "....orrrrrro....", "....oRRRRRRo...."], 1,
                    ["o": RGB(hex: 0x3A1518), "r": RGB(hex: 0xE0574A), "R": RGB(hex: 0xB13C38), "p": RGB(hex: 0xFFE3D6)])
        case .headlamp:
            return (["......oyyo......", ".....oyWWyo.....", "....okkkkkko...."], 4,
                    ["o": RGB(hex: 0x12151C), "y": RGB(hex: 0xFFD27A), "W": RGB(hex: 0xFFFFFF), "k": RGB(hex: 0x2A2F3A)])
        case .seashell:
            return (["......ooo.......", ".....ospso......", "....ospspso.....", "....ossssso....."], 2,
                    ["o": RGB(hex: 0x8A3550), "s": RGB(hex: 0xFFB3C7), "p": RGB(hex: 0xFF7FA3)])
        case .crown:
            return ([".....y.yy.y.....", ".....yyyyyy.....", "....oyryyryo....", "....oyyyyyyo...."], 2,
                    ["o": RGB(hex: 0x6B4A12), "y": RGB(hex: 0xFFC93D), "r": RGB(hex: 0xFF4F7B)])
        }
    }

    static func drawHat(_ c: PixelCanvas, _ hat: Hat, at ox: Int, _ oy: Int, flip: Bool = false, bob: Int = 0) {
        guard let h = hatRows(hat) else { return }
        c.sprite(h.rows, at: ox, oy + h.top + bob, palette: h.palette, flip: flip)
    }

    // MARK: Textures (cached)

    @MainActor private static var cache: [String: SKTexture] = [:]

    /// The axolotl with its hat, 16 × 18. The sprite's feet are at the bottom row.
    @MainActor static func texture(_ color: PlayerColor, _ hat: Hat, _ frame: Frame, flip: Bool, ghost: Bool = false) -> SKTexture {
        let key = "\(color.rawValue)-\(hat.rawValue)-\(frame.rawValue)-\(flip)-\(ghost)"
        if let t = cache[key] { return t }
        let c = PixelCanvas(size, canvasHeight)
        draw(c, color: color, frame: frame, at: 0, 2, flip: flip)
        let bob = (frame == .walk2 || frame == .walk4) ? -1 : 0
        drawHat(c, hat, at: 0, 0, flip: flip, bob: bob)
        if ghost {
            for y in 0..<c.height { for x in 0..<c.width { let p = c[x, y]; if p.a > 0 { c[x, y] = p.lighter(0.25).alpha(p.a * 0.45) } } }
        }
        let t = c.texture()
        cache[key] = t
        return t
    }

    /// A body: the axolotl on its back, greyed out, eyes shut.
    @MainActor static func bodyTexture(_ color: PlayerColor) -> SKTexture {
        let key = "body-\(color.rawValue)"
        if let t = cache[key] { return t }
        let src = PixelCanvas(size, size)
        draw(src, color: color, frame: .idle, at: 0, 0, dim: 0.55)
        // Shut eyes.
        let lid = palette(color, dim: 0.55)["o"]!
        src[5, 6] = lid; src[10, 6] = lid
        // Rotate 90° so it lies on its back, head to the left.
        let c = PixelCanvas(size + 2, size)
        for y in 0..<size { for x in 0..<size { c[y + 1, size - 1 - x] = src[x, y] } }
        let t = c.texture()
        cache[key] = t
        return t
    }

    /// For SwiftUI: the axolotl scaled up with hard pixels.
    @MainActor static func portrait(_ color: PlayerColor, _ hat: Hat, scale: Int = 4, dead: Bool = false) -> NSImage {
        let c = PixelCanvas(size, canvasHeight)
        draw(c, color: color, frame: .idle, at: 0, 2, dim: dead ? 0.6 : 0)
        drawHat(c, hat, at: 0, 0)
        if dead { let lid = palette(color, dim: 0.6)["o"]!; c[5, 8] = lid; c[10, 8] = lid }
        return c.nsImage(scale: scale)
    }

    @MainActor static let shadow: SKTexture = {
        let c = PixelCanvas(12, 4)
        for y in 0..<4 { for x in 0..<12 {
            let dx = (Double(x) + 0.5 - 6) / 6, dy = (Double(y) + 0.5 - 2) / 2
            if dx * dx + dy * dy <= 1 { c[x, y] = RGB(0, 0.02, 0.06, 0.38) }
        } }
        return c.texture()
    }()

    @MainActor static let marker: SKTexture = {
        let c = PixelCanvas(5, 9)
        let o = RGB(hex: 0x2A1A00), y = RGB(hex: 0xFFD54A), w = RGB(hex: 0xFFF3B0)
        c.sprite([".ooo.", "oyyyo", "owyyo", "oyyyo", ".oyo.", ".oyo.", ".ooo.", ".oyo.", ".ooo."], at: 0, 0,
                 palette: ["o": o, "y": y, "w": w])
        return c.texture()
    }()

    /// A soft round glow for lights (linear filtering on purpose).
    @MainActor static let glow: SKTexture = {
        let n = 64
        let c = PixelCanvas(n, n)
        for y in 0..<n { for x in 0..<n {
            let dx = (Double(x) + 0.5 - Double(n) / 2) / (Double(n) / 2), dy = (Double(y) + 0.5 - Double(n) / 2) / (Double(n) / 2)
            let d = min(1, (dx * dx + dy * dy).squareRoot())
            let a = pow(1 - d, 2.2)
            c[x, y] = RGB(1, 1, 1, a)
        } }
        let t = SKTexture(cgImage: c.image())
        t.filteringMode = .linear
        return t
    }()

    @MainActor static let bubble: SKTexture = {
        let c = PixelCanvas(3, 3)
        c.sprite([".w.", "w.w", ".w."], at: 0, 0, palette: ["w": RGB(0.75, 0.92, 1, 0.8)])
        return c.texture()
    }()
}
