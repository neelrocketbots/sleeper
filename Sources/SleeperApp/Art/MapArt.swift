import SleeperCore
import SpriteKit

/// A light baked into the scene as an additive glow sprite.
struct MapLight {
    let x: Double, y: Double  // map pixels, origin top-left
    let color: RGB
    let radius: Double
    let flicker: Bool
}

/// Bakes the whole map into one texture (one draw call), plus the lights to place on top of it.
enum MapArt {
    static let tile = 16

    static func floorColor(_ theme: RoomTheme) -> RGB {
        switch theme {
        case .sonar: RGB(hex: 0x22303F)
        case .kelp: RGB(hex: 0x213A33)
        case .pearl: RGB(hex: 0x2D3048)
        case .mess: RGB(hex: 0x2A3644)
        case .thermal: RGB(hex: 0x3A2A28)
        case .ballast: RGB(hex: 0x213A46)
        case .pressure: RGB(hex: 0x2A3039)
        case .hatchery: RGB(hex: 0x352E42)
        case .corridor: RGB(hex: 0x1C2630)
        }
    }

    static func bake(_ map: GameMap) -> (texture: SKTexture, lights: [MapLight]) {
        let T = tile
        let c = PixelCanvas(map.width * T, map.height * T)
        var lights: [MapLight] = []

        func themeAt(_ p: TilePos) -> RoomTheme { map.room(at: p)?.theme ?? .corridor }

        for ty in 0..<map.height { for tx in 0..<map.width {
            let p = TilePos(tx, ty)
            let ox = tx * T, oy = ty * T
            switch map[p] {
            case .void: water(c, ox, oy, tx, ty)
            case .floor, .prop: floor(c, ox, oy, tx, ty, themeAt(p))
            case .wall:
                let south = map[TilePos(tx, ty + 1)]
                if south == .floor || south == .prop {
                    let exterior = map[TilePos(tx, ty - 1)] == .void
                    wallFace(c, ox, oy, tx, ty, exterior: exterior, lights: &lights)
                } else {
                    wallTop(c, ox, oy, tx, ty, map)
                }
            }
        } }

        // Ambient occlusion under wall faces and around props.
        for ty in 0..<map.height { for tx in 0..<map.width where map[TilePos(tx, ty)] == .floor {
            if map[TilePos(tx, ty - 1)] == .wall {
                for (row, k) in [(0, 0.45), (1, 0.28), (2, 0.14), (3, 0.06)] {
                    for x in 0..<T { let px = c[tx * T + x, ty * T + row]; c[tx * T + x, ty * T + row] = px.darker(k) }
                }
            }
        } }

        for prop in map.props { drawProp(c, prop, &lights) }
        return (c.texture(), lights)
    }

    // MARK: Tiles

    static func water(_ c: PixelCanvas, _ ox: Int, _ oy: Int, _ tx: Int, _ ty: Int) {
        let base = RGB(hex: 0x041019)
        for y in 0..<tile { for x in 0..<tile {
            let n = hash2(ox + x, oy + y, 3)
            var col = base.mix(RGB(hex: 0x07202F), 0.25 * hash2((ox + x) / 6, (oy + y) / 6, 9))
            if n > 0.996 { col = RGB(hex: 0x4FD1C5, alpha: 1).mix(base, 0.4) }
            c[ox + x, oy + y] = col
        } }
    }

    static func floor(_ c: PixelCanvas, _ ox: Int, _ oy: Int, _ tx: Int, _ ty: Int, _ theme: RoomTheme) {
        var base = floorColor(theme)
        if theme == .mess && (tx + ty) % 2 == 0 { base = base.lighter(0.04) }
        for y in 0..<tile { for x in 0..<tile {
            var col = base.mix(RGB(0, 0, 0), (hash2(ox + x, oy + y) - 0.5) * 0.08)
            if theme == .corridor {
                if x % 4 == 1 { col = col.darker(0.35) }
                if y == 0 || y == 15 { col = col.darker(0.2) }
            } else {
                if x == 0 || y == 0 { col = col.lighter(0.07) }
                if x == 15 || y == 15 { col = col.darker(0.28) }
                if (x == 2 || x == 13) && (y == 2 || y == 13) { col = base.lighter(0.22) }
                if (x == 3 || x == 14) && (y == 3 || y == 14) { col = base.darker(0.3) }
            }
            c[ox + x, oy + y] = col
        } }
        // Occasional drain or hazard markings, for variety.
        let h = hash2(tx, ty, 17)
        if theme != .corridor && h > 0.93 {
            for y in 5...10 { for x in 5...10 where (x + y) % 2 == 0 { c[ox + x, oy + y] = base.darker(0.4) } }
        }
    }

