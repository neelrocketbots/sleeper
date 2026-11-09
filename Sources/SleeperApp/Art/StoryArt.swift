import AppKit
import SleeperCore
import SpriteKit

/// The storybook art: loads the painted sprites bundled in Assets, recolours the crew per player, and makes the small
/// code-drawn pieces (shadows, markers, bubbles, fish). World units: 16 per tile.
@MainActor enum StoryArt {
    static let unit: Double = 16
    /// The crew's height on screen, in world units.
    static let crewHeight: Double = 24

    enum Pose: String, CaseIterable { case idle = "crew-idle", walk1 = "crew-walk1", walk2 = "crew-walk2", body = "crew-body" }

    static func image(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Assets") else { return nil }
        return Bitmap.load(url)
    }

    private static var bitmaps: [String: Bitmap] = [:]
    private static func bitmap(_ name: String) -> Bitmap {
        if let b = bitmaps[name] { return b }
        let b = image(name).map(Bitmap.init) ?? Bitmap(w: 1, h: 1)
        bitmaps[name] = b
        return b
    }

    private static var textures: [String: SKTexture] = [:]
    static func texture(_ key: String, _ make: () -> CGImage?) -> SKTexture {
        if let t = textures[key] { return t }
        let t = make().map { SKTexture(cgImage: $0) } ?? SKTexture()
        t.filteringMode = .linear
        textures[key] = t
        return t
    }

    // MARK: Crew

    static func crew(_ pose: Pose, _ color: PlayerColor) -> SKTexture {
        texture("\(pose.rawValue)-\(color.rawValue)") { bitmap(pose.rawValue).tinted(color, dim: pose == .body ? 0.35 : 0) }
    }

    /// Size of a pose in world units (the crew are `crewHeight` tall; bodies a little shorter).
    static func size(_ pose: Pose) -> CGSize {
        let b = bitmap(pose.rawValue)
        let h = pose == .body ? crewHeight * 0.85 : crewHeight
        return CGSize(width: h * Double(b.w) / Double(max(1, b.h)), height: h)
    }

    static func hat(_ hat: Hat) -> SKTexture? {
        guard hat != .none else { return nil }
        return texture("hat-\(hat)") { image("hat-\(hat)") }
    }

    /// Where a hat sits on a pose, in world units from the sprite's bottom centre, and the hat's size.
    static func hatPlacement(_ hat: Hat, on pose: Pose) -> (center: CGPoint, size: CGSize)? {
        guard hat != .none, let img = image("hat-\(hat)") else { return nil }
        let b = bitmap(pose.rawValue)
        let top = b.headTop()
        let s = size(pose)
        let k = s.height / Double(b.h)
        let width = s.width * 0.5
        let height = width * Double(img.height) / Double(img.width)
        // The hat's lower third overlaps the top of the head.
        let x = (top.x - Double(b.w) / 2) * k
        let y = s.height - Double(top.y) * k + height * 0.3
        return (CGPoint(x: x, y: y), CGSize(width: width, height: height))
    }

