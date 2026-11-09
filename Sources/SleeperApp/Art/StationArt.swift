import AppKit
import SleeperCore
import SpriteKit

/// The station in storybook paint: domes (floor, curved back wall with portholes, hull rim in front), glass tunnels,
/// and the sea around them. Everything is drawn once into textures when a game starts.
@MainActor enum StationArt {
    /// Texture pixels per world unit (16 units per tile).
    static let ppu: CGFloat = 4
    static let U = StoryArt.unit
    /// How tall the back wall of a dome stands, and the front rim, in world units.
    static let wallHeight: Double = 30
    static let rimHeight: Double = 7
    /// Hull thickness, in tiles.
    static let hull: Double = 1.0

    struct Piece {
        let texture: SKTexture
        /// World units, top-left origin (y down): the texture's top-left corner.
        let origin: CGPoint
        let size: CGSize
        let z: Double
    }

    static func floorTint(_ t: RoomTheme) -> CGColor {
        switch t {
        case .sonar: CGColor(srgbRed: 0.35, green: 0.55, blue: 0.75, alpha: 1)
        case .kelp: CGColor(srgbRed: 0.35, green: 0.65, blue: 0.5, alpha: 1)
        case .pearl: CGColor(srgbRed: 0.6, green: 0.55, blue: 0.75, alpha: 1)
        case .mess: CGColor(srgbRed: 0.5, green: 0.55, blue: 0.65, alpha: 1)
        case .thermal: CGColor(srgbRed: 0.8, green: 0.5, blue: 0.4, alpha: 1)
        case .ballast: CGColor(srgbRed: 0.35, green: 0.62, blue: 0.68, alpha: 1)
        case .pressure: CGColor(srgbRed: 0.5, green: 0.52, blue: 0.58, alpha: 1)
        case .hatchery: CGColor(srgbRed: 0.72, green: 0.5, blue: 0.62, alpha: 1)
        case .corridor: CGColor(srgbRed: 0.45, green: 0.5, blue: 0.58, alpha: 1)
        }
    }