    static func wallTop(_ c: PixelCanvas, _ ox: Int, _ oy: Int, _ tx: Int, _ ty: Int, _ map: GameMap) {
        let base = RGB(hex: 0x0D151D)
        let rim = RGB(hex: 0x3A5266)
        let open = { (dx: Int, dy: Int) -> Bool in let t = map[TilePos(tx + dx, ty + dy)]; return t == .floor || t == .prop }
        for y in 0..<tile { for x in 0..<tile {
            c[ox + x, oy + y] = base.mix(RGB(hex: 0x16222D), hash2(ox + x, oy + y, 5) * 0.35)
        } }
        // Bevelled rim facing the rooms.
        if open(0, -1) { c.hline(ox, ox + 15, oy + 15, rim.darker(0.3)) }
        if open(-1, 0) { c.vline(ox, oy, oy + 15, rim); c.vline(ox + 1, oy, oy + 15, rim.darker(0.5)) }
        if open(1, 0) { c.vline(ox + 15, oy, oy + 15, rim); c.vline(ox + 14, oy, oy + 15, rim.darker(0.5)) }
        if open(0, 1) { c.hline(ox, ox + 15, oy + 15, rim) }
        // Seam lines on the slab.
        if tx % 3 == 0 { c.vline(ox + 8, oy + 3, oy + 12, RGB(hex: 0x091017)) }
    }

    static func wallFace(_ c: PixelCanvas, _ ox: Int, _ oy: Int, _ tx: Int, _ ty: Int, exterior: Bool, lights: inout [MapLight]) {
        let cap = RGB(hex: 0x0D151D), panel = RGB(hex: 0x182431), pipe = RGB(hex: 0x23323F)
        for y in 0..<tile { for x in 0..<tile {
            var col: RGB
            switch y {
            case 0...3: col = cap.mix(RGB(hex: 0x16222D), hash2(ox + x, oy + y, 5) * 0.3)
            case 4: col = RGB(hex: 0x3D5468)
            case 5: col = panel.lighter(0.08)
            case 8: col = pipe.lighter(0.25)
            case 9, 10: col = pipe
            case 15: col = RGB(hex: 0x0A0F14)
            default: col = panel
            }
            if y >= 5 && y <= 14 && (x == 0 || x == 15) && tx % 2 == 0 { col = col.darker(0.25) }
            c[ox + x, oy + y] = col
        } }
        // Bolts.
        c[ox + 2, oy + 12] = RGB(hex: 0x4A6070); c[ox + 13, oy + 12] = RGB(hex: 0x4A6070)
        let h = hash2(tx, ty, 11)
        if exterior && h < 0.42 {
            // A porthole onto the deep.
            let cx = Double(ox) + 8, cy = Double(oy) + 9.5
            c.disc(cx, cy, 5.2, RGB(hex: 0x6F8796))
            c.disc(cx, cy, 4.2, RGB(hex: 0x0A2E4A))
            c.disc(cx - 0.5, cy + 0.6, 3.2, RGB(hex: 0x0E3E62))
            c.disc(cx - 1.5, cy - 1.5, 1.2, RGB(hex: 0x7FD3FF, alpha: 0.9))
            c[ox + 10, oy + 11] = RGB(hex: 0x2B6E9A)
            lights.append(MapLight(x: cx, y: cy + 4, color: RGB(hex: 0x2E8BC0), radius: 22, flicker: false))
        } else if h > 0.82 {
            // A wall lamp.
            c.rect(ox + 6, oy + 6, 4, 2, RGB(hex: 0xFFE1A0))
            c.hline(ox + 5, ox + 10, oy + 8, RGB(hex: 0x6B5A3A))
            lights.append(MapLight(x: Double(ox) + 8, y: Double(oy) + 12, color: RGB(hex: 0xFFC46B), radius: 30, flicker: h > 0.95))
        }
    }

    // MARK: Props