    /// For SwiftUI: the axolotl with its hat.
    static func portrait(_ color: PlayerColor, _ hat: Hat, dead: Bool = false) -> NSImage {
        let key = "\(color.rawValue)-\(hat.rawValue)-\(dead)"
        if let p = portraits[key] { return p }
        let pose: Pose = .idle
        let b = bitmap(pose.rawValue)
        let s = size(pose)
        let scale = Double(b.h) / s.height
        let extra = 0.45 * s.height * scale
        let w = Double(b.w), h = Double(b.h) + extra
        let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(b.tinted(color, dim: dead ? 0.6 : 0), in: CGRect(x: 0, y: 0, width: w, height: Double(b.h)))
        if let hp = hatPlacement(hat, on: pose), let hi = image("hat-\(hat)") {
            let r = CGRect(x: w / 2 + hp.center.x * scale - hp.size.width * scale / 2, y: hp.center.y * scale - hp.size.height * scale / 2,
                           width: hp.size.width * scale, height: hp.size.height * scale)
            ctx.draw(hi, in: r)
        }
        let img = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w / 4, height: h / 4))
        portraits[key] = img
        return img
    }
    private static var portraits: [String: NSImage] = [:]

    // MARK: Props

    static func prop(_ kind: PropKind) -> SKTexture {
        let name = kind == .table && image("prop-table2") != nil ? "prop-table2" : "prop-\(kind.rawValue)"
        return texture(name) { image(name) }
    }

    /// Flat props lie on the floor; the rest stand up from their footprint.
    static func isFlat(_ kind: PropKind) -> Bool { kind == .ventGrate || kind == .airlock }

    // MARK: Small pieces drawn in code

    static func draw(_ size: CGSize, scale: CGFloat = 4, _ body: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        body(ctx)
        return ctx.makeImage()!
    }

    static let ink = CGColor(srgbRed: 0.11, green: 0.09, blue: 0.17, alpha: 1)

    static var shadow: SKTexture {
        texture("shadow") {
            draw(CGSize(width: 32, height: 12)) { c in
                let g = CGGradient(colorsSpace: nil, colors: [CGColor(srgbRed: 0, green: 0.02, blue: 0.06, alpha: 0.45),
                                                             CGColor(srgbRed: 0, green: 0.02, blue: 0.06, alpha: 0)] as CFArray, locations: [0, 1])!
                c.saveGState(); c.translateBy(x: 16, y: 6); c.scaleBy(x: 1, y: 6.0 / 16)
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 16, options: [])
                c.restoreGState()
            }
        }
    }

    /// A task marker: an inked yellow tag with "!".
    static var marker: SKTexture {
        texture("marker") {
            draw(CGSize(width: 12, height: 16)) { c in
                let tag = CGPath(roundedRect: CGRect(x: 1, y: 4, width: 10, height: 11), cornerWidth: 4, cornerHeight: 4, transform: nil)
                c.setFillColor(CGColor(srgbRed: 1, green: 0.84, blue: 0.35, alpha: 1)); c.addPath(tag); c.fillPath()
                c.setStrokeColor(ink); c.setLineWidth(1); c.addPath(tag); c.strokePath()
                c.move(to: CGPoint(x: 5, y: 4)); c.addLine(to: CGPoint(x: 6, y: 1)); c.addLine(to: CGPoint(x: 7, y: 4))
                c.setFillColor(CGColor(srgbRed: 1, green: 0.84, blue: 0.35, alpha: 1)); c.fillPath()
                c.setFillColor(ink)
                c.fill(CGRect(x: 5.3, y: 8.6, width: 1.4, height: 4.6))
                c.fillEllipse(in: CGRect(x: 5.25, y: 6, width: 1.5, height: 1.5))
            }
        }
    }

    static var bubble: SKTexture {
        texture("bubble") {
            draw(CGSize(width: 6, height: 6)) { c in
                c.setStrokeColor(CGColor(srgbRed: 0.8, green: 0.95, blue: 1, alpha: 0.8)); c.setLineWidth(0.7)
                c.strokeEllipse(in: CGRect(x: 0.7, y: 0.7, width: 4.6, height: 4.6))
                c.setFillColor(CGColor(gray: 1, alpha: 0.7)); c.fillEllipse(in: CGRect(x: 3.2, y: 3.4, width: 1.2, height: 1.2))
            }
        }
    }

    /// A small inked fish, facing right.
    static func fish(_ variant: Int) -> SKTexture {
        let colors: [CGColor] = [CGColor(srgbRed: 0.98, green: 0.62, blue: 0.3, alpha: 1), CGColor(srgbRed: 0.5, green: 0.8, blue: 0.85, alpha: 1),
                                 CGColor(srgbRed: 0.9, green: 0.85, blue: 0.5, alpha: 1)]
        return texture("fish-\(variant)") {
            draw(CGSize(width: 18, height: 10)) { c in
                let body = CGMutablePath()
                body.move(to: CGPoint(x: 16, y: 5))
                body.addQuadCurve(to: CGPoint(x: 5, y: 5), control: CGPoint(x: 11, y: 10))
                body.addQuadCurve(to: CGPoint(x: 16, y: 5), control: CGPoint(x: 11, y: 0))
                let tail = CGMutablePath()
                tail.move(to: CGPoint(x: 6, y: 5)); tail.addLine(to: CGPoint(x: 1, y: 8.5)); tail.addLine(to: CGPoint(x: 1.5, y: 1.5)); tail.closeSubpath()
                c.setFillColor(colors[variant % colors.count]); c.addPath(body); c.addPath(tail); c.fillPath()
                c.setStrokeColor(ink); c.setLineWidth(0.8); c.addPath(body); c.addPath(tail); c.strokePath()
                c.setFillColor(ink); c.fillEllipse(in: CGRect(x: 12.6, y: 5.4, width: 1.3, height: 1.3))
            }
        }
    }
}
