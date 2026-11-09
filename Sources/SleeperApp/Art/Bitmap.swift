import AppKit
import SleeperCore

/// An RGBA bitmap for cutting generated art: background removal, splitting sheets, recolouring.
struct Bitmap {
    var w: Int, h: Int
    var px: [UInt8]  // RGBA, premultiplied

    init(_ img: CGImage) {
        w = img.width; h = img.height
        px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    init(w: Int, h: Int) { self.w = w; self.h = h; px = [UInt8](repeating: 0, count: w * h * 4) }

    func image() -> CGImage {
        let data = CFDataCreate(nil, px, px.count)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Flood-fills a white backdrop from the edges to transparent, and softens the cut.
    mutating func removeBackground() {
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func isBG(_ i: Int) -> Bool {
            let r = Int(px[i * 4]), g = Int(px[i * 4 + 1]), b = Int(px[i * 4 + 2])
            return r > 222 && g > 222 && b > 222 && max(r, g, b) - min(r, g, b) < 18
        }
        for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
        for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
        while let i = stack.popLast() {
            if seen[i] { continue }
            seen[i] = true
            guard isBG(i) else { continue }
            for k in 0..<4 { px[i * 4 + k] = 0 }
            let x = i % w, y = i / w
            if x > 0 { stack.append(i - 1) }; if x < w - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - w) }; if y < h - 1 { stack.append(i + w) }
        }
        for i in 0..<(w * h) where px[i * 4 + 3] > 0 {
            let x = i % w, y = i / w
            guard x > 0, y > 0, x < w - 1, y < h - 1 else { continue }
            if [i - 1, i + 1, i - w, i + w].contains(where: { px[$0 * 4 + 3] == 0 }) {
                let l = (Int(px[i * 4]) + Int(px[i * 4 + 1]) + Int(px[i * 4 + 2])) / 3
                if l > 200 { let a = Double(255 - l) / 55; for k in 0..<4 { px[i * 4 + k] = UInt8(Double(px[i * 4 + k]) * a) } }
            }
        }
    }

    /// Splits a sheet into pieces at empty columns, each trimmed to its content.
    func split() -> [Bitmap] {
        var colHas = [Bool](repeating: false, count: w)
        for x in 0..<w { for y in 0..<h where px[(y * w + x) * 4 + 3] > 40 { colHas[x] = true; break } }
        var runs: [(Int, Int)] = []
        var start: Int?
        for x in 0...w {
            let on = x < w && colHas[x]
            if on && start == nil { start = x }
            if !on, let s = start { if x - s > 40 { runs.append((s, x - 1)) }; start = nil }
        }
        return runs.map { (x0, x1) in
            var y0 = h, y1 = 0
            for y in 0..<h { for x in x0...x1 where px[(y * w + x) * 4 + 3] > 40 { y0 = min(y0, y); y1 = max(y1, y); break } }
            var out = Bitmap(w: x1 - x0 + 1, h: max(1, y1 - y0 + 1))
            for y in 0..<out.h { for x in 0..<out.w {
                let si = ((y0 + y) * w + x0 + x) * 4, di = (y * out.w + x) * 4
                for k in 0..<4 { out.px[di + k] = px[si + k] }
            } }
            return out
        }
    }

    /// Recolours the light grey body, keeping its painted shading and texture; the dark vest, eyes, ink lines and
    /// gold buckle are left alone. `dim` greys the result (bodies).
    func tinted(_ color: PlayerColor, dim: Double = 0) -> CGImage {
        var b = self
        let t = (Double((color.hex >> 16) & 0xFF) / 255, Double((color.hex >> 8) & 0xFF) / 255, Double(color.hex & 0xFF) / 255)
        for i in 0..<(w * h) {
            let a = Double(px[i * 4 + 3]) / 255
            guard a > 0 else { continue }
            let r = Double(px[i * 4]) / 255 / a, g = Double(px[i * 4 + 1]) / 255 / a, bl = Double(px[i * 4 + 2]) / 255 / a
            let l = 0.299 * r + 0.587 * g + 0.114 * bl
            let sat = max(r, g, bl) - min(r, g, bl)
            var o = (r, g, bl)
            if sat < 0.14 && l > 0.4 {
                let k = l / 0.72
                let lift = k > 1 ? (k - 1) * 0.6 : 0
                let c = (min(1, t.0 * k + lift), min(1, t.1 * k + lift), min(1, t.2 * k + lift))
                // Keep a touch of the original wash so it still reads as paint.
                o = (c.0 * 0.9 + r * 0.1, c.1 * 0.9 + g * 0.1, c.2 * 0.9 + bl * 0.1)
            }
            if dim > 0 { let m = 0.299 * o.0 + 0.587 * o.1 + 0.114 * o.2; o = (o.0 + (m - o.0) * dim, o.1 + (m - o.1) * dim, o.2 + (m - o.2) * dim) }
            b.px[i * 4] = UInt8(min(255, o.0 * a * 255)); b.px[i * 4 + 1] = UInt8(min(255, o.1 * a * 255)); b.px[i * 4 + 2] = UInt8(min(255, o.2 * a * 255))
        }
        return b.image()
    }

    /// The top of the head: the first row with paint in the middle third, and the centre of that paint.
    func headTop() -> (x: Double, y: Int) {
        let x0 = w / 3, x1 = 2 * w / 3
        for y in 0..<h {
            var sum = 0, n = 0
            for x in x0..<x1 where px[(y * w + x) * 4 + 3] > 120 { sum += x; n += 1 }
            if n > 3 { return (Double(sum) / Double(n), y) }
        }
        return (Double(w) / 2, 0)
    }
}
