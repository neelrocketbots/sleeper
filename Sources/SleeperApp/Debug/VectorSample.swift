import AppKit
import SleeperCore

/// `Sleeper --vector-sample <dir>`: the Mess Hall and the axolotl drawn as flat vector art, for comparing styles.
@MainActor enum VectorSample {
    // Points per tile at game zoom (the pixel version is 16 px × 3).
    static let T: CGFloat = 48

    static func write(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try save(scene(), dir.appendingPathComponent("vector-scene.png"))
        try save(lineup(), dir.appendingPathComponent("vector-crew.png"))
    }

    // MARK: Scene

    static func scene() -> CGImage {
        let map = GameMap.abyss
        let view = CGSize(width: 764, height: 500)
        let scale: CGFloat = 2
        let ctx = context(view, scale)
        // Camera on the Mess Hall, a little up and left of the table.
        let cam = CGPoint(x: 22.5 * T, y: 15.5 * T)
        ctx.translateBy(x: view.width / 2 - cam.x, y: view.height / 2 - cam.y)

        let x0 = Int((cam.x - view.width / 2) / T) - 1, x1 = Int((cam.x + view.width / 2) / T) + 1
        let y0 = Int((cam.y - view.height / 2) / T) - 2, y1 = Int((cam.y + view.height / 2) / T) + 2
        func open(_ x: Int, _ y: Int) -> Bool { let t = map[TilePos(x, y)]; return t == .floor || t == .prop }
        func wall(_ x: Int, _ y: Int) -> Bool { map[TilePos(x, y)] == .wall }

        // Floor.
        ctx.setFillColor(hex(0x06121D)); ctx.fill(CGRect(x: CGFloat(x0) * T, y: CGFloat(y0) * T, width: CGFloat(x1 - x0) * T, height: CGFloat(y1 - y0) * T))
        for y in y0...y1 { for x in x0...x1 where open(x, y) {
            let r = CGRect(x: CGFloat(x) * T, y: CGFloat(y) * T, width: T, height: T)
            let theme = map.room(at: TilePos(x, y))?.theme ?? .corridor
            let base: UInt32 = theme == .corridor ? 0x223040 : ((x + y) % 2 == 0 ? 0x2E3E50 : 0x2B3A4B)
            ctx.setFillColor(hex(base)); ctx.fill(r)
            ctx.setFillColor(hex(0x243242)); ctx.fill(CGRect(x: r.minX, y: r.maxY - 2, width: T, height: 2))
            ctx.fill(CGRect(x: r.maxX - 2, y: r.minY, width: 2, height: T))
            if theme == .corridor { for i in 0..<4 { ctx.fill(CGRect(x: r.minX + CGFloat(i) * 12 + 5, y: r.minY + 4, width: 2, height: T - 8)) } }
            // Contact shadow under north walls.
            if wall(x, y - 1) {
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.35)); ctx.fill(CGRect(x: r.minX, y: r.minY, width: T, height: 14))
            }
        } }
        // Prop shadows.
        for p in map.props {
            let r = rect(p.rect)
            ctx.setFillColor(CGColor(red: 0, green: 0.02, blue: 0.05, alpha: 0.4))
            ctx.addPath(CGPath(roundedRect: r.offsetBy(dx: 8, dy: 10), cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
        }

        // Raised things, back to front, with the characters.
        let crew: [(PlayerColor, Hat, CGPoint, Bool)] = [
            (.coral, .captain, CGPoint(x: 21.3, y: 15.6), true), (.lime, .none, CGPoint(x: 19.4, y: 17.8), false),
            (.violet, .crown, CGPoint(x: 24.5, y: 14.6), true), (.gold, .beanie, CGPoint(x: 22.6, y: 20.4), false),
        ]
        for y in y0...y1 {
            for x in x0...x1 where wall(x, y) { drawWall(ctx, x, y, open: open, wall: wall) }
            for p in map.props where p.rect.y1 == y { drawProp(ctx, p) }
            for c in crew where Int(c.2.y) == y {
                axolotl(ctx, feet: CGPoint(x: c.2.x * T, y: c.2.y * T), unit: 3, color: c.0, hat: c.1, facingRight: c.3)
            }
        }
        // A body on the floor.
        body(ctx, at: CGPoint(x: 26.5 * T, y: 13.9 * T), unit: 3, color: .cyan)
        return ctx.makeImage()!
    }

    static func rect(_ r: TileRect) -> CGRect {
        CGRect(x: CGFloat(r.x0) * T, y: CGFloat(r.y0) * T, width: CGFloat(r.width) * T, height: CGFloat(r.height) * T)
    }

    static func drawWall(_ ctx: CGContext, _ x: Int, _ y: Int, open: (Int, Int) -> Bool, wall: (Int, Int) -> Bool) {
        let south = open(x, y - 1)  // a south wall: low ledge
        let h: CGFloat = south ? 18 : 66
        let foot = CGRect(x: CGFloat(x) * T, y: CGFloat(y) * T, width: T, height: T)
        let cap = foot.offsetBy(dx: 0, dy: -h)
        let showFace = !wall(x, y + 1)
        if showFace {
            let face = CGRect(x: foot.minX, y: cap.maxY, width: T, height: foot.maxY - cap.maxY)
            ctx.setFillColor(hex(south ? 0x172430 : 0x203043)); ctx.fill(face)
            if !south {
                ctx.setFillColor(hex(0x3A5268)); ctx.fill(CGRect(x: face.minX, y: face.minY, width: T, height: 4))
                ctx.setFillColor(hex(0x2C4255)); ctx.fill(CGRect(x: face.minX, y: face.minY + 14, width: T, height: 8))  // pipe
                ctx.setFillColor(hex(0x16212C)); ctx.fill(CGRect(x: face.minX, y: face.maxY - 8, width: T, height: 8))  // baseboard
                let k = (x * 7 + y * 3) % 5
                if k == 0 || k == 2 {
                    let c = CGPoint(x: face.midX, y: face.minY + 40)
                    ctx.setFillColor(hex(0x8FA6B6)); ctx.fillEllipse(in: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30))
                    ctx.setFillColor(hex(0x0F3D60)); ctx.fillEllipse(in: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22))
                    ctx.setFillColor(hex(0x1D6A99)); ctx.fillEllipse(in: CGRect(x: c.x - 6, y: c.y - 2, width: 15, height: 12))
                    ctx.setFillColor(CGColor(gray: 1, alpha: 0.8)); ctx.fillEllipse(in: CGRect(x: c.x - 7, y: c.y - 8, width: 5, height: 5))
                } else if k == 4 {
                    ctx.setFillColor(hex(0xFFD58A))
                    ctx.addPath(CGPath(roundedRect: CGRect(x: face.midX - 10, y: face.minY + 30, width: 20, height: 6), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
                }
            }
        }
        ctx.setFillColor(hex(0x2A3D51)); ctx.fill(cap)
        ctx.setFillColor(hex(0x4A6A88))
        if open(x, y - 1) || south { ctx.fill(CGRect(x: cap.minX, y: cap.minY, width: T, height: 4)) }
        if open(x - 1, y) { ctx.fill(CGRect(x: cap.minX, y: cap.minY, width: 4, height: T)) }
        if open(x + 1, y) { ctx.setFillColor(hex(0x1C2A38)); ctx.fill(CGRect(x: cap.maxX - 4, y: cap.minY, width: 4, height: T)) }
    }

    static func drawProp(_ ctx: CGContext, _ p: Prop) {
        let r = rect(p.rect)
        switch p.kind {
        case .table:
            let lift: CGFloat = 24
            let top = r.insetBy(dx: 6, dy: 6).offsetBy(dx: 0, dy: -lift)
            ctx.setFillColor(hex(0x26323F))
            ctx.fill(CGRect(x: top.minX, y: top.maxY - 10, width: top.width, height: lift + 10))
            ctx.setFillColor(hex(0x1A232D)); ctx.fill(CGRect(x: top.minX + 14, y: top.maxY + 4, width: top.width - 28, height: lift - 8))
            ctx.setFillColor(hex(0x4C5E72))
            ctx.addPath(CGPath(roundedRect: top, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.fillPath()
            ctx.setFillColor(hex(0x5A6E84))
            ctx.addPath(CGPath(roundedRect: top.insetBy(dx: 10, dy: 10), cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
            for i in 0..<5 {
                ctx.setFillColor(hex(0xE3B062))
                ctx.fillEllipse(in: CGRect(x: top.minX + 30 + CGFloat(i) * 52, y: top.maxY - 34, width: 14, height: 9))
            }
            let c = CGPoint(x: top.midX, y: top.midY - 6)
            ctx.setFillColor(hex(0x1A222C)); ctx.fillEllipse(in: CGRect(x: c.x - 20, y: c.y - 14, width: 40, height: 30))
            ctx.setFillColor(hex(0xB8333E)); ctx.fillEllipse(in: CGRect(x: c.x - 14, y: c.y - 8, width: 28, height: 20))
            ctx.setFillColor(hex(0xEF4E5A)); ctx.fillEllipse(in: CGRect(x: c.x - 14, y: c.y - 13, width: 28, height: 20))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.6)); ctx.fillEllipse(in: CGRect(x: c.x - 8, y: c.y - 10, width: 8, height: 5))
        case .filter:
            let lift: CGFloat = 40
            let top = r.insetBy(dx: 4, dy: 4).offsetBy(dx: 0, dy: -lift)
            ctx.setFillColor(hex(0x1E2933)); ctx.fill(CGRect(x: top.minX, y: top.midY, width: top.width, height: top.height / 2 + lift))
            ctx.setFillColor(hex(0x34424F)); ctx.fill(top)
            for i in 0..<2 {
                let c = CGPoint(x: top.minX + 24 + CGFloat(i) * 48, y: top.midY)
                ctx.setFillColor(hex(0x1A232C)); ctx.fillEllipse(in: CGRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28))
                ctx.setFillColor(hex(0x6E8296)); ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            }
            for i in 0..<5 { ctx.setFillColor(hex(0x2A3743)); ctx.fill(CGRect(x: top.minX + 8 + CGFloat(i) * 16, y: top.maxY + 8, width: 8, height: lift - 14)) }
        default: break
        }
    }

    // MARK: Axolotl

    /// Flat axolotl: one design, recoloured. `unit` = points per pixel of the 16-unit-tall character.
    static func axolotl(_ ctx: CGContext, feet: CGPoint, unit u: CGFloat, color: PlayerColor, hat: Hat, facingRight: Bool) {
        let base = rgb(color.hex)
        let dark = mix(base, (0.1, 0.06, 0.2), 0.35)
        let light = mix(base, (1, 1, 1), 0.25)
        let gill = mix(mix(base, (1, 0.44, 0.57), 0.35), (1, 1, 1), 0.1)
        ctx.saveGState()
        ctx.translateBy(x: feet.x, y: feet.y)
        if !facingRight { ctx.scaleBy(x: -1, y: 1) }
        ctx.scaleBy(x: u, y: u)
        // Shadow.
        ctx.setFillColor(CGColor(red: 0, green: 0.02, blue: 0.06, alpha: 0.35)); ctx.fillEllipse(in: CGRect(x: -6, y: -1.5, width: 12, height: 3))
        // Tail.
        let tail = CGMutablePath(); tail.move(to: CGPoint(x: 3, y: -4)); tail.addQuadCurve(to: CGPoint(x: 8.5, y: -5.5), control: CGPoint(x: 7, y: -2))
        tail.addQuadCurve(to: CGPoint(x: 3, y: -6.5), control: CGPoint(x: 6, y: -6.5)); tail.closeSubpath()
        ctx.setFillColor(cg(dark)); ctx.addPath(tail); ctx.fillPath()
        // Legs.
        ctx.setFillColor(cg(dark))
        ctx.addPath(CGPath(roundedRect: CGRect(x: -4, y: -3, width: 3, height: 3), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 1, y: -3, width: 3, height: 3), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)); ctx.fillPath()
        // Body and vest.
        ctx.setFillColor(cg(base)); ctx.addPath(CGPath(roundedRect: CGRect(x: -4.6, y: -8.5, width: 9.2, height: 6.5), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
        ctx.setFillColor(hex(0x3D4C57)); ctx.addPath(CGPath(roundedRect: CGRect(x: -3.8, y: -8.4, width: 7.6, height: 4.6), cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)); ctx.fillPath()
        ctx.setFillColor(hex(0x2A353D)); ctx.fill(CGRect(x: -0.4, y: -8.4, width: 0.8, height: 4.6))
        ctx.setFillColor(hex(0xE8B547)); ctx.fill(CGRect(x: -0.9, y: -7.2, width: 1.8, height: 1.2))
        // Gills: three fronds a side.
        for side in [-1.0, 1.0] {
            for (i, a) in [-0.55, 0.0, 0.55].enumerated() {
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(side) * 5.6, y: -12.5 + CGFloat(i) * 1.6 - 1.6)
                ctx.rotate(by: CGFloat(side * (0.9 + a)))
                ctx.setFillColor(cg(gill)); ctx.addPath(CGPath(roundedRect: CGRect(x: -0.8, y: -3.6, width: 1.7, height: 4), cornerWidth: 0.85, cornerHeight: 0.85, transform: nil)); ctx.fillPath()
                ctx.restoreGState()
            }
        }
        // Head.
        ctx.setFillColor(cg(base)); ctx.fillEllipse(in: CGRect(x: -6.2, y: -16, width: 12.4, height: 8.6))
        ctx.setFillColor(cg(light)); ctx.fillEllipse(in: CGRect(x: -4.8, y: -15.6, width: 7, height: 3.2))
        ctx.setFillColor(cg(mix(base, (0.1, 0.06, 0.2), 0.18))); ctx.fillEllipse(in: CGRect(x: -5.2, y: -10.6, width: 10.4, height: 2.8))
        ctx.setFillColor(cg(base)); ctx.fillEllipse(in: CGRect(x: -5.6, y: -14, width: 11.2, height: 5))
        // Face.
        ctx.setFillColor(hex(0x1B1026))
        ctx.fillEllipse(in: CGRect(x: -3.6, y: -13, width: 1.6, height: 1.9)); ctx.fillEllipse(in: CGRect(x: 2, y: -13, width: 1.6, height: 1.9))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: -3.2, y: -12.8, width: 0.6, height: 0.6)); ctx.fillEllipse(in: CGRect(x: 2.4, y: -12.8, width: 0.6, height: 0.6))
        ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.67, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: -5.1, y: -11.6, width: 1.8, height: 1.1)); ctx.fillEllipse(in: CGRect(x: 3.3, y: -11.6, width: 1.8, height: 1.1))
        ctx.setStrokeColor(cg(mix(base, (0.1, 0.06, 0.2), 0.6))); ctx.setLineWidth(0.5); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: -1, y: -11)); ctx.addQuadCurve(to: CGPoint(x: 1, y: -11), control: CGPoint(x: 0, y: -10.2)); ctx.strokePath()
        // Hat.
        switch hat {
        case .captain:
            ctx.setFillColor(hex(0xF2F4F8)); ctx.addPath(CGPath(roundedRect: CGRect(x: -3.6, y: -19, width: 7.2, height: 3.6), cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)); ctx.fillPath()
            ctx.setFillColor(hex(0x1F2A44)); ctx.addPath(CGPath(roundedRect: CGRect(x: -4.4, y: -15.9, width: 8.8, height: 1.4), cornerWidth: 0.7, cornerHeight: 0.7, transform: nil)); ctx.fillPath()
            ctx.setFillColor(hex(0xE8B547)); ctx.fillEllipse(in: CGRect(x: -0.8, y: -18, width: 1.6, height: 1.4))
        case .beanie:
            ctx.setFillColor(hex(0xE0574A)); ctx.fillEllipse(in: CGRect(x: -3.8, y: -19.6, width: 7.6, height: 6))
            ctx.setFillColor(hex(0xB13C38)); ctx.addPath(CGPath(roundedRect: CGRect(x: -4.2, y: -16.4, width: 8.4, height: 1.8), cornerWidth: 0.9, cornerHeight: 0.9, transform: nil)); ctx.fillPath()
            ctx.setFillColor(hex(0xFFE3D6)); ctx.fillEllipse(in: CGRect(x: -1.1, y: -21, width: 2.2, height: 2.2))
        case .crown:
            let cr = CGMutablePath()
            cr.move(to: CGPoint(x: -3.2, y: -15.4)); cr.addLine(to: CGPoint(x: -3.2, y: -18.6)); cr.addLine(to: CGPoint(x: -1.6, y: -17.2))
            cr.addLine(to: CGPoint(x: 0, y: -19.4)); cr.addLine(to: CGPoint(x: 1.6, y: -17.2)); cr.addLine(to: CGPoint(x: 3.2, y: -18.6))
            cr.addLine(to: CGPoint(x: 3.2, y: -15.4)); cr.closeSubpath()
            ctx.setFillColor(hex(0xFFC93D)); ctx.addPath(cr); ctx.fillPath()
            ctx.setFillColor(hex(0xFF4F7B)); ctx.fillEllipse(in: CGRect(x: -0.6, y: -17, width: 1.2, height: 1.2))
        case .headlamp:
            ctx.setFillColor(hex(0x2A2F3A)); ctx.fill(CGRect(x: -5.4, y: -15, width: 10.8, height: 1.2))
            ctx.setFillColor(hex(0xFFD27A)); ctx.fillEllipse(in: CGRect(x: -1.4, y: -16.6, width: 2.8, height: 2.6))
        case .seashell:
            ctx.setFillColor(hex(0xFFB3C7)); ctx.fillEllipse(in: CGRect(x: -3.2, y: -19.2, width: 6.4, height: 4.4))
            ctx.setStrokeColor(hex(0xFF7FA3)); ctx.setLineWidth(0.5)
            for a in [-1.2, 0.0, 1.2] { ctx.move(to: CGPoint(x: 0, y: -15.2)); ctx.addLine(to: CGPoint(x: a * 2, y: -18.8)) }
            ctx.strokePath()
        case .none: break
        }
        ctx.restoreGState()
    }

    static func body(_ ctx: CGContext, at p: CGPoint, unit u: CGFloat, color: PlayerColor) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: -.pi / 2)
        ctx.setAlpha(0.8)
        axolotl(ctx, feet: .zero, unit: u, color: color, hat: .none, facingRight: true)
        ctx.restoreGState()
    }

    // MARK: Lineup

    static func lineup() -> CGImage {
        let size = CGSize(width: 764, height: 230)
        let ctx = context(size, 2)
        ctx.setFillColor(hex(0x0B1620)); ctx.fill(CGRect(origin: .zero, size: size))
        let colors: [PlayerColor] = [.coral, .ocean, .lime, .gold, .tangerine, .ink, .pearl, .violet, .cyan, .rose, .cocoa, .moss]
        let hats = Hat.allCases
        for (i, c) in colors.enumerated() {
            axolotl(ctx, feet: CGPoint(x: 40 + CGFloat(i) * 62, y: 120), unit: 3.2, color: c, hat: hats[i % hats.count], facingRight: i % 2 == 0)
        }
        for (i, h) in hats.enumerated() {
            axolotl(ctx, feet: CGPoint(x: 120 + CGFloat(i) * 100, y: 220), unit: 4.2, color: .gold, hat: h, facingRight: true)
        }
        return ctx.makeImage()!
    }

    // MARK: Helpers

    static func context(_ size: CGSize, _ scale: CGFloat) -> CGContext {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Top-left origin, y down, like the game.
        ctx.translateBy(x: 0, y: size.height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setShouldAntialias(true)
        return ctx
    }

    static func save(_ img: CGImage, _ url: URL) throws {
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
    }

    typealias C3 = (Double, Double, Double)
    static func rgb(_ h: UInt32) -> C3 { (Double((h >> 16) & 0xFF) / 255, Double((h >> 8) & 0xFF) / 255, Double(h & 0xFF) / 255) }
    static func mix(_ a: C3, _ b: C3, _ t: Double) -> C3 { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t) }
    static func cg(_ c: C3) -> CGColor { CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1) }
    static func hex(_ h: UInt32) -> CGColor { cg(rgb(h)) }
}