    /// Paints a prop's top surface. With `origin`, it paints at that spot (its own sprite) instead of on the map.
    static func drawProp(_ c: PixelCanvas, _ prop: Prop, _ lights: inout [MapLight], origin: (Int, Int)? = nil) {
        let T = tile
        let x0 = origin?.0 ?? prop.rect.x0 * T, y0 = origin?.1 ?? prop.rect.y0 * T
        let w = prop.rect.width * T, h = prop.rect.height * T
        let cx = Double(x0) + Double(w) / 2, cy = Double(y0) + Double(h) / 2
        func box(_ body: RGB, inset: Int = 1) {
            c.rect(x0 + inset, y0 + inset + 1, w - 2 * inset, h - 2 * inset, RGB(0, 0, 0, 0.35))  // drop shadow
            c.rect(x0 + inset, y0 + inset, w - 2 * inset, h - 2 * inset - 1, body)
            c.hline(x0 + inset, x0 + w - inset - 1, y0 + inset, body.lighter(0.25))
            c.hline(x0 + inset, x0 + w - inset - 1, y0 + h - inset - 2, body.darker(0.35))
            c.vline(x0 + inset, y0 + inset, y0 + h - inset - 2, body.lighter(0.12))
            c.vline(x0 + w - inset - 1, y0 + inset, y0 + h - inset - 2, body.darker(0.25))
        }
        func screen(_ glow: RGB, lines: Bool = true) {
            let sx = x0 + 3, sy = y0 + 3, sw = w - 6, sh = min(h - 7, 7)
            c.rect(sx, sy, sw, sh, glow.darker(0.75))
            if lines { for i in stride(from: 1, to: sh, by: 2) { c.hline(sx + 1, sx + 1 + Int(Double(sw - 3) * (0.4 + hash2(x0, i) * 0.6)), sy + i, glow) } }
            lights.append(MapLight(x: cx, y: Double(sy + sh / 2), color: glow, radius: Double(max(w, 24)) * 0.9, flicker: false))
        }
        switch prop.kind {
        case .console:
            box(RGB(hex: 0x1A232D)); screen(RGB(hex: 0x39D0E0))
            for i in 0..<(w / 6) { c[x0 + 3 + i * 6, y0 + h - 4] = RGB(hex: i % 2 == 0 ? 0xFF5A6A : 0x6BFF9A) }
        case .sonarDish:
            box(RGB(hex: 0x17262A))
            let sx = Double(x0) + Double(w) / 2, sy = Double(y0) + 8
            c.disc(sx, sy, 6.5, RGB(hex: 0x0B2A1E))
            c.ring(sx, sy, 6, RGB(hex: 0x3DFF9A, alpha: 0.7)); c.ring(sx, sy, 3.5, RGB(hex: 0x3DFF9A, alpha: 0.45))
            c.hline(Int(sx), Int(sx) + 5, Int(sy), RGB(hex: 0x9DFFC8))
            c[Int(sx) + 3, Int(sy) - 3] = RGB(hex: 0xFFFFFF)
            lights.append(MapLight(x: sx, y: sy, color: RGB(hex: 0x3DFF9A), radius: 34, flicker: false))
        case .chartTable:
            box(RGB(hex: 0x4A3B2E))
            c.rect(x0 + 4, y0 + 4, w - 8, h - 9, RGB(hex: 0xD9CBA8))
            for i in 0..<5 { c.hline(x0 + 6, x0 + w - 8 - i * 3, y0 + 7 + i * 4, RGB(hex: 0x8A7A60)) }
            c.ring(Double(x0 + w - 12), Double(y0 + 12), 3, RGB(hex: 0xC0504D))
        case .kelpTank:
            box(RGB(hex: 0x2A3B44))
            c.rect(x0 + 3, y0 + 3, w - 6, h - 7, RGB(hex: 0x0E3B3A))
            for k in 0..<max(1, w / 6) {
                let kx = x0 + 5 + k * 6
                for y in stride(from: y0 + h - 6, to: y0 + 4, by: -1) {
                    let wob = Int((sin(Double(y) * 0.6 + Double(k)) * 1.2).rounded())
                    c[kx + wob, y] = RGB(hex: 0x3FB56A).mix(RGB(hex: 0x8FE36B), hash2(kx, y) * 0.5)
                }
            }
            c.hline(x0 + 3, x0 + w - 4, y0 + 3, RGB(hex: 0x8FD9D0, alpha: 0.6))
            c[x0 + w - 6, y0 + 6] = RGB(hex: 0xCFFFF8); c[x0 + w - 7, y0 + 9] = RGB(hex: 0xCFFFF8)
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0x3FD08A), radius: Double(max(w, h)) * 1.1, flicker: false))
        case .pearlBench:
            box(RGB(hex: 0x4A3F5C))
            for i in 0..<(w / 7) {
                let px = Double(x0) + 6 + Double(i) * 7, py = Double(y0) + Double(h) / 2 - 1
                c.disc(px, py, 2, RGB(hex: 0xF2EEF8)); c[Int(px) - 1, Int(py) - 1] = RGB(1, 1, 1)
            }
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0xC9B8FF), radius: 26, flicker: false))
        case .table:
            box(RGB(hex: 0x3A4756), inset: 2)
            c.rect(x0 + 5, y0 + 5, w - 10, h - 11, RGB(hex: 0x445466))
            // Trays and bowls along the table.
            for i in 0..<(w / 16) {
                c.rect(x0 + 6 + i * 16, y0 + 8, 8, 5, RGB(hex: 0x2A3540))
                c.disc(Double(x0 + 10 + i * 16), Double(y0 + h - 14), 2.5, RGB(hex: 0xC9A060))
            }
            // The emergency button in the middle.
            c.disc(cx, cy - 1, 5, RGB(hex: 0x1A1F28)); c.disc(cx, cy - 2, 3.6, RGB(hex: 0xE04A4A))
            c.disc(cx - 1, cy - 3, 1.2, RGB(hex: 0xFF9A9A))
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0xFF5A5A), radius: 28, flicker: false))
        case .filter:
            box(RGB(hex: 0x2F3B47))
            for i in 0..<(w / 16) { let fx = Double(x0 + 8 + i * 16); c.ring(fx, cy - 1, 4.5, RGB(hex: 0x6B7B8C)); c.disc(fx, cy - 1, 1.5, RGB(hex: 0x6B7B8C)) }
        case .ventGrate:
            box(RGB(hex: 0x1A0F0C))
            for y in stride(from: y0 + 4, to: y0 + h - 4, by: 3) { c.hline(x0 + 4, x0 + w - 5, y, RGB(hex: 0xFF7A3D)) }
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0xFF6A2D), radius: 46, flicker: true))
        case .lightPanel:
            box(RGB(hex: 0x2A2F3A))
            for i in 0..<(w / 5) { c.rect(x0 + 3 + i * 5, y0 + 4, 3, 6, RGB(hex: 0x111318)); c.rect(x0 + 3 + i * 5, y0 + 4 + (i % 2) * 3, 3, 3, RGB(hex: 0xFFD54A)) }
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0xFFD54A), radius: 22, flicker: false))
        case .ballastTank:
            let r = Double(min(w, h)) / 2 - 1.5
            c.disc(cx, cy + 1, r, RGB(0, 0, 0, 0.4))
            c.disc(cx, cy, r, RGB(hex: 0x6FA8B3)); c.disc(cx, cy, r - 1.5, RGB(hex: 0x1F5560))
            c.disc(cx - r * 0.35, cy - r * 0.35, r * 0.35, RGB(hex: 0x3F8A96))
            c.ring(cx, cy, r * 0.55, RGB(hex: 0x6FD3E0, alpha: 0.5))
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0x3FC8D8), radius: r * 2.4, flicker: false))
        case .sealPanel:
            box(RGB(hex: 0x2B3038))
            for i in 0..<(w / 5) { c.disc(Double(x0 + 5 + i * 5), Double(y0 + 6), 1.5, RGB(hex: i % 3 == 0 ? 0xFF4A4A : 0x4AFF7A)) }
            c.rect(x0 + 3, y0 + 9, w - 6, 3, RGB(hex: 0x1A1E24))
        case .oxygenConsole:
            box(RGB(hex: 0x1D2733)); screen(RGB(hex: 0x6FD3FF), lines: false)
            for i in 0..<4 { c.rect(x0 + 5 + i * 5, y0 + 9 - i, 3, 2 + i, RGB(hex: 0x9FE6FF)) }
        case .airlock:
            c.disc(cx, cy + 1, 7.5, RGB(0, 0, 0, 0.4))
            c.disc(cx, cy, 7.5, RGB(hex: 0x4A5262)); c.disc(cx, cy, 6, RGB(hex: 0x2E3542))
            c.ring(cx, cy, 4, RGB(hex: 0x9AA6B6))
            c.hline(Int(cx) - 4, Int(cx) + 3, Int(cy), RGB(hex: 0x9AA6B6)); c.vline(Int(cx), Int(cy) - 4, Int(cy) + 3, RGB(hex: 0x9AA6B6))
        case .eggBed:
            box(RGB(hex: 0x5A4636))
            c.rect(x0 + 3, y0 + 3, w - 6, h - 7, RGB(hex: 0x6E5A44))
            for i in 0..<12 {
                let ex = Double(x0 + 6) + hash2(i, 1, 4) * Double(w - 12), ey = Double(y0 + 6) + hash2(i, 2, 4) * Double(h - 14)
                c.disc(ex, ey, 2.2, RGB(hex: 0xFFB3C7, alpha: 0.9)); c[Int(ex), Int(ey)] = RGB(hex: 0xFF6F91)
            }
            lights.append(MapLight(x: cx, y: cy, color: RGB(hex: 0xFF8FB0), radius: 36, flicker: false))
        case .feeder:
            box(RGB(hex: 0x3D4A3A))
            for i in 0..<10 { c[x0 + 4 + Int(hash2(i, 3) * Double(w - 8)), y0 + 4 + Int(hash2(i, 5) * 6)] = RGB(hex: 0xC9A060) }
        }
    }
}
