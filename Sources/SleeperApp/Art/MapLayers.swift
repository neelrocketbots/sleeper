import SleeperCore
import SpriteKit

/// The map in 2.5D (three-quarter view): a flat floor texture, then walls and props as raised sprites, one wall strip
/// per row, all depth-sorted with the characters.
struct MapLayers {
    struct Raised {
        let texture: SKTexture
        /// Map pixels: the bottom-left corner of the footprint (the sprite extends up from here).
        let x: Double, bottom: Double
        /// The footprint's bottom edge in tile rows, for depth sorting.
        let depth: Double
    }
    let floor: SKTexture
    let raised: [Raised]
    let lights: [MapLight]
}

extension MapArt {
    /// How tall walls stand, in pixels. South walls (facing away from you) are a low ledge so they don't hide rooms.
    static let wallHeight = 22
    static let ledgeHeight = 6

    static func propHeight(_ k: PropKind) -> Int {
        switch k {
        case .console, .sonarDish, .oxygenConsole: 11
        case .sealPanel, .lightPanel: 13
        case .chartTable, .table: 8
        case .pearlBench: 8
        case .kelpTank: 24
        case .ballastTank: 26
        case .filter: 14
        case .feeder: 10
        case .eggBed: 4
        case .ventGrate: 2
        case .airlock: 2
        }
    }

    static func layers(_ map: GameMap) -> MapLayers {
        let T = tile
        let H = wallHeight
        var lights: [MapLight] = []

        func open(_ x: Int, _ y: Int) -> Bool { let t = map[TilePos(x, y)]; return t == .floor || t == .prop }
        func isWall(_ x: Int, _ y: Int) -> Bool { map[TilePos(x, y)] == .wall }
        func isSouthWall(_ x: Int, _ y: Int) -> Bool { isWall(x, y) && open(x, y - 1) }
        func isLow(_ x: Int, _ y: Int) -> Bool {
            guard isWall(x, y) else { return false }
            if isSouthWall(x, y) { return true }
            // The corner where a side wall meets a south wall.
            return (isSouthWall(x - 1, y) || isSouthWall(x + 1, y)) && !open(x, y + 1)
        }

        // 1. Floor: floors, water, dark wall footprints, contact shadows.
        let f = PixelCanvas(map.width * T, map.height * T)
        for ty in 0..<map.height { for tx in 0..<map.width {
            let p = TilePos(tx, ty)
            switch map[p] {
            case .void: water(f, tx * T, ty * T, tx, ty)
            case .floor, .prop: floor(f, tx * T, ty * T, tx, ty, map.room(at: p)?.theme ?? .corridor)
            case .wall: f.rect(tx * T, ty * T, T, T, RGB(hex: 0x060B10))
            }
        } }
        // Shadow cast by the tall north walls onto the floor in front of them.
        for ty in 0..<map.height { for tx in 0..<map.width where open(tx, ty) && isWall(tx, ty - 1) && !isLow(tx, ty - 1) {
            for (row, k) in [(0, 0.55), (1, 0.42), (2, 0.3), (3, 0.2), (4, 0.12), (5, 0.06)] {
                for x in 0..<T { f[tx * T + x, ty * T + row] = f[tx * T + x, ty * T + row].darker(k) }
            }
        } }
        // Side walls shade the floor beside them a little.
        for ty in 0..<map.height { for tx in 0..<map.width where open(tx, ty) {
            if isWall(tx - 1, ty) { for y in 0..<T { for (col, k) in [(0, 0.3), (1, 0.15)] { f[tx * T + col, ty * T + y] = f[tx * T + col, ty * T + y].darker(k) } } }
            if isWall(tx + 1, ty) { for y in 0..<T { for (col, k) in [(15, 0.3), (14, 0.15)] { f[tx * T + col, ty * T + y] = f[tx * T + col, ty * T + y].darker(k) } } }
        } }
        // Props cast soft shadows down and to the right.
        for prop in map.props {
            let x0 = prop.rect.x0 * T, y0 = prop.rect.y0 * T, w = prop.rect.width * T, h = prop.rect.height * T
            let reach = min(6, 2 + propHeight(prop.kind) / 5)
            for y in (y0 + 2)..<(y0 + h + reach) { for x in (x0 + 2)..<(x0 + w + reach) {
                let edge = max(0, max(y - (y0 + h), x - (x0 + w)))
                f.blend(x, y, RGB(0, 0.01, 0.03, 0.42 * (1 - Double(edge) / Double(reach + 1))))
            } }
        }

        var raised: [MapLayers.Raised] = []

        // 2. Walls, one strip per row. The strip is the row's footprint plus H pixels of headroom above it.
        for ty in 0..<map.height {
            var any = false
            let c = PixelCanvas(map.width * T, T + H)
            for tx in 0..<map.width where isWall(tx, ty) {
                any = true
                let low = isLow(tx, ty)
                let h = low ? ledgeHeight : H
                let capTop = H - h
                let ox = tx * T
                // Front face: down to the footprint's bottom, or to the top of a ledge below.
                var faceBottom: Int?
                if !isWall(tx, ty + 1) { faceBottom = T + H }
                else if isLow(tx, ty + 1) && !low { faceBottom = T + H - ledgeHeight }
                if let fb = faceBottom, fb > capTop + T {
                    let exterior = !open(tx, ty + 1)
                    face(c, ox, capTop + T, fb, tx, ty, exterior: exterior, low: low, lights: &lights, mapY: ty * T - H)
                }
                cap(c, ox, capTop, tx, ty, open: open, low: low)
            }
            if any {
                raised.append(.init(texture: c.texture(), x: 0, bottom: Double((ty + 1) * T), depth: Double(ty + 1)))
            }
        }

        // 3. Props: top surface raised by its height, front face below it.
        for prop in map.props {
            let w = prop.rect.width * T, h = prop.rect.height * T
            let ph = propHeight(prop.kind)
            let c = PixelCanvas(w, h + ph)
            front(c, prop.kind, w: w, top: h, height: ph)
            var local: [MapLight] = []
            drawProp(c, prop, &local, origin: (0, 0))
            let x0 = Double(prop.rect.x0 * T), y0 = Double(prop.rect.y0 * T)
            for l in local {
                lights.append(MapLight(x: x0 + l.x, y: y0 + l.y - Double(ph), color: l.color, radius: l.radius, flicker: l.flicker))
            }
            raised.append(.init(texture: c.texture(), x: x0, bottom: Double((prop.rect.y1 + 1) * T),
                                depth: Double(prop.rect.y1 + 1) - 0.05))
        }
        return MapLayers(floor: f.texture(), raised: raised, lights: lights)
    }