    static func context(_ size: CGSize) -> CGContext {
        let ctx = CGContext(data: nil, width: Int(size.width * ppu), height: Int(size.height * ppu), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // World units, top-left origin, y down.
        ctx.translateBy(x: 0, y: size.height * ppu)
        ctx.scaleBy(x: ppu, y: -ppu)
        ctx.interpolationQuality = .high
        return ctx
    }

    static func texture(_ ctx: CGContext) -> SKTexture {
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .linear
        return t
    }

    /// Draws an image right side up into a y-down context.
    static func drawUpright(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
        ctx.restoreGState()
    }

    static func tiled(_ ctx: CGContext, _ img: CGImage, in r: CGRect, tile: CGFloat) {
        var y = r.minY
        while y < r.maxY {
            var x = r.minX
            while x < r.maxX { drawUpright(ctx, img, in: CGRect(x: x, y: y, width: tile, height: tile)); x += tile }
            y += tile
        }
    }

    // MARK: Build

    static func pieces(_ map: GameMap) -> [Piece] {
        var out: [Piece] = []
        out.append(sea(map))
        for t in map.corridors { out.append(contentsOf: tunnel(map, t)) }
        for r in map.rooms { out.append(contentsOf: dome(map, r)) }
        return out
    }

    // MARK: Sea

    /// The sea floor around the station: dark water, sand, rocks and kelp, softly painted (low resolution on purpose).
    static func sea(_ map: GameMap) -> Piece {
        let size = CGSize(width: Double(map.width) * U, height: Double(map.height) * U)
        let k: CGFloat = 0.5
        let ctx = CGContext(data: nil, width: Int(size.width * k), height: Int(size.height * k), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: size.height * k); ctx.scaleBy(x: k, y: -k)
        ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.09, blue: 0.14, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        var rng = SeededRandom(seed: 99)
        // Soft washes of lighter and darker water.
        for _ in 0..<160 {
            let r = 20 + rng.unit() * 90
            let c = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
            let light = rng.chance(0.5)
            ctx.setFillColor(light ? CGColor(srgbRed: 0.08, green: 0.2, blue: 0.27, alpha: 0.18) : CGColor(srgbRed: 0, green: 0.03, blue: 0.06, alpha: 0.2))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4))
        }
        // Rocks with an inked edge, and kelp.
        for _ in 0..<90 {
            let c = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
            if map[Vec2(c.x / U, c.y / U).tile] != .void { continue }
            let w = 6 + rng.unit() * 16, h = w * (0.5 + rng.unit() * 0.3)
            let rock = CGPath(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), transform: nil)
            ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.17, blue: 0.2, alpha: 1)); ctx.addPath(rock); ctx.fillPath()
            ctx.setStrokeColor(CGColor(srgbRed: 0.03, green: 0.05, blue: 0.08, alpha: 0.9)); ctx.setLineWidth(1.4); ctx.addPath(rock); ctx.strokePath()
            if rng.chance(0.5) {
                ctx.setStrokeColor(CGColor(srgbRed: 0.2, green: 0.45, blue: 0.3, alpha: 0.85)); ctx.setLineWidth(2)
                for s in 0..<3 {
                    ctx.move(to: CGPoint(x: c.x + Double(s) * 3, y: c.y))
                    ctx.addCurve(to: CGPoint(x: c.x + Double(s) * 3 + 4, y: c.y - 26), control1: CGPoint(x: c.x - 6, y: c.y - 8),
                                 control2: CGPoint(x: c.x + 10, y: c.y - 16))
                }
                ctx.strokePath()
            }
        }
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .linear
        return Piece(texture: t, origin: .zero, size: size, z: -20)
    }

    // MARK: Tunnels

    /// A glass tunnel: grating floor, glass walls you can see through, inked frames.
    static func tunnel(_ map: GameMap, _ r: TileRect) -> [Piece] {
        let horizontal = r.width >= r.height
        // Include the glass on both sides.
        let x0 = Double(r.x0) - (horizontal ? 0 : 1), x1 = Double(r.x1 + 1) + (horizontal ? 0 : 1)
        let y0 = Double(r.y0) - (horizontal ? 1 : 0), y1 = Double(r.y1 + 1) + (horizontal ? 1 : 0)
        let origin = CGPoint(x: x0 * U, y: y0 * U)
        let size = CGSize(width: (x1 - x0) * U, height: (y1 - y0) * U)
        let ctx = context(size)
        ctx.translateBy(x: -origin.x, y: -origin.y)
        let grate = StoryArt.image("tex-corridor")
        let glassFill = CGColor(srgbRed: 0.55, green: 0.85, blue: 1, alpha: 0.16)
        let glassLine = CGColor(srgbRed: 0.8, green: 0.95, blue: 1, alpha: 0.75)
        for ty in Int(y0)..<Int(y1) { for tx in Int(x0)..<Int(x1) {
            let p = TilePos(tx, ty)
            let rect = CGRect(x: Double(tx) * U, y: Double(ty) * U, width: U, height: U)
            if map[p] == .floor && map.room(at: p) == nil {
                if let grate {
                    ctx.saveGState(); ctx.clip(to: rect)
                    // Run the slats along the tunnel.
                    if horizontal { drawUpright(ctx, grate, in: CGRect(x: rect.minX, y: rect.minY, width: U, height: U)) }
                    else {
                        ctx.translateBy(x: rect.midX, y: rect.midY); ctx.rotate(by: .pi / 2)
                        drawUpright(ctx, grate, in: CGRect(x: -U / 2, y: -U / 2, width: U, height: U))
                    }
                    ctx.restoreGState()
                }
                ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.08, blue: 0.15, alpha: 0.35)); ctx.fill(rect)
            } else if map[p] == .glass {
                ctx.setFillColor(glassFill); ctx.fill(rect)
            }
        } }
        // Glass walls: a raised pane on the far side, a low rail on the near side, inked frames and reflections.
        ctx.setLineCap(.round)
        if horizontal {
            let top = CGRect(x: x0 * U, y: y0 * U, width: size.width, height: U)
            let paneTop = top.minY - 4, paneBottom = top.maxY
            ctx.setFillColor(CGColor(srgbRed: 0.6, green: 0.88, blue: 1, alpha: 0.14)); ctx.fill(CGRect(x: top.minX, y: paneTop, width: top.width, height: paneBottom - paneTop))
            ctx.setStrokeColor(glassLine); ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: top.minX, y: paneBottom)); ctx.addLine(to: CGPoint(x: top.maxX, y: paneBottom)); ctx.strokePath()
            ctx.setStrokeColor(StoryArt.ink); ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: top.minX, y: paneTop + 2)); ctx.addLine(to: CGPoint(x: top.maxX, y: paneTop + 2)); ctx.strokePath()
            // Ribs and glints.
            var x = top.minX + 8
            while x < top.maxX {
                ctx.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.35, blue: 0.45, alpha: 1)); ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: x, y: paneTop + 2)); ctx.addLine(to: CGPoint(x: x, y: y1 * U - 2)); ctx.strokePath()
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35)); ctx.setLineWidth(0.8)
                ctx.move(to: CGPoint(x: x + 5, y: paneTop + 4)); ctx.addLine(to: CGPoint(x: x + 9, y: paneBottom - 2)); ctx.strokePath()
                x += 32
            }
            let rail = (y1 - 1) * U
            ctx.setStrokeColor(glassLine); ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: top.minX, y: rail)); ctx.addLine(to: CGPoint(x: top.maxX, y: rail)); ctx.strokePath()
            ctx.setStrokeColor(StoryArt.ink); ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: top.minX, y: y1 * U - 3)); ctx.addLine(to: CGPoint(x: top.maxX, y: y1 * U - 3)); ctx.strokePath()
        } else {
            for side in [x0 * U, (x1 - 1) * U] {
                let inner = side == x0 * U ? side + U : side
                ctx.setStrokeColor(glassLine); ctx.setLineWidth(1.2)
                ctx.move(to: CGPoint(x: inner, y: y0 * U)); ctx.addLine(to: CGPoint(x: inner, y: y1 * U)); ctx.strokePath()
                ctx.setStrokeColor(StoryArt.ink); ctx.setLineWidth(1.6)
                let outer = side == x0 * U ? side + 3 : side + U - 3
                ctx.move(to: CGPoint(x: outer, y: y0 * U)); ctx.addLine(to: CGPoint(x: outer, y: y1 * U)); ctx.strokePath()
                var y = y0 * U + 8
                while y < y1 * U {
                    ctx.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.35, blue: 0.45, alpha: 1)); ctx.setLineWidth(2)
                    ctx.move(to: CGPoint(x: side + 3, y: y)); ctx.addLine(to: CGPoint(x: side + U - 3, y: y)); ctx.strokePath()
                    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.3)); ctx.setLineWidth(0.8)
                    ctx.move(to: CGPoint(x: side + 4, y: y + 6)); ctx.addLine(to: CGPoint(x: side + U - 4, y: y + 12)); ctx.strokePath()
                    y += 32
                }
            }
        }
        return [Piece(texture: texture(ctx), origin: origin, size: size, z: 1)]
    }

    // MARK: Domes

    /// A dome: the floor and curved back wall (behind everyone), and the hull rim along the front (sorted with the crew).
    static func dome(_ map: GameMap, _ room: Room) -> [Piece] {
        let R = room.radius * U                     // floor radius, world units
        let H = hull * U                            // hull thickness
        let c = CGPoint(x: room.center.x * U, y: room.center.y * U)
        let margin = H + wallHeight + 4
        let origin = CGPoint(x: c.x - R - margin, y: c.y - R - margin)
        let size = CGSize(width: (R + margin) * 2, height: (R + margin) * 2)

        // How high the hull stands at an angle (y-down: sin < 0 is the back).
        func raise(_ a: Double) -> Double { rimHeight + (wallHeight - rimHeight) * max(0, -sin(a)) }
        func pt(_ a: Double, _ r: Double, lift: Double = 0) -> CGPoint { CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r - lift) }
        /// Whether the hull exists at this angle (tunnels cut doorways through it).
        func solid(_ a: Double) -> Bool {
            let p = pt(a, R + H * 0.5)
            return map[Vec2(p.x / U, p.y / U).tile] == .wall
        }

        let steps = 240
        let angles = (0...steps).map { Double($0) / Double(steps) * 2 * .pi }

        // Back layer: floor disc, then the inner face and cap of the back half.
        let back = context(size)
        back.translateBy(x: -origin.x, y: -origin.y)
        let disc = CGPath(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), transform: nil)
        back.saveGState(); back.addPath(disc); back.clip()
        if let floor = StoryArt.image("tex-floor") { tiled(back, floor, in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), tile: 3 * U) }
        back.setFillColor(floorTint(room.theme)); back.setBlendMode(.color); back.fill(CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        back.setBlendMode(.normal)
        // Darker toward the hull, like a lamp-lit room.
        let vignette = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 0, alpha: 0), CGColor(srgbRed: 0, green: 0.02, blue: 0.06, alpha: 0.55)] as CFArray,
                                  locations: [0.45, 1])!
        back.drawRadialGradient(vignette, startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])
        back.restoreGState()

        let wall = StoryArt.image("tex-wall")
        let arcLen = 2 * Double.pi * R
        for i in 0..<steps {
            let a0 = angles[i], a1 = angles[i + 1], am = (a0 + a1) / 2
            guard sin(am) < 0.15, solid(am) else { continue }
            // Inner face: from the floor edge up to the raised top, textured with the wall painting along the arc.
            let p0 = pt(a0, R), p1 = pt(a1, R)
            let lift = raise(am)
            let x = min(p0.x, p1.x), w = max(abs(p1.x - p0.x), 0.6)
            let top = min(p0.y, p1.y) - lift
            let rect = CGRect(x: x, y: top, width: w, height: max(p0.y, p1.y) - top)
            if let wall {
                let u = (am * R).truncatingRemainder(dividingBy: arcLen) / (Double(wall.width) / 4)
                let col = Int((u - floor(u)) * Double(wall.width)) % wall.width
                let colW = max(1, Int(w / (wallHeight) * Double(wall.height) * 0.62))
                if let slice = wall.cropping(to: CGRect(x: col, y: Int(Double(wall.height) * 0.05), width: min(colW, wall.width - col),
                                                        height: Int(Double(wall.height) * 0.62))) {
                    drawUpright(back, slice, in: rect)
                }
            }
            // Shade the face toward the sides.
            back.setFillColor(CGColor(srgbRed: 0, green: 0.02, blue: 0.05, alpha: 0.5 * (1 - abs(sin(am))))); back.fill(rect)
        }
        // Cap of the back half, and its inked edges.
        func capPath(_ range: [Double], liftBy: (Double) -> Double) -> CGPath {
            let path = CGMutablePath()
            path.move(to: pt(range[0], R, lift: liftBy(range[0])))
            for a in range { path.addLine(to: pt(a, R, lift: liftBy(a))) }
            for a in range.reversed() { path.addLine(to: pt(a, R + H, lift: liftBy(a))) }
            path.closeSubpath()
            return path
        }
        func runs(_ test: (Double) -> Bool) -> [[Double]] {
            var out: [[Double]] = [], cur: [Double] = []
            for a in angles { if test(a) && solid(a) { cur.append(a) } else if !cur.isEmpty { out.append(cur); cur = [] } }
            if !cur.isEmpty { out.append(cur) }
            return out.filter { $0.count > 1 }
        }
        let capFill = CGColor(srgbRed: 0.2, green: 0.27, blue: 0.36, alpha: 1)
        for run in runs({ sin($0) < 0.15 }) {
            let p = capPath(run, liftBy: raise)
            back.setFillColor(capFill); back.addPath(p); back.fillPath()
            back.setStrokeColor(StoryArt.ink); back.setLineWidth(1.4); back.addPath(p); back.strokePath()
            // The seam where the face meets the floor.
            back.move(to: pt(run[0], R)); for a in run { back.addLine(to: pt(a, R)) }
            back.setStrokeColor(StoryArt.ink); back.setLineWidth(1.6); back.strokePath()
        }

        // Front layer: the near half of the hull, a low rim with its outer face, drawn over the crew inside.
        let front = context(size)
        front.translateBy(x: -origin.x, y: -origin.y)
        for run in runs({ sin($0) >= 0.15 }) {
            let p = capPath(run, liftBy: raise)
            // Outer face below the cap's outer edge.
            let face = CGMutablePath()
            face.move(to: pt(run[0], R + H, lift: raise(run[0])))
            for a in run { face.addLine(to: pt(a, R + H, lift: raise(a))) }
            for a in run.reversed() { face.addLine(to: pt(a, R + H)) }
            face.closeSubpath()
            front.setFillColor(CGColor(srgbRed: 0.12, green: 0.17, blue: 0.23, alpha: 1)); front.addPath(face); front.fillPath()
            front.setStrokeColor(StoryArt.ink); front.setLineWidth(1.4); front.addPath(face); front.strokePath()
            front.setFillColor(capFill); front.addPath(p); front.fillPath()
            front.setStrokeColor(StoryArt.ink); front.setLineWidth(1.4); front.addPath(p); front.strokePath()
            // Rivets along the rim.
            front.setFillColor(CGColor(srgbRed: 0.45, green: 0.55, blue: 0.62, alpha: 1))
            for (k, a) in run.enumerated() where k % 6 == 3 {
                let q = pt(a, R + H * 0.5, lift: raise(a))
                front.fillEllipse(in: CGRect(x: q.x - 0.9, y: q.y - 0.9, width: 1.8, height: 1.8))
            }
        }
        // Door frames where tunnels cut through.
        for i in 0..<steps {
            let a0 = angles[i], a1 = angles[i + 1]
            guard solid(a0) != solid(a1) else { continue }
            let a = solid(a0) ? a0 : a1
            let target = sin(a) < 0.15 ? back : front
            target.setStrokeColor(StoryArt.ink); target.setLineWidth(2)
            target.move(to: pt(a, R, lift: 0)); target.addLine(to: pt(a, R, lift: raise(a))); target.addLine(to: pt(a, R + H, lift: raise(a)))
            target.strokePath()
        }
        let bottom = (room.center.y + room.radius + hull)
        return [Piece(texture: texture(back), origin: origin, size: size, z: 2),
                Piece(texture: texture(front), origin: origin, size: size, z: 100 + bottom)]
    }
}
