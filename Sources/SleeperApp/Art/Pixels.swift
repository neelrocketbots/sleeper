import AppKit
import SleeperCore
import SpriteKit

/// An RGBA colour with the small amount of maths pixel art needs.
struct RGB: Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255; g = Double((hex >> 8) & 0xFF) / 255; b = Double(hex & 0xFF) / 255; a = alpha
    }
    static let clear = RGB(0, 0, 0, 0)
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t) }
    func lighter(_ t: Double) -> RGB { mix(RGB(1, 1, 1, a), t) }
    func darker(_ t: Double) -> RGB { mix(RGB(0, 0, 0, a), t) }
    func alpha(_ a: Double) -> RGB { RGB(r, g, b, a) }
    /// Shift toward another hue family, for coloured shadows and outlines (a hi-bit staple).
    func shade(_ t: Double, toward tint: RGB = RGB(hex: 0x1A1033)) -> RGB { mix(tint, t) }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }
    func desaturated(_ t: Double) -> RGB { let l = luminance; return mix(RGB(l, l, l, a), t) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// A plain RGBA pixel buffer that becomes a CGImage. Origin top-left.
final class PixelCanvas {
    let width: Int, height: Int
    private(set) var px: [RGB]

    init(_ w: Int, _ h: Int, fill: RGB = .clear) { width = w; height = h; px = Array(repeating: fill, count: w * h) }

    subscript(x: Int, y: Int) -> RGB {
        get { (x >= 0 && y >= 0 && x < width && y < height) ? px[y * width + x] : .clear }
        set { if x >= 0 && y >= 0 && x < width && y < height { px[y * width + x] = newValue } }
    }

    /// Paint over, respecting alpha.
    func blend(_ x: Int, _ y: Int, _ c: RGB) {
        guard x >= 0, y >= 0, x < width, y < height, c.a > 0 else { return }
        let d = px[y * width + x]
        if c.a >= 1 { px[y * width + x] = c; return }
        let oa = c.a + d.a * (1 - c.a)
        guard oa > 0 else { return }
        px[y * width + x] = RGB((c.r * c.a + d.r * d.a * (1 - c.a)) / oa, (c.g * c.a + d.g * d.a * (1 - c.a)) / oa,
                                (c.b * c.a + d.b * d.a * (1 - c.a)) / oa, oa)
    }

    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { blend(xx, yy, c) } }
    }

    func hline(_ x0: Int, _ x1: Int, _ y: Int, _ c: RGB) { for x in x0...x1 { blend(x, y, c) } }
    func vline(_ x: Int, _ y0: Int, _ y1: Int, _ c: RGB) { for y in y0...y1 { blend(x, y, c) } }

    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGB) {
        for y in Int(cy - r - 1)...Int(cy + r + 1) { for x in Int(cx - r - 1)...Int(cx + r + 1) {
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            if dx * dx + dy * dy <= r * r { blend(x, y, c) }
        } }
    }

    func ring(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGB) {
        for y in Int(cy - r - 1)...Int(cy + r + 1) { for x in Int(cx - r - 1)...Int(cx + r + 1) {
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            let d = (dx * dx + dy * dy).squareRoot()
            if abs(d - r) < 0.6 { blend(x, y, c) }
        } }
    }

    /// Draw a palette-indexed sprite. Spaces and dots are transparent.
    func sprite(_ rows: [String], at ox: Int, _ oy: Int, palette: [Character: RGB], flip: Bool = false) {
        for (y, row) in rows.enumerated() {
            let chars = Array(row)
            for (x, ch) in chars.enumerated() where ch != "." && ch != " " {
                guard let c = palette[ch] else { continue }
                let xx = flip ? ox + chars.count - 1 - x : ox + x
                blend(xx, oy + y, c)
            }
        }
    }

    func image() -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let c = px[i]
            let a = max(0, min(1, c.a))
            bytes[i * 4] = UInt8(max(0, min(255, c.r * a * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, c.g * a * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, c.b * a * 255)))
            bytes[i * 4 + 3] = UInt8(a * 255)
        }
        let data = CFDataCreate(nil, bytes, bytes.count)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    func texture() -> SKTexture {
        let t = SKTexture(cgImage: image())
        t.filteringMode = .nearest
        return t
    }

    func nsImage(scale: Int = 1) -> NSImage {
        NSImage(cgImage: image(), size: NSSize(width: width * scale, height: height * scale))
    }
}

/// A tiny deterministic hash for per-pixel noise.
@inline(__always) func hash2(_ x: Int, _ y: Int, _ s: Int = 0) -> Double {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ s &* 2_147_483_647)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65535
}