    // MARK: Wall pieces

    /// The wall's top, seen from above, with a bright rim on edges that face a room.
    static func cap(_ c: PixelCanvas, _ ox: Int, _ oy: Int, _ tx: Int, _ ty: Int, open: (Int, Int) -> Bool, low: Bool) {
        let base = RGB(hex: 0x1A2733), rim = RGB(hex: 0x5A7A92)
        for y in 0..<tile { for x in 0..<tile {
            c[ox + x, oy + y] = base.mix(RGB(hex: 0x24384A), hash2(ox + x, oy + y + ty * 16, 5) * 0.3)
        } }
        // Top-left light.
        c.hline(ox, ox + 15, oy, base.lighter(0.18))
        if open(tx, ty - 1) || low { c.hline(ox, ox + 15, oy, rim); c.hline(ox, ox + 15, oy + 1, rim.darker(0.4)) }
        if open(tx - 1, ty) { c.vline(ox, oy, oy + 15, rim); c.vline(ox + 1, oy, oy + 15, rim.darker(0.45)) }
        if open(tx + 1, ty) { c.vline(ox + 15, oy, oy + 15, rim.darker(0.25)); c.vline(ox + 14, oy, oy + 15, rim.darker(0.55)) }
        if open(tx, ty + 1) { c.hline(ox, ox + 15, oy + 15, RGB(hex: 0x0B1219)) }
        // Plate seams.
        if tx % 3 == 0 { c.vline(ox + 8, oy + 3, oy + 12, base.darker(0.35)) }
        if (tx + ty) % 4 == 0 { c[ox + 4, oy + 4] = base.lighter(0.3); c[ox + 11, oy + 11] = base.lighter(0.3) }
    }

