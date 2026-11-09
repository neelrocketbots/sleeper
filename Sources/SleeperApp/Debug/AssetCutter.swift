import AppKit

/// `Sleeper --cut-assets <raw-dir> <assets-dir>`: turns generated sheets (white backgrounds) into trimmed sprites,
/// resized for the game, plus the floor, tunnel and wall textures.
@MainActor enum AssetCutter {
    static func run(raw: URL, out: URL) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func sheet(_ name: String, _ names: [String], height: Int? = nil, width: Int? = nil) throws {
            guard let img = Bitmap.load(raw.appendingPathComponent("\(name).png")) else { print("missing \(name)"); return }
            var b = Bitmap(img)
            b.removeBackground()
            let parts = b.split()
            print("\(name): \(parts.count) parts (want \(names.count))")
            for (part, n) in zip(parts, names) {
                let s: Double
                if let height { s = min(1, Double(height) / Double(part.h)) } else { s = min(1, Double(width ?? 384) / Double(part.w)) }
                try save(resize(part.image(), scale: s), out.appendingPathComponent("\(n).png"))
            }
        }
        try sheet("axolotl", ["crew-idle", "crew-walk1", "crew-walk2", "crew-body"], height: 256)
        try sheet("hats", ["hat-captain", "hat-beanie", "hat-headlamp", "hat-seashell", "hat-crown"], width: 150)
        try sheet("props-a", ["prop-console", "prop-sonarDish", "prop-oxygenConsole", "prop-lightPanel"])
        try sheet("props-b", ["prop-kelpTank", "prop-ballastTank", "prop-pearlBench", "prop-chartTable"])
        try sheet("props-c", ["prop-table", "prop-filter", "prop-eggBed", "prop-feeder"], width: 640)
        try sheet("props-d", ["prop-ventGrate", "prop-airlock", "prop-sealPanel"])
        try sheet("table2", ["prop-table2"], width: 640)
        for (name, w, h) in [("floor", 512, 512), ("corridor", 512, 512), ("wall", 1152, 768)] {
            guard let img = Bitmap.load(raw.appendingPathComponent("\(name).png")) else { continue }
            try save(resize(img, to: CGSize(width: w, height: h)), out.appendingPathComponent("tex-\(name).png"))
        }
    }

    static func resize(_ img: CGImage, scale: Double) -> CGImage {
        resize(img, to: CGSize(width: max(1, Double(img.width) * scale), height: max(1, Double(img.height) * scale)))
    }

    static func resize(_ img: CGImage, to size: CGSize) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()!
    }

    static func save(_ img: CGImage, _ url: URL) throws {
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
    }
}