    /// The wall's front face, from `top` to `bottom` (strip rows).
    static func face(_ c: PixelCanvas, _ ox: Int, _ top: Int, _ bottom: Int, _ tx: Int, _ ty: Int, exterior: Bool, low: Bool,
                     lights: inout [MapLight], mapY: Int) {
        let h = bottom - top
        if exterior || low {
            // Outside of the hull, or a ledge: plain darker plating.
            for y in top..<bottom { for x in 0..<tile {
                var col = RGB(hex: 0x111B24).mix(RGB(hex: 0x182633), hash2(ox + x, y + ty * 16, 8) * 0.3)
                if y == top { col = RGB(hex: 0x2E4254) }
                if y == bottom - 1 { col = RGB(hex: 0x05090D) }
                c[ox + x, y] = col
            } }
            return
        }
        let panel = RGB(hex: 0x1B2A38), pipe = RGB(hex: 0x29404F)
        for y in top..<bottom { for x in 0..<tile {
            let r = y - top
            var col: RGB
            switch r {
            case 0: col = RGB(hex: 0x4A6880)
            case 1: col = panel.lighter(0.12)
            case _ where r == h - 1: col = RGB(hex: 0x04080C)
            case _ where r == h - 2: col = RGB(hex: 0x0E161E)
            case _ where r == h - 3: col = RGB(hex: 0x2A3A48)  // baseboard
            default: col = panel.mix(RGB(hex: 0x15212C), Double(r) / Double(h))  // darker toward the floor
            }
            // A pipe runs along the wall.
            if r == 5 { col = pipe.lighter(0.35) }
            if r == 6 || r == 7 { col = pipe }
            if r == 8 { col = pipe.darker(0.4) }
            // Panel seams.
            if r > 9 && r < h - 3 && x == 0 && tx % 2 == 0 { col = col.darker(0.3) }
            c[ox + x, y] = col
        } }
        // Rivets.
        c[ox + 3, top + 11] = RGB(hex: 0x5A7488); c[ox + 12, top + 11] = RGB(hex: 0x5A7488)
        let hh = hash2(tx, ty, 11)
        let mapTop = Double(mapY + top)
        if hh < 0.4 && h >= 18 {
            // A porthole onto the deep.
            let cx = Double(ox) + 8, cy = Double(top) + 13
            c.disc(cx, cy, 5.6, RGB(hex: 0x7F97A6))
            c.disc(cx, cy, 4.5, RGB(hex: 0x081F33))
            c.disc(cx + 0.6, cy + 0.8, 3.4, RGB(hex: 0x0E3E62))
            c.disc(cx - 1.6, cy - 1.6, 1.3, RGB(hex: 0x9FE3FF, alpha: 0.95))
            c[ox + 11, Int(cy) + 2] = RGB(hex: 0x2B6E9A)
            if hash2(tx, ty, 13) > 0.6 { c[ox + 9, Int(cy)] = RGB(hex: 0x4FD1C5) }  // something glowing outside
            lights.append(MapLight(x: cx, y: mapTop + 13 + 10, color: RGB(hex: 0x2E8BC0), radius: 24, flicker: false))
        } else if hh > 0.8 {
            // A wall lamp with a hood.
            c.hline(ox + 4, ox + 11, top + 9, RGB(hex: 0x3A4A58))
            c.rect(ox + 5, top + 10, 6, 2, RGB(hex: 0xFFE7B0))
            c.hline(ox + 6, ox + 9, top + 12, RGB(hex: 0xFFC46B, alpha: 0.6))
            lights.append(MapLight(x: Double(ox) + 8, y: mapTop + 14 + 8, color: RGB(hex: 0xFFC46B), radius: 34, flicker: hh > 0.95))
        } else if hh > 0.62 {
            // A status screen.
            c.rect(ox + 3, top + 10, 10, 6, RGB(hex: 0x0A2A30))
            c.hline(ox + 4, ox + 4 + Int(hash2(tx, 2) * 7), top + 12, RGB(hex: 0x39D0E0))
            c.hline(ox + 4, ox + 4 + Int(hash2(tx, 3) * 7), top + 14, RGB(hex: 0x39D0E0, alpha: 0.6))
        }
    }

    /// A prop's front face: `height` pixels below its top surface.
    static func front(_ c: PixelCanvas, _ k: PropKind, w: Int, top: Int, height: Int) {
        guard height > 0 else { return }
        let base: RGB
        switch k {
        case .console, .sonarDish, .oxygenConsole: base = RGB(hex: 0x141C24)
        case .sealPanel, .lightPanel: base = RGB(hex: 0x1F242D)
        case .chartTable: base = RGB(hex: 0x3A2E23)
        case .pearlBench: base = RGB(hex: 0x3A3149)
        case .table: base = RGB(hex: 0x2B3541)
        case .filter: base = RGB(hex: 0x24303B)
        case .feeder: base = RGB(hex: 0x2F3A2D)
        case .eggBed: base = RGB(hex: 0x473629)
        case .kelpTank: base = RGB(hex: 0x0C3533)
        case .ballastTank: base = RGB(hex: 0x1F5560)
        case .ventGrate, .airlock: base = RGB(hex: 0x10151B)
        }
        if k == .ballastTank {
            // A cylinder: shaded left to right, with a highlight band and rivet rings.
            for y in top..<(top + height) { for x in 1..<(w - 1) {
                let u = Double(x) / Double(w)
                var col = base.lighter(max(0, 0.35 - abs(u - 0.32) * 1.2)).darker(max(0, (u - 0.6) * 0.9))
                if (y - top) % 8 == 0 { col = col.darker(0.3) }
                c[x, y] = col
            } }
            c.rect(w / 2 - 3, top + height / 2 - 2, 6, 5, RGB(hex: 0x0E2A30))
            c.hline(w / 2 - 2, w / 2 + 1, top + height / 2, RGB(hex: 0x6FD3E0))
            return
        }
        if k == .kelpTank {
            // Glass: you can see the kelp through the front.
            for y in top..<(top + height) { for x in 1..<(w - 1) {
                var col = base.mix(RGB(hex: 0x135A52), Double(y - top) / Double(height) * 0.5)
                if x == 1 || x == w - 2 { col = RGB(hex: 0x2A3B44) }
                c[x, y] = col
            } }
            for k2 in 0..<max(1, w / 6) {
                let kx = 5 + k2 * 6
                for y in (top + 2)..<(top + height - 1) {
                    let wob = Int((sin(Double(y) * 0.5 + Double(k2) * 2) * 1.3).rounded())
                    c[kx + wob, y] = RGB(hex: 0x3FB56A).mix(RGB(hex: 0x8FE36B), hash2(kx, y) * 0.5)
                }
            }
            c.vline(3, top + 1, top + height - 3, RGB(hex: 0xBFFFF4, alpha: 0.5))  // glass glint
            c.hline(1, w - 2, top + height - 1, RGB(hex: 0x1A2830))
            return
        }
        for y in top..<(top + height) { for x in 1..<(w - 1) {
            var col = base.mix(RGB(0, 0, 0), Double(y - top) / Double(height) * 0.35)
            if y == top { col = base.lighter(0.2) }
            if x == 1 { col = col.lighter(0.08) }
            if x == w - 2 { col = col.darker(0.3) }
            c[x, y] = col
        } }
        switch k {
        case .table, .chartTable, .pearlBench:
            // Legs with a gap between them.
            for y in (top + 2)..<(top + height) { for x in 4..<(w - 4) { c[x, y] = RGB(hex: 0x05090D, alpha: 0.85) } }
        case .console, .sonarDish, .oxygenConsole, .sealPanel, .lightPanel, .filter:
            // Vents and a status light.
            for i in 0..<max(1, (w - 8) / 4) { c.vline(5 + i * 4, top + 3, top + height - 3, base.darker(0.45)) }
            c[w - 5, top + 3] = RGB(hex: 0x6BFF9A)
        default: break
        }
    }

    /// Debug: everything composited into one picture, in draw order.
    static func compose(_ map: GameMap) -> CGImage {
        let L = layers(map)
        let w = map.width * tile, h = map.height * tile
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(L.floor.cgImage(), in: CGRect(x: 0, y: 0, width: w, height: h))
        for r in L.raised.sorted(by: { $0.depth < $1.depth }) {
            let img = r.texture.cgImage()
            // CG's origin is bottom-left: the sprite's bottom sits at the footprint's bottom.
            ctx.draw(img, in: CGRect(x: r.x, y: Double(h) - r.bottom, width: Double(img.width), height: Double(img.height)))
        }
        return ctx.makeImage()!
    }
}
